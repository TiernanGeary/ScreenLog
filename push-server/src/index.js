// deny push server — Cloudflare Worker
//
// Sends real APNs *alert* pushes so friend-request events (approved / denied /
// new request) reach the recipient even when the app is force-quit.
//
// Endpoints (all expect header `x-deny-secret: <APP_SHARED_SECRET>`):
//   POST /register  { profileID, token, environment? }  -> stores token
//   POST /notify    { toProfileID, title, body, requestID? } -> sends alert push
//   POST /group-pool-exhausted { toProfileID/profileIDs, groupID } -> sends silent push
//
// Secrets (via `wrangler secret put`):
//   APNS_AUTH_KEY      contents of the AuthKey_XXXX.p8 (PEM)
//   APP_SHARED_SECRET  shared secret the app sends in x-deny-secret
// Vars (wrangler.toml): APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID, APNS_ENVIRONMENT

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // Public, unauthenticated GET pages for the App Store listing.
    if (request.method === "GET") {
      if (url.pathname === "/privacy" || url.pathname === "/privacy/") {
        return html(PRIVACY_HTML);
      }
      if (url.pathname === "/support" || url.pathname === "/support/") {
        return html(SUPPORT_HTML);
      }
      if (url.pathname.startsWith("/invite/")) {
        const raw = url.pathname.slice("/invite/".length).split("/")[0];
        const code = (raw || "").replace(/[^a-zA-Z0-9]/g, "").toUpperCase().slice(0, 16);
        return html(inviteLandingHTML(code));
      }
      if (url.pathname.startsWith("/group-invite/")) {
        const raw = url.pathname.slice("/group-invite/".length).split("/")[0];
        const code = (raw || "").replace(/[^a-zA-Z0-9]/g, "").toUpperCase().slice(0, 16);
        return html(inviteLandingHTML(code, { scheme: "deny://group-invite/", heading: "You've been invited to a Deny group" }));
      }
      return json({ error: "not found" }, 404);
    }

    if (request.method !== "POST") {
      return json({ error: "method not allowed" }, 405);
    }

    if (request.headers.get("x-deny-secret") !== env.APP_SHARED_SECRET) {
      return json({ error: "unauthorized" }, 401);
    }

    try {
      if (url.pathname === "/register") {
        return await handleRegister(request, env);
      }
      if (url.pathname === "/notify") {
        return await handleNotify(request, env);
      }
      if (url.pathname === "/group-pool-exhausted") {
        return await handleGroupPoolExhausted(request, env);
      }
      return json({ error: "not found" }, 404);
    } catch (err) {
      return json({ error: String(err && err.message ? err.message : err) }, 500);
    }
  },
};

async function handleRegister(request, env) {
  const body = await request.json();
  const profileID = String(body.profileID || "").trim();
  const token = String(body.token || "").trim();
  if (!profileID || !token) {
    return json({ error: "profileID and token required" }, 400);
  }

  const record = {
    token,
    environment: body.environment === "sandbox" ? "sandbox" : "production",
    updatedAt: Date.now(),
  };
  await env.TOKENS.put(`profile:${profileID}`, JSON.stringify(record));
  return json({ ok: true });
}

async function handleNotify(request, env) {
  const body = await request.json();
  const toProfileID = String(body.toProfileID || "").trim();
  const title = String(body.title || "deny").slice(0, 120);
  const message = String(body.body || "").slice(0, 240);
  if (!toProfileID) {
    return json({ error: "toProfileID required" }, 400);
  }

  const payload = {
    aps: {
      alert: { title, body: message },
      sound: "default",
      category: "friend-time-request",
      "interruption-level": "time-sensitive",
      // Wake the app so it refetches friends/requests immediately instead of
      // waiting for the next foreground poll.
      "content-available": 1,
    },
  };
  if (body.requestID) {
    // Match the key the app reads in didReceive (FriendRequestNotificationService
    // .requestIDUserInfoKey) so tapping the push routes to the request feed.
    payload.friendRequestID = String(body.requestID);
  }

  const result = await sendAPNsToProfile(env, toProfileID, payload, {
    "apns-push-type": "alert",
    "apns-priority": "10",
  });
  if (result.ok) {
    return json({ ok: true });
  }
  if (result.reason === "no token for recipient") {
    return json(result);
  }
  return json(result, 502);
}

async function handleGroupPoolExhausted(request, env) {
  const body = await request.json();
  const groupID = String(body.groupID || "").trim();
  const profileIDs = Array.isArray(body.profileIDs) ? body.profileIDs : body.toProfileID ? [body.toProfileID] : [];
  if (profileIDs.length < 1 || profileIDs.length > 32) {
    return json({ error: "toProfileID or profileIDs required" }, 400);
  }
  const recipients = [...new Set(profileIDs.map((id) => String(id || "").trim()).filter(Boolean))].slice(0, 32);

  if (!groupID) {
    return json({ error: "groupID required" }, 400);
  }
  if (recipients.length === 0) {
    return json({ error: "toProfileID or profileIDs required" }, 400);
  }

  const payload = {
    aps: {
      "content-available": 1,
    },
    poolExhaustedGroupID: groupID,
  };

  const results = [];
  for (const profileID of recipients) {
    const result = await sendAPNsToProfile(env, profileID, payload, {
      "apns-push-type": "background",
      "apns-priority": "5",
    });
    results.push({ profileID, ...result });
  }

  const hasAPNsFailure = results.some((result) => !result.ok && result.reason !== "no token for recipient");
  return json({ ok: results.every((result) => result.ok), results }, hasAPNsFailure ? 502 : 200);
}

async function sendAPNsToProfile(env, profileID, payload, apnsHeaders) {
  const raw = await env.TOKENS.get(`profile:${profileID}`);
  if (!raw) {
    return { ok: false, reason: "no token for recipient" };
  }
  const record = JSON.parse(raw);

  const jwt = await makeAPNsJWT(env);
  const host = (record.environment === "sandbox" || env.APNS_ENVIRONMENT === "sandbox")
    ? "https://api.sandbox.push.apple.com"
    : "https://api.push.apple.com";

  const res = await fetch(`${host}/3/device/${record.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": env.APNS_BUNDLE_ID,
      ...apnsHeaders,
    },
    body: JSON.stringify(payload),
  });

  if (res.status === 200) {
    return { ok: true };
  }

  // 410 = token no longer valid; drop it so we stop trying.
  if (res.status === 410 || res.status === 400) {
    await env.TOKENS.delete(`profile:${profileID}`);
  }
  const text = await res.text();
  return { ok: false, status: res.status, apns: text };
}

// --- APNs token-based auth (ES256 JWT signed with the .p8 key) ---

let cachedJWT = null;
let cachedJWTExpiry = 0;

async function makeAPNsJWT(env) {
  const now = Math.floor(Date.now() / 1000);
  // APNs tokens are valid up to 60 min; refresh well before that.
  if (cachedJWT && now < cachedJWTExpiry - 600) {
    return cachedJWT;
  }

  const header = { alg: "ES256", kid: env.APNS_KEY_ID };
  const claims = { iss: env.APNS_TEAM_ID, iat: now };
  const signingInput = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(claims))}`;

  const key = await importPKCS8(env.APNS_AUTH_KEY);
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput)
  );

  cachedJWT = `${signingInput}.${base64urlBytes(new Uint8Array(signature))}`;
  cachedJWTExpiry = now + 3600;
  return cachedJWT;
}

async function importPKCS8(pem) {
  const clean = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(clean), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );
}

function base64url(str) {
  return base64urlBytes(new TextEncoder().encode(str));
}

function base64urlBytes(bytes) {
  let binary = "";
  for (const b of bytes) {
    binary += String.fromCharCode(b);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function html(body, status = 200) {
  return new Response(body, {
    status,
    headers: { "content-type": "text/html; charset=utf-8" },
  });
}

// Public App Store product page for Deny.
const APP_STORE_URL = "https://apps.apple.com/app/id6773738211";

// Invite landing page: tries to open the app via the deny:// scheme and falls
// back to the App Store if it isn't installed.
function inviteLandingHTML(code, opts = { scheme: "deny://invite/", heading: "You've been invited to Deny" }) {
  const appLink = `${opts.scheme}${code}`;
  const isDefaultFriendInvite = opts.scheme === "deny://invite/" && opts.heading === "You've been invited to Deny";
  const pageTitle = isDefaultFriendInvite ? "Deny — Friend Invite" : opts.heading;
  return `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${pageTitle}</title><style>${PAGE_STYLE}
  .wrap { text-align: center; padding-top: 60px; }
  .btn { display: inline-block; margin: 8px; padding: 14px 22px; border-radius: 14px;
         font-weight: 600; text-decoration: none; }
  .primary { background: #ff6a00; color: #fff; }
  .secondary { border: 1px solid #ff6a00; color: #ff6a00; }
  .code { font: 600 15px ui-monospace, Menlo, monospace; color: #8a8a8e; margin-top: 18px; }
</style></head>
<body>
<div class="wrap">
  <h1>${opts.heading}</h1>
  <p>Opening the app to connect you…<br>Don't have it yet? Grab it free below.</p>
  <p>
    <a class="btn primary" href="${appLink}">Open in Deny</a>
    <a class="btn secondary" href="${APP_STORE_URL}">Get the app</a>
  </p>
  <p class="code">Invite code: ${code}</p>
</div>
<script>
  (function () {
    var code = ${JSON.stringify(code)};
    if (!code) { window.location.replace(${JSON.stringify(APP_STORE_URL)}); return; }
    // Try to open the app; if still here after a beat, send to the App Store.
    var t = setTimeout(function () {
      window.location.replace(${JSON.stringify(APP_STORE_URL)});
    }, 1200);
    // If the app opens, the page is backgrounded — cancel the App Store redirect.
    document.addEventListener("visibilitychange", function () {
      if (document.hidden) { clearTimeout(t); }
    });
    window.location.replace(${JSON.stringify(opts.scheme)} + code);
  })();
</script>
</body></html>`;
}

const PAGE_STYLE = `
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; }
  body {
    font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    max-width: 720px; margin: 0 auto; padding: 40px 22px 80px; color: #1c1c1e;
  }
  @media (prefers-color-scheme: dark) { body { color: #e5e5ea; background: #000; } }
  h1 { font-size: 28px; letter-spacing: -0.02em; }
  h2 { font-size: 19px; margin-top: 34px; }
  a { color: #ff6a00; }
  .muted { color: #8a8a8e; font-size: 14px; }
  ul { padding-left: 20px; }
  li { margin: 6px 0; }
`;

const PRIVACY_HTML = `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Deny — Privacy Policy</title><style>${PAGE_STYLE}</style></head>
<body>
<h1>Deny — Privacy Policy</h1>
<p class="muted">Last updated: June 14, 2026</p>

<p>Deny (“the app”, “we”, “us”) helps you lock distracting apps and ask friends
for permission before unlocking them. This policy explains what we collect, why,
and your choices. We do not sell your data and we do not use it for advertising.</p>

<h2>Information you provide</h2>
<ul>
  <li><strong>Account.</strong> When you sign in with Apple we receive a unique
  identifier and, if you choose to share it, your name. We use this to create your
  account and identify you to friends you connect with.</li>
  <li><strong>Profile.</strong> A display name and avatar (a color or an image you
  choose) so friends can recognize you.</li>
  <li><strong>Request photos.</strong> If you attach a photo when asking a friend
  for screen time, that photo is shared only with the friend(s) you send the
  request to.</li>
</ul>

<h2>Information the app generates</h2>
<ul>
  <li><strong>Screen time summaries.</strong> Daily summaries of your device usage
  (such as total time and per-category or per-app durations) are created on your
  device using Apple’s Screen Time framework. If you connect with a friend, the
  summaries you choose to share are visible to that friend so they can see your
  progress. You can stop sharing at any time.</li>
  <li><strong>Blocking settings.</strong> The groups of apps you block and your
  unlock rules are stored to keep your blocks working across launches.</li>
</ul>

<h2>Device data we never see</h2>
<p>Deny uses Apple’s Family Controls / Screen Time APIs. The identities of the
specific apps you block are represented by opaque tokens provided by iOS; Apple
does not reveal the underlying app names to us, and we cannot read your messages,
browsing, or app content.</p>

<h2>Push notifications</h2>
<p>To deliver alerts (for example, when a friend approves a request) we store a
device push token associated with your account identifier. It is used only to
send you these notifications.</p>

<h2>Where data is stored</h2>
<p>Account, profile, screen-time summaries, requests, and photos are stored with
our backend provider Supabase on servers located in the United States. Push
tokens are stored with Cloudflare. We retain data while your account is active.</p>

<h2>Deleting your data</h2>
<p>You can delete your account at any time from Settings inside the app, which
removes your profile, summaries, requests, and photos from our backend. You may
also contact us using the email below.</p>

<h2>Children</h2>
<p>Deny is not directed to children under 13 and we do not knowingly collect data
from them.</p>

<h2>Contact</h2>
<p>Questions or requests: <a href="mailto:info@stepai.co.jp">info@stepai.co.jp</a></p>
</body></html>`;

const SUPPORT_HTML = `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Deny — Support</title><style>${PAGE_STYLE}</style></head>
<body>
<h1>Deny — Support</h1>
<p>Need help with Deny? We’re happy to assist.</p>

<h2>Contact us</h2>
<p>Email <a href="mailto:info@stepai.co.jp">info@stepai.co.jp</a> and we’ll get
back to you as soon as we can.</p>

<h2>Common questions</h2>
<ul>
  <li><strong>How do I block apps?</strong> Create a block group, choose the apps
  to block, and set a schedule or time limit. Deny keeps them locked using Apple’s
  Screen Time controls.</li>
  <li><strong>How do temporary unlocks work?</strong> If a group allows them, you
  can unlock for a set number of minutes. A live countdown shows when it re-locks.</li>
  <li><strong>How do friends help?</strong> Connect with a friend using an invite
  code. You can ask them for screen time, and they can approve or deny your
  request.</li>
  <li><strong>How do I delete my account?</strong> Open Settings in the app and
  choose Delete Account. This removes your data from our servers.</li>
</ul>

<h2>Privacy</h2>
<p>See our <a href="/privacy">Privacy Policy</a>.</p>
</body></html>`;

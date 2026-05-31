// deny push server — Cloudflare Worker
//
// Sends real APNs *alert* pushes so friend-request events (approved / denied /
// new request) reach the recipient even when the app is force-quit.
//
// Endpoints (all expect header `x-deny-secret: <APP_SHARED_SECRET>`):
//   POST /register  { profileID, token, environment? }  -> stores token
//   POST /notify    { toProfileID, title, body, requestID? } -> sends alert push
//
// Secrets (via `wrangler secret put`):
//   APNS_AUTH_KEY      contents of the AuthKey_XXXX.p8 (PEM)
//   APP_SHARED_SECRET  shared secret the app sends in x-deny-secret
// Vars (wrangler.toml): APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID, APNS_ENVIRONMENT

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return json({ error: "method not allowed" }, 405);
    }

    if (request.headers.get("x-deny-secret") !== env.APP_SHARED_SECRET) {
      return json({ error: "unauthorized" }, 401);
    }

    const url = new URL(request.url);
    try {
      if (url.pathname === "/register") {
        return await handleRegister(request, env);
      }
      if (url.pathname === "/notify") {
        return await handleNotify(request, env);
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

  const raw = await env.TOKENS.get(`profile:${toProfileID}`);
  if (!raw) {
    return json({ ok: false, reason: "no token for recipient" });
  }
  const record = JSON.parse(raw);

  const jwt = await makeAPNsJWT(env);
  const host = (record.environment === "sandbox" || env.APNS_ENVIRONMENT === "sandbox")
    ? "https://api.sandbox.push.apple.com"
    : "https://api.push.apple.com";

  const payload = {
    aps: {
      alert: { title, body: message },
      sound: "default",
      "interruption-level": "time-sensitive",
    },
  };
  if (body.requestID) {
    payload.requestID = String(body.requestID);
  }

  const res = await fetch(`${host}/3/device/${record.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": env.APNS_BUNDLE_ID,
      "apns-push-type": "alert",
      "apns-priority": "10",
    },
    body: JSON.stringify(payload),
  });

  if (res.status === 200) {
    return json({ ok: true });
  }

  // 410 = token no longer valid; drop it so we stop trying.
  if (res.status === 410 || res.status === 400) {
    await env.TOKENS.delete(`profile:${toProfileID}`);
  }
  const text = await res.text();
  return json({ ok: false, status: res.status, apns: text }, 502);
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

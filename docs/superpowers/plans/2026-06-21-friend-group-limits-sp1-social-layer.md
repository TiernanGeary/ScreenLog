# Friend-Group SP1 (Social Layer) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Project model (CLAUDE.md):** Claude plans & verifies; **Codex implements** (`/codex:rescue --write`). Codex's sandbox blocks `.git`, so **Claude performs all commits** (English messages, append the `Co-Authored-By` trailer). Commit steps show staging + message only.

**Goal:** Ship the social foundation for friend groups — create a group, invite friends by link (multi-redeem), join, list members with a "configured" status — so the per-member / pool / approval sub-projects can build on it.

**Architecture:** A new Supabase schema (`groups`, `group_members`, `group_invites` + RPCs) applied out-of-band to the Supabase project (this repo has **no** migration pipeline; the SQL is a deliverable the owner applies). The iOS app gets pure Core models (unit-tested), thin RPC wrappers in the existing `SupabaseSnapshotStore`/`SupabaseRowMapping`, `AppModel` methods, a `deny://group-invite/<code>` deep link, and group UI. The push-server invite landing is extended to group codes.

**Tech Stack:** Supabase (Postgres + PL/pgSQL RPCs, RLS), Swift Package `ScreenTimeSharingCore` + XCTest (`swift test`), SwiftUI, Cloudflare Worker (`push-server`, JS).

**Spec:** `docs/superpowers/specs/2026-06-21-friend-group-limits-design.md`
**Base branch:** `feature/friend-group-limits` (from main `95a7f6a`).

## Global Constraints

- **No code writing by Claude** beyond trivial ≤3-line fixes / config; Codex implements. Claude commits (Codex sandbox blocks `.git`).
- **Supabase schema is applied OUT-OF-BAND.** The repo has no SQL migrations. Deliver SQL as a file; the owner applies it in the Supabase SQL editor. iOS RPC calls assume the functions exist; they **cannot** be unit-tested locally — verified by `xcodebuild` compile + manual once SQL is applied.
- **RPC names (verbatim):** `create_group`, `create_group_invite`, `peek_group_invite`, `redeem_group_invite`, `get_my_groups`, `get_group`, `leave_group`, `remove_group_member`, `delete_group`.
- **Decisions (verbatim from spec §2):** group `mode` ∈ {`per_member`,`pool`} chosen at creation; daily reset in **owner timezone**; app target = creator-defined **app-name list** (members pick locally, honor-system); **owner cannot leave** (only `delete_group`); members can `leave_group`; invites are **multi-redeem**; auth (Apple Sign In) required to create/join.
- **Core test command:** `swift test` (covers `ScreenTimeSharingCore` only; keep the existing suite green).
- **New Core files** are auto-discovered by SwiftPM (`swift test`) AND must be **registered in the Xcode app target** (the app compiles Core sources directly — see `docs` memory; app files do NOT `import ScreenTimeSharingCore`). New **app-layer** files must also be registered in the `.xcodeproj` app target. Use the `xcodeproj` ruby gem (installed) or hand-add the 4 pbxproj entries (sequential IDs: `C0…` PBXFileReference, `B1…` PBXBuildFile, the relevant PBXGroup child, the app `PBXSourcesBuildPhase`).
- **App build:** `xcodebuild -project ScreenTimeSharing.xcodeproj -scheme ScreenTimeSharing -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`.
- **UI copy:** English (match existing views).

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `supabase/migrations/0001_group_social_layer.sql` | **NEW** Postgres tables + RLS + RPCs for the social layer (owner applies) | Create (Task 1) |
| `Sources/ScreenTimeSharingCore/FriendGroupModels.swift` | **NEW** pure group models + helpers (mode, role, group, member, config, validation, summaries, code formatting) | Create (Tasks 2–3) |
| `Tests/ScreenTimeSharingCoreTests/FriendGroupModelsTests.swift` | **NEW** unit tests | Create (Tasks 2–3) |
| `ScreenTimeSharing/Services/SupabaseRowMapping.swift` | Add group RPC row types + deep-link parsing for group invites | Modify (Task 4) |
| `ScreenTimeSharing/Services/SupabaseSnapshotStore.swift` | Add group RPC wrappers | Modify (Task 5) |
| `ScreenTimeSharing/AppModel.swift` | Group state + methods (create/fetch/redeem/leave/remove/delete/incoming-invite) | Modify (Task 6) |
| `ScreenTimeSharing/ScreenTimeSharingApp.swift` | Route `deny://group-invite/<code>` to `presentIncomingGroupInvite` | Modify (Task 7) |
| `ScreenTimeSharing/Views/GroupsView.swift` | **NEW** group list, create sheet, join, detail/manage UI | Create (Task 8) |
| `push-server/src/index.js` | Serve a group-invite landing (reuse the invite landing) | Modify (Task 9) |

New Core file → register in app target (Task 2 step). New app-layer `GroupsView.swift` → register in app target (Task 8 step).

Symbols referenced from existing code (confirm current line by symbol; the rework may have shifted lines):
- Invite pattern: `SupabaseSnapshotStore.createInvite/peekInvite/redeemInvite` (~L215–266), `CreatedInvite`/`IncomingInvite`/`RedeemedInvite` + `InviteDeepLink` (`SupabaseRowMapping.swift` ~L279–369), `AppModel.createInvite/presentIncomingInvite/redeemInvite` (~L1158–1235), `ScreenTimeSharingApp.onOpenURL` (~L29–36), `AppConfiguration.inviteWebLink(code)`.
- Identity: `SupabaseSnapshotStore.currentUserID()` (~L60–69), `profiles` upsert (~L117).
- push-server invite landing: `push-server/src/index.js` `/invite/<code>` (~L27–31, `inviteLandingHTML` ~L206–246).

---

## Task 1: Supabase schema + RPCs (deliverable SQL)

Author the social-layer SQL. This is applied by the **owner** in Supabase (not by us). Verification = SQL reviewed for correctness; no local run.

**Files:**
- Create: `supabase/migrations/0001_group_social_layer.sql`

- [ ] **Step 1: Write the SQL file**

```sql
-- Friend groups: social layer (SP1). Apply in the Supabase SQL editor.
-- Assumes existing tables: public.profiles(id uuid pk references auth.users).

create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 60),
  mode text not null check (mode in ('per_member','pool')),
  owner_time_zone text not null default 'UTC',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.group_members (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('owner','member')),
  joined_at timestamptz not null default now(),
  configured_at timestamptz,
  left_at timestamptz,
  primary key (group_id, user_id)
);

create table if not exists public.group_config (
  group_id uuid primary key references public.groups(id) on delete cascade,
  app_names text[] not null default '{}',
  per_member_limit_seconds int,
  pool_seconds int,
  reset text not null default 'daily' check (reset = 'daily'),
  approvals_required int not null default 1 check (approvals_required >= 1),
  updated_at timestamptz not null default now()
);

create table if not exists public.group_invites (
  code text primary key,
  group_id uuid not null references public.groups(id) on delete cascade,
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.group_config enable row level security;
alter table public.group_invites enable row level security;

-- Helper: is the current user an active member of a group?
create or replace function public.is_group_member(p_group_id uuid)
returns boolean language sql security definer stable as $$
  select exists (
    select 1 from public.group_members m
    where m.group_id = p_group_id and m.user_id = auth.uid() and m.left_at is null
  );
$$;

create policy groups_select on public.groups for select
  using (public.is_group_member(id));
create policy group_members_select on public.group_members for select
  using (public.is_group_member(group_id));
create policy group_config_select on public.group_config for select
  using (public.is_group_member(group_id));
-- All writes go through SECURITY DEFINER RPCs below; no direct write policies.

-- 8-char A–Z2–9 code (no ambiguous chars).
create or replace function public.gen_group_code() returns text language sql as $$
  select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
    (floor(random()*32)+1)::int, 1), '') from generate_series(1,8);
$$;

create or replace function public.create_group(
  p_name text, p_mode text, p_app_names text[],
  p_limit_seconds int, p_approvals_required int, p_owner_time_zone text)
returns table(group_id uuid, code text)
language plpgsql security definer as $$
declare g_id uuid; inv_code text;
begin
  if auth.uid() is null then raise exception 'auth required'; end if;
  insert into public.groups(owner_id, name, mode, owner_time_zone)
    values (auth.uid(), p_name, p_mode, coalesce(p_owner_time_zone,'UTC'))
    returning id into g_id;
  insert into public.group_members(group_id, user_id, role) values (g_id, auth.uid(), 'owner');
  insert into public.group_config(group_id, app_names,
      per_member_limit_seconds, pool_seconds, approvals_required)
    values (g_id, coalesce(p_app_names,'{}'),
      case when p_mode='per_member' then p_limit_seconds end,
      case when p_mode='pool' then p_limit_seconds end,
      greatest(coalesce(p_approvals_required,1),1));
  inv_code := public.gen_group_code();
  insert into public.group_invites(code, group_id, created_by, expires_at)
    values (inv_code, g_id, auth.uid(), now() + interval '30 days');
  return query select g_id, inv_code;
end; $$;

create or replace function public.create_group_invite(p_group_id uuid)
returns table(code text, expires_at timestamptz)
language plpgsql security definer as $$
declare inv_code text; exp timestamptz;
begin
  if not exists (select 1 from public.groups where id=p_group_id and owner_id=auth.uid())
    then raise exception 'owner only'; end if;
  inv_code := public.gen_group_code(); exp := now() + interval '30 days';
  insert into public.group_invites(code, group_id, created_by, expires_at)
    values (inv_code, p_group_id, auth.uid(), exp);
  return query select inv_code, exp;
end; $$;

create or replace function public.peek_group_invite(p_code text)
returns table(group_id uuid, group_name text, owner_display_name text, mode text)
language plpgsql security definer as $$
begin
  return query
  select g.id, g.name, p.display_name, g.mode
  from public.group_invites i
  join public.groups g on g.id=i.group_id
  join public.profiles p on p.id=g.owner_id
  where i.code = upper(p_code) and i.expires_at > now();
end; $$;

create or replace function public.redeem_group_invite(p_code text)
returns table(group_id uuid, group_name text)
language plpgsql security definer as $$
declare g_id uuid; g_name text;
begin
  if auth.uid() is null then raise exception 'auth required'; end if;
  select i.group_id, g.name into g_id, g_name
    from public.group_invites i join public.groups g on g.id=i.group_id
    where i.code = upper(p_code) and i.expires_at > now();
  if g_id is null then raise exception 'invalid or expired code'; end if;
  insert into public.group_members(group_id, user_id, role)
    values (g_id, auth.uid(), 'member')
    on conflict (group_id, user_id) do update set left_at = null;  -- idempotent / rejoin
  return query select g_id, g_name;
end; $$;

create or replace function public.get_my_groups()
returns table(id uuid, name text, mode text, owner_id uuid, owner_time_zone text,
  role text, configured_at timestamptz, member_count int,
  app_names text[], per_member_limit_seconds int, pool_seconds int,
  approvals_required int, updated_at timestamptz)
language sql security definer stable as $$
  select g.id, g.name, g.mode, g.owner_id, g.owner_time_zone,
    m.role, m.configured_at,
    (select count(*) from public.group_members mm where mm.group_id=g.id and mm.left_at is null)::int,
    c.app_names, c.per_member_limit_seconds, c.pool_seconds, c.approvals_required, c.updated_at
  from public.group_members m
  join public.groups g on g.id=m.group_id
  join public.group_config c on c.group_id=g.id
  where m.user_id = auth.uid() and m.left_at is null;
$$;

create or replace function public.get_group(p_group_id uuid)
returns jsonb language sql security definer stable as $$
  select case when public.is_group_member(p_group_id) then jsonb_build_object(
    'group', (select to_jsonb(g) from public.groups g where g.id=p_group_id),
    'config', (select to_jsonb(c) from public.group_config c where c.group_id=p_group_id),
    'members', (select coalesce(jsonb_agg(jsonb_build_object(
        'user_id', m.user_id, 'display_name', p.display_name,
        'avatar_color_hex', p.avatar_color_hex, 'role', m.role,
        'joined_at', m.joined_at, 'configured_at', m.configured_at)), '[]'::jsonb)
      from public.group_members m join public.profiles p on p.id=m.user_id
      where m.group_id=p_group_id and m.left_at is null)
  ) end;
$$;

create or replace function public.set_member_configured(p_group_id uuid, p_configured boolean)
returns void language plpgsql security definer as $$
begin
  update public.group_members set configured_at = case when p_configured then now() else null end
    where group_id=p_group_id and user_id=auth.uid();
end; $$;

create or replace function public.leave_group(p_group_id uuid)
returns void language plpgsql security definer as $$
begin
  if exists (select 1 from public.groups where id=p_group_id and owner_id=auth.uid())
    then raise exception 'owner cannot leave; delete the group instead'; end if;
  update public.group_members set left_at = now()
    where group_id=p_group_id and user_id=auth.uid();
end; $$;

create or replace function public.remove_group_member(p_group_id uuid, p_user_id uuid)
returns void language plpgsql security definer as $$
begin
  if not exists (select 1 from public.groups where id=p_group_id and owner_id=auth.uid())
    then raise exception 'owner only'; end if;
  if p_user_id = auth.uid() then raise exception 'use delete_group'; end if;
  update public.group_members set left_at = now() where group_id=p_group_id and user_id=p_user_id;
end; $$;

create or replace function public.delete_group(p_group_id uuid)
returns void language plpgsql security definer as $$
begin
  if not exists (select 1 from public.groups where id=p_group_id and owner_id=auth.uid())
    then raise exception 'owner only'; end if;
  delete from public.groups where id=p_group_id;  -- cascades members/config/invites
end; $$;
```

- [ ] **Step 2: Add an apply note**

At the top of the file, the comment already says "Apply in the Supabase SQL editor." No automated apply (no Supabase CLI in this repo). The owner runs it once.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0001_group_social_layer.sql
# message: "Add Supabase schema + RPCs for friend-group social layer (SP1)"
```

---

## Task 2: Core — group models + validation/normalization (TDD)

**Files:**
- Create: `Sources/ScreenTimeSharingCore/FriendGroupModels.swift`
- Test: `Tests/ScreenTimeSharingCoreTests/FriendGroupModelsTests.swift`

**Interfaces — Produces:**
- `enum GroupMode: String { case perMember = "per_member", pool }`
- `enum GroupRole: String { case owner, member }`
- `struct FriendGroup { id, ownerID, name, mode, ownerTimeZone, role: GroupRole, configuredAt: Date?, memberCount: Int }` (the app-facing summary returned by `get_my_groups`)
- `struct GroupBlockConfig { appNames:[String], perMemberLimitSeconds:Int?, poolSeconds:Int?, approvalsRequired:Int }`
- `enum GroupConfigValidation { static func errors(mode:GroupMode, appNames:[String], limitSeconds:Int?, approvalsRequired:Int) -> [String] }`
- `enum GroupAppNames { static func normalize(_:[String]) -> [String] }`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import ScreenTimeSharingCore

final class FriendGroupModelsTests: XCTestCase {
    func test_normalize_trimsDropsEmptyDedupesCaseInsensitive() {
        let out = GroupAppNames.normalize([" Instagram ", "instagram", "", "TikTok", "  "])
        XCTAssertEqual(out, ["Instagram", "TikTok"])
    }

    func test_validation_perMember_requiresPositiveLimitAndApps() {
        XCTAssertTrue(GroupConfigValidation.errors(
            mode: .perMember, appNames: [], limitSeconds: 1800, approvalsRequired: 1)
            .contains { $0.localizedCaseInsensitiveContains("app") })
        XCTAssertTrue(GroupConfigValidation.errors(
            mode: .perMember, appNames: ["IG"], limitSeconds: 0, approvalsRequired: 1)
            .contains { $0.localizedCaseInsensitiveContains("limit") })
        XCTAssertTrue(GroupConfigValidation.errors(
            mode: .perMember, appNames: ["IG"], limitSeconds: 1800, approvalsRequired: 1).isEmpty)
    }

    func test_validation_approvalsAtLeastOne() {
        XCTAssertFalse(GroupConfigValidation.errors(
            mode: .pool, appNames: ["IG"], limitSeconds: 3600, approvalsRequired: 0).isEmpty)
    }

    func test_groupMode_rawValueMatchesBackend() {
        XCTAssertEqual(GroupMode.perMember.rawValue, "per_member")
        XCTAssertEqual(GroupMode.pool.rawValue, "pool")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter FriendGroupModelsTests`
Expected: FAIL — types not found.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

public enum GroupMode: String, Codable, Sendable {
    case perMember = "per_member"
    case pool
}

public enum GroupRole: String, Codable, Sendable {
    case owner, member
}

public struct GroupBlockConfig: Codable, Equatable, Sendable {
    public var appNames: [String]
    public var perMemberLimitSeconds: Int?
    public var poolSeconds: Int?
    public var approvalsRequired: Int
    public init(appNames: [String], perMemberLimitSeconds: Int?, poolSeconds: Int?, approvalsRequired: Int) {
        self.appNames = appNames; self.perMemberLimitSeconds = perMemberLimitSeconds
        self.poolSeconds = poolSeconds; self.approvalsRequired = approvalsRequired
    }
}

public enum GroupAppNames {
    /// Trim, drop empties, dedupe case-insensitively (keep first spelling), cap length.
    public static func normalize(_ names: [String]) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for raw in names {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            let key = t.lowercased()
            if seen.insert(key).inserted { out.append(String(t.prefix(60))) }
        }
        return out
    }
}

public enum GroupConfigValidation {
    /// Returns a list of human-readable errors; empty means valid.
    public static func errors(mode: GroupMode, appNames: [String], limitSeconds: Int?, approvalsRequired: Int) -> [String] {
        var errs: [String] = []
        if GroupAppNames.normalize(appNames).isEmpty { errs.append("Add at least one app to restrict.") }
        if (limitSeconds ?? 0) <= 0 {
            errs.append(mode == .pool ? "Set a positive pool limit." : "Set a positive daily limit.")
        }
        if approvalsRequired < 1 { errs.append("Approvals required must be at least 1.") }
        return errs
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test` (full Core suite — new tests pass, no regression)
Expected: PASS.

- [ ] **Step 5: Register the new Core file in the Xcode app target**

The app compiles Core sources directly. Add `FriendGroupModels.swift` to the `ScreenTimeSharing` app target (and any extension that will need it later — for SP1 the app target suffices) via the `xcodeproj` gem:
```ruby
require "xcodeproj"; p = Xcodeproj::Project.open("ScreenTimeSharing.xcodeproj")
app = p.targets.find { |t| t.name == "ScreenTimeSharing" }
grp = p.files.find { |f| f.display_name == "BlockingModels.swift" }.parent  # Sources/ScreenTimeSharingCore group
ref = grp.new_reference("FriendGroupModels.swift"); app.add_file_references([ref]); p.save
```
(Test files are NOT added to the app target.)

- [ ] **Step 6: Build to confirm app target sees the type**

Run: `xcodebuild -project ScreenTimeSharing.xcodeproj -scheme ScreenTimeSharing -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add Sources/ScreenTimeSharingCore/FriendGroupModels.swift Tests/ScreenTimeSharingCoreTests/FriendGroupModelsTests.swift ScreenTimeSharing.xcodeproj/project.pbxproj
# message: "Add friend-group Core models + config validation (SP1)"
```

---

## Task 3: Core — member-summary + invite-code formatting (TDD)

**Files:**
- Modify: `Sources/ScreenTimeSharingCore/FriendGroupModels.swift`
- Test: `Tests/ScreenTimeSharingCoreTests/FriendGroupModelsTests.swift`

**Interfaces — Produces:**
- `struct GroupMemberInfo { userID:String, displayName:String, role:GroupRole, configured:Bool }`
- `enum GroupMembership { static func configuredSummary(_:[GroupMemberInfo]) -> (configured:Int, total:Int, pending:[String]) }`
- `enum GroupInviteCode { static func formatted(_:String) -> String }`  // "ABCD-EFGH"

- [ ] **Step 1: Append failing tests**

```swift
func test_configuredSummary_countsAndPending() {
    let m = [
        GroupMemberInfo(userID: "1", displayName: "Leo", role: .owner, configured: true),
        GroupMemberInfo(userID: "2", displayName: "Mia", role: .member, configured: false),
        GroupMemberInfo(userID: "3", displayName: "Sam", role: .member, configured: false),
    ]
    let s = GroupMembership.configuredSummary(m)
    XCTAssertEqual(s.configured, 1); XCTAssertEqual(s.total, 3)
    XCTAssertEqual(s.pending, ["Mia", "Sam"])
}

func test_inviteCode_formatted() {
    XCTAssertEqual(GroupInviteCode.formatted("ABCD1234"), "ABCD-1234")
    XCTAssertEqual(GroupInviteCode.formatted("SHORT"), "SHORT")
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter FriendGroupModelsTests`
Expected: FAIL — symbols not found.

- [ ] **Step 3: Append implementation to `FriendGroupModels.swift`**

```swift
public struct GroupMemberInfo: Codable, Equatable, Identifiable, Sendable {
    public var userID: String
    public var displayName: String
    public var role: GroupRole
    public var configured: Bool
    public var id: String { userID }
    public init(userID: String, displayName: String, role: GroupRole, configured: Bool) {
        self.userID = userID; self.displayName = displayName; self.role = role; self.configured = configured
    }
}

public enum GroupMembership {
    public static func configuredSummary(_ members: [GroupMemberInfo]) -> (configured: Int, total: Int, pending: [String]) {
        let pending = members.filter { !$0.configured }.map(\.displayName)
        return (members.filter { $0.configured }.count, members.count, pending)
    }
}

public enum GroupInviteCode {
    public static func formatted(_ code: String) -> String {
        guard code.count == 8 else { return code }
        return "\(code.prefix(4))-\(code.suffix(4))"
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test`
Expected: PASS, no regression.

- [ ] **Step 5: Commit**

```bash
git add Sources/ScreenTimeSharingCore/FriendGroupModels.swift Tests/ScreenTimeSharingCoreTests/FriendGroupModelsTests.swift
# message: "Add group member-summary + invite-code helpers (SP1)"
```

---

## Task 4: Swift — group RPC row types + deep-link parsing

**Files:**
- Modify: `ScreenTimeSharing/Services/SupabaseRowMapping.swift`

**Interfaces — Produces (Swift types the store + AppModel consume):**
- `struct CreatedGroup { groupID: String, code: String }`
- `struct PeekedGroupInvite { groupID, groupName, ownerDisplayName, mode: GroupMode }`
- `struct RedeemedGroupInvite { groupID, groupName }`
- `struct GroupDetail { group: FriendGroup-ish, config: GroupBlockConfig, members: [GroupMemberInfo] }`
- `enum GroupInviteDeepLink { static func code(from: URL) -> String? }`  // parses `deny://group-invite/<code>` (+ tolerates `https://host/group-invite/<code>`)

- [ ] **Step 1: Add the Codable row structs + deep-link parser**

Mirror the existing invite row types (`CreatedInviteRow`, `PeekedInviteRow`, `InviteDeepLink`) in this file. Add `Decodable` structs matching the RPC JSON (snake_case → `CodingKeys`), an app-facing `GroupDetail`/`GroupSummaryRow` mapped from `get_my_groups` / `get_group`, and `GroupInviteDeepLink` matching the host token `group-invite`. Representative parser:

```swift
public enum GroupInviteDeepLink {
    public static func code(from url: URL) -> String? {
        let parts = url.pathComponents.dropFirst()  // drop leading "/"
        if url.scheme?.lowercased() == "deny", url.host()?.lowercased() == "group-invite" {
            return normalize(parts.first)
        }
        if parts.first?.lowercased() == "group-invite" { return normalize(parts.dropFirst().first) }
        return nil
    }
    private static func normalize(_ raw: String?) -> String? {
        let s = raw?.replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return (s?.isEmpty == false) ? s : nil
    }
}
```

> Codex: define the row structs to match the RPC return shapes in Task 1 (e.g. `get_my_groups` columns; `get_group` returns a `jsonb` object with `group`/`config`/`members`). Map them to the Core models (`GroupMode`, `GroupBlockConfig`, `GroupMemberInfo`). Match the file's existing decoding style.

- [ ] **Step 2: Build**

Run: `xcodebuild … build` (as in Global Constraints)
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ScreenTimeSharing/Services/SupabaseRowMapping.swift
# message: "Add group RPC row types + group-invite deep link parsing (SP1)"
```

---

## Task 5: Swift — group RPC wrappers in SupabaseSnapshotStore

**Files:**
- Modify: `ScreenTimeSharing/Services/SupabaseSnapshotStore.swift`

**Interfaces — Consumes:** Task 4 row types. **Produces:** async wrappers:
- `createGroup(name:mode:appNames:limitSeconds:approvalsRequired:timeZone:) async throws -> CreatedGroup`
- `createGroupInvite(groupID:) async throws -> (code:String, url:URL)`
- `peekGroupInvite(code:) async throws -> PeekedGroupInvite`
- `redeemGroupInvite(code:) async throws -> RedeemedGroupInvite`
- `getMyGroups() async throws -> [FriendGroup]`
- `getGroup(groupID:) async throws -> GroupDetail`
- `setMemberConfigured(groupID:configured:) async throws`
- `leaveGroup(groupID:) async throws`
- `removeGroupMember(groupID:userID:) async throws`
- `deleteGroup(groupID:) async throws`

- [ ] **Step 1: Add the wrappers**

Mirror existing RPC calls (`client.rpc("create_friend_invite").execute().value`, ~L215–266). Each wrapper calls the matching RPC with `["p_…": value]` params, decodes into Task-4 types. For the invite URL reuse `AppConfiguration.inviteWebLink(code)` but with a group path (add `AppConfiguration.groupInviteWebLink(code)` returning `\(pushServerBaseURL)/group-invite/\(code)` and the deep link `deny://group-invite/\(code)`). Representative:

```swift
func createGroup(name: String, mode: GroupMode, appNames: [String],
                 limitSeconds: Int, approvalsRequired: Int, timeZone: String) async throws -> CreatedGroup {
    let rows: [CreatedGroupRow] = try await client.rpc("create_group", params: [
        "p_name": name, "p_mode": mode.rawValue, "p_app_names": appNames,
        "p_limit_seconds": limitSeconds, "p_approvals_required": approvalsRequired,
        "p_owner_time_zone": timeZone
    ]).execute().value
    guard let r = rows.first else { throw SupabaseSnapshotStoreError.invalidInvite }
    return CreatedGroup(groupID: r.groupId, code: r.code)
}
```

> Codex: implement all 10 wrappers in the same style; match the actual supabase-swift `rpc(_:params:)` API used elsewhere in this file; reuse the existing error type. `getGroup` decodes the `jsonb` object.

- [ ] **Step 2: Add `AppConfiguration.groupInviteWebLink`**

In `ScreenTimeSharing/AppConfiguration.swift`, next to `inviteWebLink`:
```swift
static func groupInviteWebLink(_ code: String) -> URL {
    URL(string: "\(pushServerBaseURL)/group-invite/\(code)")!
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild … build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add ScreenTimeSharing/Services/SupabaseSnapshotStore.swift ScreenTimeSharing/AppConfiguration.swift
# message: "Add group RPC wrappers + group invite web link (SP1)"
```

---

## Task 6: AppModel — group state + methods

**Files:**
- Modify: `ScreenTimeSharing/AppModel.swift`

**Interfaces — Consumes:** Task 5 store methods. **Produces (used by UI/app):**
- `@Published var myGroups: [FriendGroup]`
- `@Published var pendingIncomingGroupInvite: PeekedGroupInvite?`
- `func loadMyGroups() async`
- `func createGroup(name:mode:appNames:limitSeconds:approvalsRequired:) async -> CreatedGroup?`  // uses TimeZone.current.identifier
- `func presentIncomingGroupInvite(code:) async`
- `func redeemPendingGroupInvite() async -> Bool`
- `func leaveGroup(_:) async` / `func removeMember(groupID:userID:) async` / `func deleteGroup(_:) async`
- `func loadGroupDetail(groupID:) async -> GroupDetail?`

- [ ] **Step 1: Add state + methods**

Mirror the existing friend-invite methods (`createInvite`/`presentIncomingInvite`/`redeemInvite` ~L1158–1235). `createGroup` validates via `GroupConfigValidation.errors(...)` before calling the store and sets `self.message` on error. `presentIncomingGroupInvite` peeks and sets `pendingIncomingGroupInvite`. All set user-facing `message` on failure. Representative:

```swift
@Published var myGroups: [FriendGroup] = []
@Published var pendingIncomingGroupInvite: PeekedGroupInvite?

@MainActor func createGroup(name: String, mode: GroupMode, appNames: [String],
                            limitSeconds: Int, approvalsRequired: Int) async -> CreatedGroup? {
    let errs = GroupConfigValidation.errors(mode: mode, appNames: appNames,
                                            limitSeconds: limitSeconds, approvalsRequired: approvalsRequired)
    guard errs.isEmpty else { message = errs.joined(separator: " "); return nil }
    do {
        let g = try await snapshotStore.createGroup(
            name: name, mode: mode, appNames: GroupAppNames.normalize(appNames),
            limitSeconds: limitSeconds, approvalsRequired: approvalsRequired,
            timeZone: TimeZone.current.identifier)
        await loadMyGroups(); return g
    } catch { message = "Could not create group: \(error.localizedDescription)"; return nil }
}
```

> Codex: implement the remaining methods in the same pattern; `loadMyGroups` populates `myGroups`; redeem path mirrors `redeemPendingInvite` + reloads groups.

- [ ] **Step 2: Build**

Run: `xcodebuild … build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ScreenTimeSharing/AppModel.swift
# message: "Add AppModel group state + create/join/manage methods (SP1)"
```

---

## Task 7: Deep link — route group invites

**Files:**
- Modify: `ScreenTimeSharing/ScreenTimeSharingApp.swift`

- [ ] **Step 1: Extend `onOpenURL`**

The existing handler (~L29–36) calls `InviteDeepLink.code(from:)` → `presentIncomingInvite`. Add a branch BEFORE it for group invites:

```swift
.onOpenURL { url in
    if let code = GroupInviteDeepLink.code(from: url) {
        Task { await model.presentIncomingGroupInvite(code: code) }
        return
    }
    guard let code = InviteDeepLink.code(from: url) else { return }
    Task { await model.presentIncomingInvite(code: code) }
}
```

- [ ] **Step 2: Build + commit**

Run: `xcodebuild … build` → BUILD SUCCEEDED.
```bash
git add ScreenTimeSharing/ScreenTimeSharingApp.swift
# message: "Route deny://group-invite/<code> to incoming group invite (SP1)"
```

---

## Task 8: UI — Groups views (list / create / join / detail)

**Files:**
- Create: `ScreenTimeSharing/Views/GroupsView.swift`
- Modify: `ScreenTimeSharing.xcodeproj/project.pbxproj` (register new file in app target)
- Modify: the tab/nav host (where the app's tabs are declared — `RootView.swift` / `AppTabs`) to add a "Groups" entry.

**Interfaces — Consumes:** `AppModel.myGroups`, `createGroup`, `loadMyGroups`, `pendingIncomingGroupInvite`, `redeemPendingGroupInvite`, `loadGroupDetail`, `leaveGroup`/`removeMember`/`deleteGroup`; Core `GroupMode`, `GroupMembership.configuredSummary`, `GroupInviteCode.formatted`; `AppConfiguration.groupInviteWebLink`.

- [ ] **Step 1: Implement the views**

Build these (match existing view styling, e.g. `FriendsView`/`InviteFriendsSheet`):
- `GroupsView`: a list of `model.myGroups` (name, mode badge, member count, your configured ✓/pending); a "Create group" button; `.task { await model.loadMyGroups() }`.
- `CreateGroupSheet`: fields — name; mode `Picker` (Per-member limit / Shared pool); app-name list editor (add/remove text rows); a limit input (minutes → seconds; label switches "per person/day" vs "shared/day" by mode); approvals stepper (default 1). "Create" → `model.createGroup(...)` → on success show a share step with `ShareLink(item: shareText)` where shareText includes `AppConfiguration.groupInviteWebLink(code)` and `deny://group-invite/CODE` (reuse `OnboardingInvite.shareMessage` style or a small group variant). Gate "Create" on `GroupConfigValidation.errors(...).isEmpty`.
- `GroupDetailView`: members list with ✓/pending (via `GroupMembership.configuredSummary`), the config summary, a "Share invite" button; owner sees Edit config / Remove member / Delete group; member sees Leave. Wire to the AppModel methods. `.task { detail = await model.loadGroupDetail(groupID:) }`.
- A join sheet presented from `model.pendingIncomingGroupInvite` (mirror `FriendShareInviteView` in `RootView`): shows group name + owner, Accept → `redeemPendingGroupInvite`. Add `.sheet(item:)` for it in the same host as the friend invite sheet.

> Codex: match existing SwiftUI idioms (Haptics/AppHaptics, button styles, layout bits in `SharedViewBits.swift`). Use `model` as `@EnvironmentObject`. Keep app-name editing simple (a `TextField` + add button + deletable rows). Do NOT implement the local block adoption here — that is SP2.

- [ ] **Step 2: Register the new view file in the app target**

```ruby
require "xcodeproj"; p = Xcodeproj::Project.open("ScreenTimeSharing.xcodeproj")
app = p.targets.find { |t| t.name == "ScreenTimeSharing" }
grp = p.files.find { |f| f.display_name == "FriendsView.swift" }.parent  # Views group
ref = grp.new_reference("GroupsView.swift"); app.add_file_references([ref]); p.save
```

- [ ] **Step 3: Build + manual verify**

Run: `xcodebuild … build` → BUILD SUCCEEDED.
Manual (after SQL applied + signed-in device/sim): create a group → get an invite link; on a second account, open `deny://group-invite/<code>` → accept → both see the membership; configured ✓ reflects state; leave/remove/delete behave; owner cannot leave.

- [ ] **Step 4: Commit**

```bash
git add ScreenTimeSharing/Views/GroupsView.swift ScreenTimeSharing.xcodeproj/project.pbxproj ScreenTimeSharing/Views/RootView.swift
# message: "Add group list/create/join/manage UI (SP1)"
```

---

## Task 9: push-server — group-invite landing

**Files:**
- Modify: `push-server/src/index.js`

- [ ] **Step 1: Serve `/group-invite/<code>`**

Mirror the `/invite/<code>` handler (~L27–31, `inviteLandingHTML`). Add a branch that serves the same landing HTML but builds the deep link `deny://group-invite/<code>` and copy "You've been invited to a Deny group". Reuse the App Store fallback.

```javascript
if (url.pathname.startsWith("/group-invite/")) {
  const raw = url.pathname.slice("/group-invite/".length).split("/")[0];
  const code = (raw || "").replace(/[^a-zA-Z0-9]/g, "").toUpperCase().slice(0, 16);
  return html(inviteLandingHTML(code, { scheme: "deny://group-invite/", heading: "You've been invited to a Deny group" }));
}
```

> Codex: parameterize `inviteLandingHTML` to accept the scheme + heading (default to the existing friend-invite values) so both routes share it. Owner deploys the Worker.

- [ ] **Step 2: Commit**

```bash
git add push-server/src/index.js
# message: "Serve group-invite landing page (SP1)"
```

---

## Final verification (SP1)

- [ ] `swift test` — Core green (existing + `FriendGroupModelsTests`).
- [ ] `xcodebuild … build` — app builds with the new Core file, RPC wrappers, AppModel, deep link, and UI registered.
- [ ] **Owner applies** `supabase/migrations/0001_group_social_layer.sql` in Supabase, then manual end-to-end: create → invite link → second account joins → member list + configured status → leave/remove/delete; owner-cannot-leave enforced.

---

## Self-Review (against spec)

- **Spec coverage (SP1 scope):** tables/RPCs §4 → Task 1; Core models + pure logic §4 → Tasks 2–3; RPC wrappers + deep link → Tasks 4–5,7; AppModel → Task 6; UI (create/join/manage, configured ✓/✗) → Task 8; push-server group invite → Task 9. SP2/SP3/SP4 explicitly out of THIS plan (later sub-projects).
- **Placeholder scan:** The Swift/UI tasks delegate idiomatic bodies to Codex but give exact signatures, the SQL/Core in full, and exact build/commit commands — no "TBD"/"handle errors" hand-waving. The one external dependency (apply SQL in Supabase) is an explicit, unavoidable hand-off, not a gap.
- **Type consistency:** `GroupMode`(`per_member`/`pool`), `GroupRole`, `GroupBlockConfig`, `GroupConfigValidation.errors`, `GroupAppNames.normalize`, `GroupMemberInfo`, `GroupMembership.configuredSummary`, `GroupInviteCode.formatted`, and the RPC names match between the SQL (Task 1), Core (Tasks 2–3), wrappers (Tasks 4–5), AppModel (Task 6), and UI (Task 8).

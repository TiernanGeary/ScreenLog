# Friend-Group SP3 (Shared pool, near-real-time) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement task-by-task. Checkbox (`- [ ]`) steps.
>
> **Project model (CLAUDE.md):** Claude plans & verifies; **Codex implements**; **Claude commits** (English + `Co-Authored-By`; add by explicit file path). New files registered in the Xcode app target by Claude.

**Goal:** A `pool` group shares one daily usage budget — each member runs a local backstop block (pool-sized daily limit) so the pool can't be wildly exceeded, while members report incremental selected-app usage so the group total can re-shield everyone (best-effort, near-real-time) when the shared pool is exhausted, resetting at the owner's timezone day.

**Architecture:** REUSE SP2's local adoption with `limitSeconds = pool_seconds` as the **backstop** (the reliable, offline-safe enforcement). On top, members report their `selectedAppDuration` to a new `group_usage` table on each `publishSnapshotIfNeeded` (foreground / remote-push throttled); the backend sums the group's day and, when ≥ `pool_seconds`, marks it exhausted and fires a SILENT (background) push; on that push (and on every foreground), members fetch pool state and apply/clear a local **pool-exhausted shield override** that force-blocks the group's apps until the owner-TZ reset.

**Tech Stack:** Supabase (PL/pgSQL applied out-of-band), FamilyControls/ManagedSettings (DeviceActivity, existing enforcement), supabase-swift, APNs (silent/background push via the Cloudflare Worker), Core (`ScreenTimeSharingCore` + XCTest).

**Spec:** `docs/superpowers/specs/2026-06-21-friend-group-limits-design.md` (§5 SP3).
**Branch:** `feature/friend-group-limits` (SP1+SP2+SP4 already on it).

## Global Constraints

- **No code by Claude** beyond config/pbxproj; Codex implements; Claude commits.
- **Supabase SQL applied out-of-band** by owner. RPC names (verbatim): `report_group_usage`, `get_group_pool_state`.
- **Backstop = primary enforcement (spec §5 SP3):** every pool member's local block is `mode = .timeLimit(limitSeconds: pool_seconds, days: BlockWeekday.everyDay)` over their picked apps — so a fully-offline member can never alone exceed the whole pool. (Reuses SP2's adoption with `limitSeconds = pool_seconds`.)
- **Shared accounting is BEST-EFFORT, not instant (iOS constraints, documented):** the DeviceActivity extension cannot make network calls, so usage is reported only from the main app on foreground / remote-push (the existing `publishSnapshotIfNeeded` 10-min throttle). Silent pushes are throttled/unreliable → ALWAYS also poll pool state on foreground. Some overshoot is inevitable; the backstop bounds the worst case.
- **Pool reset:** daily at the OWNER's timezone midnight (`groups.owner_time_zone`); `group_usage.day` is computed in that TZ.
- **Exhaustion precedence:** a pool-exhausted override force-shields the group's apps and takes precedence over an unblock session (stricter).
- **No alert noise:** the exhaustion push is `content-available`-only (`apns-push-type: background`), no alert/sound.
- **Core tests:** `swift test`. **App build:** `xcodebuild … -scheme ScreenTimeSharing -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`. **Distributed behavior (reporting → exhaustion → re-shield) can only be verified on real devices with the SQL applied + the Worker deployed — flag this; it is NOT locally verifiable.**

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `supabase/migrations/0003_group_usage_pool.sql` | **NEW** group_usage table + report_group_usage/get_group_pool_state RPCs (owner applies) | Create (Task 1) |
| `Sources/ScreenTimeSharingCore/FriendGroupModels.swift` | `GroupPool` accounting (remaining/exhausted) + owner-TZ day key | Modify (Task 2) |
| `Tests/ScreenTimeSharingCoreTests/FriendGroupModelsTests.swift` | Tests | Modify (Task 2) |
| `Sources/ScreenTimeSharingCore/BlockingModels.swift` | Add `PoolExhaustionOverride` to `BlockingState` (additive, backward-compatible) | Modify (Task 3) |
| `ScreenTimeSharing/Services/BlockingEnforcementService.swift` | Force-shield groups with an active pool-exhaustion override (precedence over unblock) | Modify (Task 3) |
| `ScreenTimeSharing/Services/SupabaseSnapshotStore.swift` | `reportGroupUsage` + `getGroupPoolState` wrappers + `GroupPoolState` row | Modify (Task 4) |
| `ScreenTimeSharing/AppModel.swift` | Pool adoption (backstop), report usage in publishSnapshotIfNeeded, sync pool state + apply/clear override | Modify (Task 5) |
| `push-server/src/index.js` | Silent (background) push variant + pool-exhausted trigger payload | Modify (Task 6) |
| `ScreenTimeSharing/Views/GroupsView.swift` | Pool-mode setup (adopt backstop) + pool status in GroupDetailView | Modify (Task 7) |

Reference: SP2 adoption (`AppModel.adoptGroupBlock`, `GroupBlock.makeBlockGroup`), `publishSnapshotIfNeeded` (~AppModel L1489), `BlockingEnforcementService.applyShields` (~L76-95) + suppression (~L88-96), `BlockUnblockSession` (`BlockingModels` ~L717), `RemoteChangeCenter.handleRemoteChange`/`AppModel.handleRemoteChange`, `PushServerClient.notify` + push-server `/notify` (~L79-137), `DateBoundaries` (owner-TZ day), `groups.owner_time_zone`, `DailyUsageSnapshot.selectedAppDuration`.

---

## Task 1: Supabase — group_usage table + pool RPCs (deliverable SQL)

**Files:** Create `supabase/migrations/0003_group_usage_pool.sql`

- [ ] **Step 1: Write the SQL**

```sql
-- SP3: shared pool usage. Apply in the Supabase SQL editor (after 0001/0002).
create table if not exists public.group_usage (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  day text not null,                         -- owner-TZ day key 'YYYY-MM-DD'
  selected_app_seconds int not null default 0,
  updated_at timestamptz not null default now(),
  primary key (group_id, user_id, day)
);
alter table public.group_usage enable row level security;
create policy group_usage_select on public.group_usage for select
  using (public.is_group_member(group_id));

-- Owner-TZ day key for a group.
create or replace function public.group_owner_day(p_group_id uuid)
returns text language sql security definer stable as $$
  select to_char((now() at time zone coalesce(
    (select owner_time_zone from public.groups where id = p_group_id), 'UTC')), 'YYYY-MM-DD');
$$;

-- Report a member's cumulative selected-app seconds for today; return pool state.
create or replace function public.report_group_usage(p_group_id uuid, p_selected_app_seconds int)
returns table(pool_seconds int, used_seconds int, remaining_seconds int, exhausted boolean)
language plpgsql security definer as $$
declare d text; pool int; used int;
begin
  if not public.is_group_member(p_group_id) then raise exception 'not a member'; end if;
  d := public.group_owner_day(p_group_id);
  insert into public.group_usage(group_id, user_id, day, selected_app_seconds, updated_at)
    values (p_group_id, auth.uid(), d, greatest(coalesce(p_selected_app_seconds,0),0), now())
    on conflict (group_id, user_id, day) do update
      set selected_app_seconds = greatest(excluded.selected_app_seconds, public.group_usage.selected_app_seconds),
          updated_at = now();
  select pool_seconds into pool from public.group_config where group_id = p_group_id;
  select coalesce(sum(selected_app_seconds),0) into used
    from public.group_usage where group_id = p_group_id and day = d;
  return query select coalesce(pool,0), used, greatest(coalesce(pool,0)-used,0),
                      (used >= coalesce(pool,0) and coalesce(pool,0) > 0);
end; $$;

create or replace function public.get_group_pool_state(p_group_id uuid)
returns table(pool_seconds int, used_seconds int, remaining_seconds int, exhausted boolean)
language plpgsql security definer stable as $$
declare d text; pool int; used int;
begin
  if not public.is_group_member(p_group_id) then raise exception 'not a member'; end if;
  d := public.group_owner_day(p_group_id);
  select pool_seconds into pool from public.group_config where group_id = p_group_id;
  select coalesce(sum(selected_app_seconds),0) into used
    from public.group_usage where group_id = p_group_id and day = d;
  return query select coalesce(pool,0), used, greatest(coalesce(pool,0)-used,0),
                      (used >= coalesce(pool,0) and coalesce(pool,0) > 0);
end; $$;
```

> The exhaustion silent-push TRIGGER (server → push-server) is intentionally NOT a DB cron here: the simplest reliable path is the iOS client that observes `exhausted=true` from `report_group_usage`/`get_group_pool_state` asks push-server to broadcast to members (Task 6). Document this; a Supabase Edge Function trigger is a future hardening.

- [ ] **Step 2: Commit** — `git add supabase/migrations/0003_group_usage_pool.sql` · message "Add Supabase group_usage table + pool RPCs (SP3 T1)"

---

## Task 2: Core — pool accounting + owner-TZ day (TDD)

**Files:** Modify `FriendGroupModels.swift` + `FriendGroupModelsTests.swift`

**Produces:** `enum GroupPool { static func remaining(poolSeconds:Int, usedSeconds:Int) -> Int ; static func exhausted(poolSeconds:Int, usedSeconds:Int) -> Bool ; static func dayKey(now: Date, timeZoneIdentifier: String) -> String }`

- [ ] **Step 1: Append failing tests**

```swift
func test_groupPool_remainingAndExhausted() {
    XCTAssertEqual(GroupPool.remaining(poolSeconds: 3600, usedSeconds: 1000), 2600)
    XCTAssertEqual(GroupPool.remaining(poolSeconds: 3600, usedSeconds: 5000), 0)
    XCTAssertFalse(GroupPool.exhausted(poolSeconds: 3600, usedSeconds: 3599))
    XCTAssertTrue(GroupPool.exhausted(poolSeconds: 3600, usedSeconds: 3600))
    XCTAssertFalse(GroupPool.exhausted(poolSeconds: 0, usedSeconds: 10))  // unconfigured pool never exhausts
}
func test_groupPool_dayKey_usesTimeZone() {
    // 2026-06-21 00:30 UTC is still 2026-06-20 in America/Los_Angeles.
    let d = ISO8601DateFormatter().date(from: "2026-06-21T00:30:00Z")!
    XCTAssertEqual(GroupPool.dayKey(now: d, timeZoneIdentifier: "America/Los_Angeles"), "2026-06-20")
    XCTAssertEqual(GroupPool.dayKey(now: d, timeZoneIdentifier: "UTC"), "2026-06-21")
}
```

- [ ] **Step 2: Run → FAIL** (`swift test --filter FriendGroupModelsTests`).

- [ ] **Step 3: Append implementation**

```swift
public enum GroupPool {
    public static func remaining(poolSeconds: Int, usedSeconds: Int) -> Int { max(poolSeconds - usedSeconds, 0) }
    public static func exhausted(poolSeconds: Int, usedSeconds: Int) -> Bool { poolSeconds > 0 && usedSeconds >= poolSeconds }
    public static func dayKey(now: Date, timeZoneIdentifier: String) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        let c = cal.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
```

- [ ] **Step 4: Run → PASS** (`swift test`). **Step 5: Commit** — message "Add group pool accounting + owner-TZ day key (SP3 T2)".

---

## Task 3: Core + enforcement — pool-exhaustion override force-shield

**Files:** Modify `Sources/ScreenTimeSharingCore/BlockingModels.swift` + `ScreenTimeSharing/Services/BlockingEnforcementService.swift`

**Produces:** `BlockingState.poolExhaustionOverrides: [PoolExhaustionOverride]` where `struct PoolExhaustionOverride: Codable, Equatable, Sendable { var groupID: String; var exhaustedAt: Date; var resetsAt: Date; func isActive(now:) -> Bool }`. Enforcement: for any group with an active override, force-apply its shield (precedence over unblock suppression).

- [ ] **Step 1: Add the model (additive, backward-compatible)**

Add `PoolExhaustionOverride` near `BlockUnblockSession` in BlockingModels.swift; add `public var poolExhaustionOverrides: [PoolExhaustionOverride] = []` to `BlockingState` with a DEFAULT so existing decoding/tests still pass. `isActive(now:) = exhaustedAt <= now && now < resetsAt`.

- [ ] **Step 2: Force-shield in enforcement**

In `BlockingEnforcementService.applyShields(for:in:)`, compute `forcedGroupIDs` = groups (block id `"group.<socialGroupID>"`) with an active `PoolExhaustionOverride`; ensure those are shielded REGARDLESS of time-limit threshold and are NOT in `suppressedGroupIDs` (pool-exhaustion overrides unblock). Concretely: include forced groups' selections in the applied shield set and remove them from the exemption/suppression set.

> Codex: keep changes additive; mirror how unblock suppression is computed/applied. The forced set unions into the shielded selections and is subtracted from the exempted/suppressed selections.

- [ ] **Step 3: Verify BOTH** — `swift test` (Core regression: BlockingState Codable + BlockingModelsTests must stay green) AND `xcodebuild … build`. **Commit** (BlockingModels.swift + BlockingEnforcementService.swift) — message "Add pool-exhaustion override force-shield (SP3 T3)".

---

## Task 4: Store — report/get pool state wrappers

**Files:** Modify `SupabaseSnapshotStore.swift` (+ a `GroupPoolState` row type in `SupabaseRowMapping.swift` if needed).

**Produces:**
- `func reportGroupUsage(groupID: String, selectedAppSeconds: Int) async throws -> GroupPoolState`
- `func getGroupPoolState(groupID: String) async throws -> GroupPoolState`
where `struct GroupPoolState { poolSeconds:Int; usedSeconds:Int; remainingSeconds:Int; exhausted:Bool }`.

- [ ] **Step 1: Add wrappers (mirror existing RPC decode of a returned row)**

```swift
struct GroupPoolStateRow: Decodable { let pool_seconds: Int; let used_seconds: Int; let remaining_seconds: Int; let exhausted: Bool }
func reportGroupUsage(groupID: String, selectedAppSeconds: Int) async throws -> GroupPoolState {
    struct P: Encodable { let p_group_id: String; let p_selected_app_seconds: Int }
    let rows: [GroupPoolStateRow] = try await client.rpc("report_group_usage",
        params: P(p_group_id: groupID, p_selected_app_seconds: selectedAppSeconds)).execute().value
    let r = rows.first
    return GroupPoolState(poolSeconds: r?.pool_seconds ?? 0, usedSeconds: r?.used_seconds ?? 0,
                          remainingSeconds: r?.remaining_seconds ?? 0, exhausted: r?.exhausted ?? false)
}
func getGroupPoolState(groupID: String) async throws -> GroupPoolState {
    struct P: Encodable { let p_group_id: String }
    let rows: [GroupPoolStateRow] = try await client.rpc("get_group_pool_state",
        params: P(p_group_id: groupID)).execute().value
    let r = rows.first
    return GroupPoolState(poolSeconds: r?.pool_seconds ?? 0, usedSeconds: r?.used_seconds ?? 0,
                          remainingSeconds: r?.remaining_seconds ?? 0, exhausted: r?.exhausted ?? false)
}
```

> Codex: match how existing table-returning RPCs decode (the SP1 group RPCs / respond wrappers). Define `GroupPoolState` where the app can see it.

- [ ] **Step 2: Build + commit** — message "Add group pool report/state RPC wrappers (SP3 T4)".

---

## Task 5: AppModel — pool adoption (backstop), reporting, exhaustion sync

**Files:** Modify `AppModel.swift`

**Produces:**
- `func adoptGroupPoolBlock(groupID: String, poolSeconds: Int, selection: FamilyActivitySelection) async -> Bool` (reuse `adoptGroupBlock` with `limitSeconds = poolSeconds` — the backstop)
- pool reporting inside `publishSnapshotIfNeeded`
- `func syncGroupPools() async` (fetch each pool group's state; insert/clear `PoolExhaustionOverride`; reconcile shields), called from `handleRemoteChange` + foreground

- [ ] **Step 1: Pool adoption (backstop)** — add `adoptGroupPoolBlock` that calls the same path as `adoptGroupBlock` but with `limitSeconds = poolSeconds` (so the local block is a pool-sized daily limit). Mark configured via `setMemberConfigured`.

- [ ] **Step 2: Report usage** — in `publishSnapshotIfNeeded`, after the daily snapshot upload, for each `pool` group the user belongs to: `let state = try? await snapshotStore.reportGroupUsage(groupID: g.id, selectedAppSeconds: Int(localSnapshot?.selectedAppDuration ?? 0))`; if `state?.exhausted == true` apply the override + ask push-server to broadcast (Task 6).

- [ ] **Step 3: Sync + enforce** — `syncGroupPools()`: for each pool group call `getGroupPoolState`; if `exhausted`, upsert a `PoolExhaustionOverride(groupID:"group.\(g.id)", exhaustedAt: now, resetsAt: <owner-TZ next midnight>)` into `blockingState.poolExhaustionOverrides` and re-run enforcement; else remove the override (if past reset or no longer exhausted) and re-enforce. Call from `handleRemoteChange()` and on foreground.

> Codex: compute `resetsAt` as the next owner-TZ midnight (use GroupPool.dayKey + the group's ownerTimeZone). Reuse the existing enforcement sync entry point to apply/clear shields. Keep the friend/per-member paths unchanged.

- [ ] **Step 4: Verify** — `swift test` (Core override unaffected) + `xcodebuild … build`. **Commit** — message "Add pool backstop adoption + usage reporting + exhaustion sync (SP3 T5)".

---

## Task 6: push-server — silent exhaustion broadcast

**Files:** Modify `push-server/src/index.js`

- [ ] **Step 1: Silent push variant + a /group-pool-exhausted route**

Parameterize the notify payload: when `content_available_only` is set, send `aps: { "content-available": 1 }` only (no alert/sound/category) with `"apns-push-type": "background"` and `"apns-priority": "5"`, plus a custom field `poolExhaustedGroupID`. Add a `POST /group-pool-exhausted` (auth via the existing `x-deny-secret`) that takes `{ groupID, profileIDs: [...] }` and sends the silent push to each — OR extend the existing `/notify` with a `silent` flag. Keep the existing `/notify` alert behavior unchanged by default.

> Codex: reuse the existing APNs send (jwt, host, token lookup); only the payload + headers differ for silent. The client (Task 5) calls this with the group's member profile IDs when it detects exhaustion.

- [ ] **Step 2: Commit** — message "Add silent pool-exhaustion push to push-server (SP3 T6)".

---

## Task 7: UI — pool setup + status

**Files:** Modify `GroupsView.swift`

- [ ] **Step 1: Pool-mode setup + status in GroupDetailView**

For a `pool` group: reuse the SP2 `GroupBlockSetupSheet` flow but call `model.adoptGroupPoolBlock(groupID:poolSeconds:selection:)` (limit = the group's `pool_seconds`), with copy explaining it's a SHARED daily budget (and a backstop on your device). Show pool status: "Shared pool: <remaining>/<pool> min left today" using a `getGroupPoolState` fetch; when exhausted, show "Pool used up — blocked until reset". Keep the per-member path (SP2) for `.perMember` groups unchanged.

- [ ] **Step 2: Build + manual verify (device + SQL + Worker)** — `xcodebuild … build`. Manual: two members in a pool group both block; usage by either drains the shared pool; on exhaustion both get re-shielded (after a foreground/push sync); resets at the owner-TZ midnight.

- [ ] **Step 3: Commit** — message "Add shared-pool setup + status UI (SP3 T7)".

---

## Final verification (SP3)

- [ ] `swift test` — Core green (existing + GroupPool + the BlockingState override).
- [ ] `xcodebuild … build` — app builds.
- [ ] **NOT locally verifiable:** the distributed reporting → aggregation → silent push → re-shield loop requires real devices + the 0001/0002/0003 SQL applied + the Worker deployed. Manual multi-device E2E on the owner's account.

---

## Self-Review (against spec §5 SP3)

- **Coverage:** backstop (pool-sized local limit) → Tasks 5,7 (reuse SP2); usage reporting → Tasks 1,4,5; group aggregation + exhaustion → Task 1; silent push + handling → Tasks 5,6; local force-shield on exhaustion (precedence over unblock) → Task 3; owner-TZ reset → Tasks 1,2,5. Honest constraints (best-effort, overshoot, extension-can't-network) are stated in Global Constraints, matching spec §5/§6.
- **Placeholder scan:** SQL + Core shown in full; enforcement/AppModel give exact reuse points (adoptGroupBlock, publishSnapshotIfNeeded, applyShields, handleRemoteChange) and exact override semantics — the deferred bits are explicit "match the existing X" instructions, not gaps. The silent-push trigger choice (client-driven vs Edge Function) is an explicit, justified decision.
- **Type consistency:** `GroupPool`, `PoolExhaustionOverride`, `GroupPoolState`, `reportGroupUsage`/`getGroupPoolState`, `adoptGroupPoolBlock`, block id `"group.<socialGroupID>"` are consistent across tasks and reuse SP1/SP2/SP4 committed types.

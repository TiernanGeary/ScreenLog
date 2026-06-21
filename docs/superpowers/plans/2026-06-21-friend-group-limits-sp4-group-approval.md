# Friend-Group SP4 (Group-approval to extend) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement task-by-task. Checkbox (`- [ ]`) steps.
>
> **Project model (CLAUDE.md):** Claude plans & verifies; **Codex implements**; **Claude commits** (English + `Co-Authored-By` trailer; add by explicit file path — the repo has CRLF stat-noise). New files registered in the Xcode app target by Claude.

**Goal:** Let a blocked member of a group ask the GROUP for extra minutes; once `approvals_required` members approve, the requester gets a temporary unblock — reusing the existing time-request + unblock-session machinery.

**Architecture:** Group time-requests are ordinary rows in the existing `time_requests` table (so the existing request feed surfaces them to members), with added `social_group_id` + `approvals_required` + `approvers[]` columns and two new RPCs (`send_group_time_request`, `respond_group_time_request`) that count approvals server-side. The local temporary unblock reuses `collectFriendRequest`'s `BlockUnblockSession` creation (no password needed locally; the shield is suppressed for active sessions).

**Tech Stack:** Supabase (PL/pgSQL RPCs applied out-of-band by the owner), supabase-swift, SwiftUI, Core (`ScreenTimeSharingCore` + XCTest).

**Spec:** `docs/superpowers/specs/2026-06-21-friend-group-limits-design.md` (§5 SP4).
**Branch:** `feature/friend-group-limits` (SP1 + SP2 already on it).

## Global Constraints

- **No code by Claude** beyond trivial config / pbxproj registration; Codex implements; Claude commits.
- **Supabase SQL is applied out-of-band** by the owner (no repo migration pipeline). RPC names (verbatim): `send_group_time_request`, `respond_group_time_request`.
- **Approval counting is SERVER-SIDE:** the request becomes `status='approved'` only when **`approvals_required` distinct group members** approve (value copied from `group_config.approvals_required` at send time). `approvals_required` is configurable (≥1), per spec §2.
- **Temporary unblock = personal only** (spec §2): granting extra time creates a local `BlockUnblockSession` for the requester's group block group `"group.<socialGroupID>"`; it does NOT credit any pool.
- **No password needed for the local unblock** — inserting a `BlockUnblockSession` into `blockingState.unblockSessions` suppresses the shield (BlockingEnforcementService).
- **Recipients = all other group members** (not a hand-picked friend subset).
- **Reuse, don't fork:** the existing request feed (BlockingSettingsView) shows incoming group requests via the existing `time_requests` recipient query; only the SEND entry point and the approve-routing differ.
- **Core tests:** `swift test`. **App build:** `xcodebuild … -scheme ScreenTimeSharing -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`.

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `supabase/migrations/0002_group_time_requests.sql` | **NEW** time_requests group columns + 2 RPCs (owner applies) | Create (Task 1) |
| `Sources/ScreenTimeSharingCore/FriendGroupModels.swift` | Add `GroupApproval` progress helper | Modify (Task 2) |
| `Tests/ScreenTimeSharingCoreTests/FriendGroupModelsTests.swift` | Test the helper | Modify (Task 2) |
| `ScreenTimeSharing/Services/SupabaseSnapshotStore.swift` | `sendGroupTimeRequest` + `respondGroupTimeRequest` wrappers | Modify (Task 3) |
| `ScreenTimeSharing/AppModel.swift` | `requestGroupTime(...)`; route group-request approve to the group RPC | Modify (Task 4) |
| `ScreenTimeSharing/Views/GroupsView.swift` | "Ask group for more time" composer in `GroupDetailView` | Modify (Task 5) |

Reference: time-request flow — `AppModel.requestFriendTime` (~L908-975), `approveFriendRequest` (~L978-1013), `collectFriendRequest` (~L1049-1097, the unblock-session creation), `sendPushNotification` (~L1469-1485), `syncFriendRequests` (~L1487); store `respond_to_time_request`/`collect_time_request` wrappers (`SupabaseSnapshotStore.updateFriendRequest` ~L515-549) + insert (`publishFriendRequestDiagnostic` ~L481-510) + fetch (`fetchFriendRequests` ~L551-575); `TimeRequestRow` (`SupabaseRowMapping` ~L139-227); `BlockFriendRequest`/`BlockUnblockSession` (`BlockingModels` ~L579/L717); SP2 block group id convention `"group.<socialGroupID>"`; `GroupBlockConfig.approvalsRequired`.

---

## Task 1: Supabase — group time-request columns + RPCs (deliverable SQL)

**Files:**
- Create: `supabase/migrations/0002_group_time_requests.sql`

- [ ] **Step 1: Write the SQL**

```sql
-- SP4: group-scoped time requests. Apply in the Supabase SQL editor.
-- Assumes 0001_group_social_layer.sql is already applied and the existing
-- time_requests table (id, group_id text, requester_id, recipient_ids uuid[],
-- requested_seconds, message, photo_path, status, approved_by, created_at,
-- expires_at, resolved_at, approved_expires_at, collected_at, group_app_names).

alter table public.time_requests
  add column if not exists social_group_id uuid references public.groups(id) on delete cascade,
  add column if not exists approvals_required int,
  add column if not exists approvers uuid[] not null default '{}';

-- Send a group time request: recipients = all other active members; approvals
-- required = the group's configured count. p_block_group_id is the requester's
-- LOCAL block group id ("group.<social_group_id>") used later for the unblock.
create or replace function public.send_group_time_request(
  p_social_group_id uuid, p_block_group_id text, p_seconds int,
  p_message text, p_photo_path text)
returns uuid language plpgsql security definer as $$
declare req_id uuid; reqd int; recips uuid[]; names text[];
begin
  if not public.is_group_member(p_social_group_id) then raise exception 'not a member'; end if;
  select approvals_required into reqd from public.group_config where group_id = p_social_group_id;
  select array_agg(user_id) into recips from public.group_members
    where group_id = p_social_group_id and left_at is null and user_id <> auth.uid();
  select app_names into names from public.group_config where group_id = p_social_group_id;
  req_id := gen_random_uuid();
  insert into public.time_requests(
    id, group_id, social_group_id, requester_id, recipient_ids, requested_seconds,
    message, photo_path, status, approvals_required, approvers, group_app_names,
    created_at, expires_at)
  values (
    req_id, p_block_group_id, p_social_group_id, auth.uid(), coalesce(recips,'{}'),
    p_seconds, p_message, p_photo_path, 'pending', greatest(coalesce(reqd,1),1), '{}',
    names, now(), now() + interval '8 hours');
  return req_id;
end; $$;

-- Approve/deny a group time request. Approval is counted; once approvals_required
-- distinct members approve, status flips to 'approved'.
create or replace function public.respond_group_time_request(p_request_id uuid, p_approve boolean)
returns text language plpgsql security definer as $$
declare r public.time_requests%rowtype; new_status text;
begin
  select * into r from public.time_requests where id = p_request_id for update;
  if r.id is null then raise exception 'no such request'; end if;
  if not (auth.uid() = any(r.recipient_ids)) then raise exception 'not a recipient'; end if;
  if r.status <> 'pending' then return r.status; end if;
  if not p_approve then
    update public.time_requests set status='denied', resolved_at=now() where id=p_request_id;
    return 'denied';
  end if;
  if not (auth.uid() = any(r.approvers)) then
    r.approvers := array_append(r.approvers, auth.uid());
  end if;
  new_status := case when array_length(r.approvers,1) >= coalesce(r.approvals_required,1)
                     then 'approved' else 'pending' end;
  update public.time_requests
    set approvers = r.approvers,
        status = new_status,
        resolved_at = case when new_status='approved' then now() else resolved_at end
    where id = p_request_id;
  return new_status;
end; $$;
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/0002_group_time_requests.sql
# message: "Add Supabase group time-request columns + RPCs (SP4 T1)"
```

---

## Task 2: Core — approval progress helper (TDD)

**Files:**
- Modify: `Sources/ScreenTimeSharingCore/FriendGroupModels.swift`
- Test: `Tests/ScreenTimeSharingCoreTests/FriendGroupModelsTests.swift`

**Interfaces — Produces:** `enum GroupApproval { static func progressLabel(count: Int, required: Int) -> String ; static func isApproved(count: Int, required: Int) -> Bool }`

- [ ] **Step 1: Append failing tests**

```swift
func test_groupApproval_progressAndApproved() {
    XCTAssertEqual(GroupApproval.progressLabel(count: 2, required: 3), "2 of 3 approved")
    XCTAssertFalse(GroupApproval.isApproved(count: 2, required: 3))
    XCTAssertTrue(GroupApproval.isApproved(count: 3, required: 3))
    XCTAssertTrue(GroupApproval.isApproved(count: 1, required: 1))
    XCTAssertTrue(GroupApproval.isApproved(count: 4, required: 3))  // never under-approved
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter FriendGroupModelsTests` → FAIL (GroupApproval not found).

- [ ] **Step 3: Append implementation**

```swift
public enum GroupApproval {
    public static func isApproved(count: Int, required: Int) -> Bool { count >= max(required, 1) }
    public static func progressLabel(count: Int, required: Int) -> String {
        "\(count) of \(max(required, 1)) approved"
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test` → PASS (no regression).

- [ ] **Step 5: Commit**

```bash
git add Sources/ScreenTimeSharingCore/FriendGroupModels.swift Tests/ScreenTimeSharingCoreTests/FriendGroupModelsTests.swift
# message: "Add group-approval progress helper (SP4 T2)"
```

---

## Task 3: Store — group time-request RPC wrappers

**Files:**
- Modify: `ScreenTimeSharing/Services/SupabaseSnapshotStore.swift`

**Interfaces — Produces:**
- `func sendGroupTimeRequest(socialGroupID: String, blockGroupID: String, seconds: Int, message: String, photoPath: String?) async throws -> String` (returns request id)
- `func respondGroupTimeRequest(requestID: String, approve: Bool) async throws -> String` (returns new status)

- [ ] **Step 1: Add the wrappers (mirror updateFriendRequest's RPC style)**

```swift
func sendGroupTimeRequest(socialGroupID: String, blockGroupID: String,
                          seconds: Int, message: String, photoPath: String?) async throws -> String {
    struct P: Encodable {
        let p_social_group_id: String; let p_block_group_id: String
        let p_seconds: Int; let p_message: String; let p_photo_path: String?
    }
    let id: String = try await client.rpc("send_group_time_request", params: P(
        p_social_group_id: socialGroupID, p_block_group_id: blockGroupID,
        p_seconds: seconds, p_message: message, p_photo_path: photoPath)).execute().value
    return id
}

func respondGroupTimeRequest(requestID: String, approve: Bool) async throws -> String {
    struct P: Encodable { let p_request_id: String; let p_approve: Bool }
    let status: String = try await client.rpc("respond_group_time_request",
        params: P(p_request_id: requestID, p_approve: approve)).execute().value
    return status
}
```

> Codex: match the EXACT supabase-swift `rpc(_:params:)` + `.execute().value` decoding style used by the existing `updateFriendRequest` (RespondParams/CollectParams pattern) and `createGroup` wrappers. Decode the scalar return (uuid/text) the same way the existing code decodes scalar RPC results.

- [ ] **Step 2: Build + commit**

Run: `xcodebuild … build` → BUILD SUCCEEDED.
```bash
git add ScreenTimeSharing/Services/SupabaseSnapshotStore.swift
# message: "Add group time-request RPC wrappers (SP4 T3)"
```

---

## Task 4: AppModel — send a group request; route approve to the group RPC

**Files:**
- Modify: `ScreenTimeSharing/AppModel.swift`

**Interfaces — Consumes:** Task 3 wrappers; existing `requestFriendTime`/`approveFriendRequest`/`collectFriendRequest`/`sendPushNotification`/photo store. **Produces:**
- `func requestGroupTime(socialGroupID: String, seconds: TimeInterval, message: String, photoJPEGData: Data?) async -> Bool`

- [ ] **Step 1: Implement requestGroupTime (mirror requestFriendTime, group recipients)**

Read `requestFriendTime` first. Then add a group variant that: saves the selfie locally + uploads it (reuse the friend-request photo path), calls `snapshotStore.sendGroupTimeRequest(socialGroupID:blockGroupID:"group.\(socialGroupID)":seconds:message:photoPath:)`, then `await syncFriendRequests()` so the new row appears in the existing feed, and pushes to group members. Representative:

```swift
@MainActor func requestGroupTime(socialGroupID: String, seconds: TimeInterval,
                                 message: String, photoJPEGData: Data?) async -> Bool {
    do {
        let photoPath = try await uploadRequestPhotoIfNeeded(photoJPEGData)   // reuse existing upload
        _ = try await snapshotStore.sendGroupTimeRequest(
            socialGroupID: socialGroupID, blockGroupID: "group.\(socialGroupID)",
            seconds: Int(seconds), message: message, photoPath: photoPath)
        await syncFriendRequests()
        return true
    } catch { message = "Could not send the request: \(error.localizedDescription)"; return false }
}
```

> Codex: use the REAL existing photo-upload path (read how requestFriendTime/publishFriendRequestToCloud uploads to the request-photos bucket) rather than a new uploader. If no standalone uploader exists, inline the same upload the friend flow uses.

- [ ] **Step 2: Route group-request approval to the group RPC**

A group request row has a non-null `social_group_id`. Ensure `TimeRequestRow`/`BlockFriendRequest` carries whether it is a group request (read `SupabaseRowMapping` — add a `socialGroupID: String?` passthrough if not present). In the approve path: when the request being approved is a group request, call `snapshotStore.respondGroupTimeRequest(requestID:approve:true)` instead of the friend `respond_to_time_request`; on deny, `respondGroupTimeRequest(...false)`. Keep the existing friend path unchanged for non-group requests. After responding, `await syncFriendRequests()`.

> Codex: the cleanest hook is where `approveFriendRequest`/`denyFriendRequest` publish to cloud (`updateFriendRequest`). Branch on group vs friend there, or add `approveGroupRequest(id:)`/`denyGroupRequest(id:)` that the UI calls for group requests. Collection stays `collectFriendRequest` (unchanged — it builds the `BlockUnblockSession` for `"group.<id>"`).

- [ ] **Step 3: Build + commit**

Run: `xcodebuild … build` → BUILD SUCCEEDED.
```bash
git add ScreenTimeSharing/AppModel.swift ScreenTimeSharing/Services/SupabaseRowMapping.swift
# message: "Add group time-request send + approve routing on AppModel (SP4 T4)"
```

---

## Task 5: UI — "Ask group for more time" composer

**Files:**
- Modify: `ScreenTimeSharing/Views/GroupsView.swift`

- [ ] **Step 1: Add the composer to `GroupDetailView`**

For a `per_member` group where the viewer is configured (`configuredAt != nil`), add an "Ask group for more time" button that presents a small sheet: a minutes stepper (→ seconds), a message TextField, and (reuse the onboarding/friend selfie capture if simple, else optional) a photo. On submit: `await model.requestGroupTime(socialGroupID: groupID, seconds: minutes*60, message: text, photoJPEGData: data)`; on success dismiss + a confirmation. Approvers will see and approve the request in the existing requests feed (no new approval UI needed here).

> Codex: keep it minimal — a sheet with minutes + message is enough for MVP; photo optional (match how the friend request composer captures a selfie if reusable, otherwise omit the photo for the group composer and pass nil). Match GroupsView styling. Approval display ("2 of 3 approved") via `GroupApproval.progressLabel` can be shown in the existing request feed in a later polish; not required here.

- [ ] **Step 2: Build + manual verify**

Run: `xcodebuild … build` → BUILD SUCCEEDED.
Manual (device, SQL applied): blocked member asks the group → other members see the request in their feed → after `approvals_required` approvals the requester can collect → temporary unblock lifts the shield for the requested minutes.

- [ ] **Step 3: Commit**

```bash
git add ScreenTimeSharing/Views/GroupsView.swift
# message: "Add ask-group-for-more-time composer (SP4 T5)"
```

---

## Final verification (SP4)

- [ ] `swift test` — Core green (existing + GroupApproval).
- [ ] `xcodebuild … build` — app builds.
- [ ] Owner applies `supabase/migrations/0002_group_time_requests.sql`; manual device E2E of the request → N approvals → collect → temporary unblock.

---

## Self-Review (against spec §5 SP4)

- **Coverage:** group request send → Tasks 1,3,4,5; N-approval counting (server) → Task 1 `respond_group_time_request`; approve via group RPC → Task 4; temporary unblock on approval (personal only) → reuse `collectFriendRequest` (Task 4 note); reuse existing feed/push/photo → Tasks 4,5. Pool-credit explicitly NOT done (personal unblock), per spec.
- **Placeholder scan:** SQL + Core shown in full; Swift tasks give exact wrapper code + signatures + the real reuse points (requestFriendTime/collectFriendRequest/photo upload) to read — the deferred bits ("use the real photo uploader", "branch in updateFriendRequest") are explicit read-and-match instructions, not gaps.
- **Type consistency:** `sendGroupTimeRequest`/`respondGroupTimeRequest`, `requestGroupTime`, the `"group.<socialGroupID>"` block id, and `GroupApproval` are consistent across tasks and reuse SP1/SP2's committed types.

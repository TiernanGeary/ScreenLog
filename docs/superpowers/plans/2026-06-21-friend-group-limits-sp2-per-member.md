# Friend-Group SP2 (Per-member same-limit mode) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.
>
> **Project model (CLAUDE.md):** Claude plans & verifies; **Codex implements**. Codex's sandbox blocks `.git`, so **Claude commits** (English messages + `Co-Authored-By` trailer). New files are registered in the Xcode app target by Claude (surgical pbxproj edit). Commit each task explicitly by file path (avoid `git add -A`; the repo has CRLF stat-noise on some files).

**Goal:** Let a member of a `per_member` group adopt the group's restriction locally — pick the agreed apps via FamilyActivityPicker and start a real daily time-limit block with an auto-generated (member-hidden) password — and mark themselves "configured".

**Architecture:** Reuse the existing local blocking system (`BlockGroup` + `AppModel.upsertBlockGroup`) exactly like the onboarding block setup (`OnboardingView` BlockSetupPage). A pure Core builder constructs the per-member `BlockGroup`; the auto-generated password is stored in the Keychain (so SP4 can later drive approved unlocks, and the member can't self-unblock). On success the app calls SP1's `set_member_configured`.

**Tech Stack:** SwiftUI, FamilyControls (`FamilyActivityPicker`), ManagedSettings (via existing enforcement), Keychain (Security.framework), Core (`ScreenTimeSharingCore` + XCTest).

**Spec:** `docs/superpowers/specs/2026-06-21-friend-group-limits-design.md` (§5 SP2).
**Branch:** `feature/friend-group-limits` (SP1 already merged into this branch).

## Global Constraints

- **No code by Claude** beyond trivial config / pbxproj registration; Codex implements; Claude commits.
- **Per-member block (verbatim, spec §2/§5):** local `BlockGroup` with `mode = .timeLimit(limitSeconds: <perMemberLimitSeconds as TimeInterval>, days: BlockWeekday.everyDay)`, `isEnabled = true`, app selection picked LOCALLY via `FamilyActivityPicker`, **password AUTO-GENERATED** (member never sees it; stored in Keychain). On success call `set_member_configured(true)`.
- **App selection is device-local** (FamilyActivitySelection tokens) — the member picks the apps that match the group's `app_names` list (shown as guidance); sameness is honor-system.
- **No import of `ScreenTimeSharingCore` in app files** (Core compiles directly into the app target).
- **Core tests:** `swift test`. **App build:** `xcodebuild -project ScreenTimeSharing.xcodeproj -scheme ScreenTimeSharing -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`.
- **UI copy:** English.

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `Sources/ScreenTimeSharingCore/FriendGroupModels.swift` | Add `GroupBlock` (per-member BlockGroup builder + password generator) | Modify (Task 1) |
| `Tests/ScreenTimeSharingCoreTests/FriendGroupModelsTests.swift` | Tests for the above | Modify (Task 1) |
| `ScreenTimeSharing/Services/GroupBlockPasswordStore.swift` | **NEW** Keychain store for per-group auto-gen passwords | Create (Task 2) |
| `ScreenTimeSharing/AppModel.swift` | `adoptGroupBlock(...)`, `removeGroupBlock(...)`, wire into leaveGroup | Modify (Task 3) |
| `ScreenTimeSharing/Views/GroupsView.swift` | `GroupBlockSetupSheet` + wire into `GroupDetailView` (per_member: "Set up your block" / re-apply on config change) | Modify (Task 4) |

New file (Task 2) → register in app target (Claude). Reference patterns: onboarding adoption `OnboardingView.swift` (FamilyActivityPicker ~L1284, encode ~L1556, `upsertBlockGroup` ~L1565), `OnboardingBlock.makeFirstBlockGroup` (`Sources/ScreenTimeSharingCore/OnboardingActivation.swift`), `BlockGroup.init` (`BlockingModels.swift` ~L311), `BlockGroupMode.timeLimit` (~L115), `AppModel.upsertBlockGroup` (~L693), SP1 `loadGroupDetail`/`FriendGroupSummary`/`GroupBlockConfig`/`snapshotStore.setMemberConfigured`/`leaveGroup`.

---

## Task 1: Core — per-member BlockGroup builder + password generator (TDD)

**Files:**
- Modify: `Sources/ScreenTimeSharingCore/FriendGroupModels.swift`
- Test: `Tests/ScreenTimeSharingCoreTests/FriendGroupModelsTests.swift`

**Interfaces — Produces:**
- `enum GroupBlock { static func makeBlockGroup(id: String, name: String, selectionData: Data, limitSeconds: TimeInterval) -> BlockGroup ; static func generatePassword(length: Int = 16) -> String }`

- [ ] **Step 1: Append failing tests**

```swift
func test_groupBlock_makeBlockGroup_perMemberDefaults() {
    let g = GroupBlock.makeBlockGroup(id: "g1", name: "Study group",
                                      selectionData: Data([0x01, 0x02]), limitSeconds: 1800)
    XCTAssertEqual(g.id, "g1")
    XCTAssertEqual(g.name, "Study group")
    XCTAssertEqual(g.selectionData, Data([0x01, 0x02]))
    XCTAssertTrue(g.isEnabled)
    if case let .timeLimit(secs, days) = g.mode {
        XCTAssertEqual(secs, 1800)
        XCTAssertEqual(days, BlockWeekday.everyDay)
    } else { XCTFail("must be .timeLimit everyday") }
}

func test_groupBlock_generatePassword_lengthAndCharset() {
    let p = GroupBlock.generatePassword()
    XCTAssertEqual(p.count, 16)
    let allowed = Set("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789")
    XCTAssertTrue(p.allSatisfy { allowed.contains($0) })
    XCTAssertNotEqual(p, GroupBlock.generatePassword())  // randomized
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter FriendGroupModelsTests`
Expected: FAIL — `GroupBlock` not found.

- [ ] **Step 3: Append implementation to `FriendGroupModels.swift`**

```swift
public enum GroupBlock {
    /// Builds the local per-member block: a daily time-limit over the picked apps.
    /// Mirror BlockGroup defaults used by OnboardingBlock.makeFirstBlockGroup.
    public static func makeBlockGroup(id: String, name: String,
                                      selectionData: Data, limitSeconds: TimeInterval) -> BlockGroup {
        let now = Date()
        return BlockGroup(
            id: id,
            name: name,
            colorHex: "#6A4C93",
            selectionData: selectionData,
            isEnabled: true,
            mode: .timeLimit(limitSeconds: limitSeconds, days: BlockWeekday.everyDay),
            createdAt: now,
            updatedAt: now
        )
    }

    /// Random, member-hidden password for the auto-locked group block.
    public static func generatePassword(length: Int = 16) -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789"
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }
}
```

> Codex: if `BlockGroup.init` requires more/fewer args than OnboardingBlock.makeFirstBlockGroup uses, match that real initializer (read OnboardingActivation.swift + BlockingModels.swift); keep the asserted fields exactly.

- [ ] **Step 4: Run to verify pass**

Run: `swift test` (full Core suite, no regression)
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ScreenTimeSharingCore/FriendGroupModels.swift Tests/ScreenTimeSharingCoreTests/FriendGroupModelsTests.swift
# message: "Add per-member group BlockGroup builder + password generator (SP2 T1)"
```

---

## Task 2: Keychain store for per-group block passwords

**Files:**
- Create: `ScreenTimeSharing/Services/GroupBlockPasswordStore.swift`
- (Claude) Modify: `ScreenTimeSharing.xcodeproj/project.pbxproj` (register file in app target)

**Interfaces — Produces:**
- `enum GroupBlockPasswordStore { static func save(_ password: String, groupID: String) ; static func load(groupID: String) -> String? ; static func delete(groupID: String) }`

- [ ] **Step 1: Implement the Keychain store**

A minimal `kSecClassGenericPassword` wrapper keyed by `"group-block.\(groupID)"`, account = app bundle group. Mirror any existing Keychain usage style in the repo (see AppleSignInService.swift / SupabaseClientProvider.swift for the Security.framework pattern already used).

```swift
import Foundation
import Security

enum GroupBlockPasswordStore {
    private static func key(_ groupID: String) -> String { "group-block.\(groupID)" }

    static func save(_ password: String, groupID: String) {
        delete(groupID: groupID)
        guard let data = password.data(using: .utf8) else { return }
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key(groupID),
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func load(groupID: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key(groupID),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(groupID: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key(groupID)
        ]
        SecItemDelete(q as CFDictionary)
    }
}
```

- [ ] **Step 2: (Claude) Register in app target + build**

Claude adds `GroupBlockPasswordStore.swift` to the `ScreenTimeSharing` target (surgical pbxproj entries), then:
Run: `xcodebuild … build` → BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ScreenTimeSharing/Services/GroupBlockPasswordStore.swift ScreenTimeSharing.xcodeproj/project.pbxproj
# message: "Add Keychain store for per-group block passwords (SP2 T2)"
```

---

## Task 3: AppModel — adopt / remove the group block

**Files:**
- Modify: `ScreenTimeSharing/AppModel.swift`

**Interfaces — Consumes:** `GroupBlock` (Core), `GroupBlockPasswordStore`, `BlockingSelectionCodec.encode`, `upsertBlockGroup`, `requestScreenTimeAuthorization`/`hasScreenTimeAuthorization`, `snapshotStore.setMemberConfigured`, existing `leaveGroup`. **Produces:**
- `func adoptGroupBlock(groupID: String, limitSeconds: Int, selection: FamilyActivitySelection) async -> Bool`
- `func removeGroupBlock(groupID: String)`

- [ ] **Step 1: Implement (mirror the onboarding adoption flow)**

```swift
@MainActor func adoptGroupBlock(groupID: String, limitSeconds: Int,
                                selection: FamilyActivitySelection) async -> Bool {
    if !hasScreenTimeAuthorization {
        await requestScreenTimeAuthorization()
        guard hasScreenTimeAuthorization else { return false }
    }
    guard let data = try? BlockingSelectionCodec.encode(selection) else {
        message = "Could not save your app selection."; return false
    }
    let password = GroupBlock.generatePassword()
    let group = GroupBlock.makeBlockGroup(
        id: "group.\(groupID)", name: "Group limit",
        selectionData: data, limitSeconds: TimeInterval(limitSeconds))
    guard upsertBlockGroup(group, password: password) else { return false }  // message set on failure
    GroupBlockPasswordStore.save(password, groupID: groupID)
    do { try await snapshotStore.setMemberConfigured(groupID: groupID, configured: true) }
    catch { /* block is live locally; configured flag will re-sync */ }
    return true
}

func removeGroupBlock(groupID: String) {
    // Disable + remove the local block group and its stored password.
    deleteBlockGroup(id: "group.\(groupID)")   // use the existing delete/remove API on AppModel
    GroupBlockPasswordStore.delete(groupID: groupID)
}
```

> Codex: use the block-group id convention `"group.\(groupID)"` consistently. Use the ACTUAL AppModel API to delete/disable a block group (read AppModel for the existing delete method, e.g. `deleteBlockGroup`/`removeBlockGroup`/toggling `isEnabled`); if none exists, disable by upserting the group with `isEnabled=false` using the stored password. Call `removeGroupBlock` from the existing `leaveGroup(_:)` after a successful backend leave.

- [ ] **Step 2: Build + commit**

Run: `xcodebuild … build` → BUILD SUCCEEDED.
```bash
git add ScreenTimeSharing/AppModel.swift
# message: "Add adopt/remove group block on AppModel (SP2 T3)"
```

---

## Task 4: UI — group block setup + configured status + re-apply

**Files:**
- Modify: `ScreenTimeSharing/Views/GroupsView.swift`

**Interfaces — Consumes:** `AppModel.adoptGroupBlock`, `loadGroupDetail`, `FriendGroupSummary`/`GroupDetail`/`GroupBlockConfig`, `GroupMembership.configuredSummary`, Core `GroupMode`.

- [ ] **Step 1: Add `GroupBlockSetupSheet` + wire into `GroupDetailView`**

In `GroupsView.swift`:
- Add `private struct GroupBlockSetupSheet: View` (mirror the onboarding BlockSetupPage in OnboardingView.swift): shows the group's `app_names` list as guidance text ("Your group restricts: Instagram, TikTok…"), a "Choose apps to block" button presenting `FamilyActivityPicker(selection:)`, the selected count, and a "Start blocking" button that is disabled until ≥1 token is selected. On tap: `await model.adoptGroupBlock(groupID:limitSeconds:selection:)` where `limitSeconds` = the group config's `perMemberLimitSeconds`; on success dismiss + refresh detail. NO passcode field (password is auto-generated).
- In `GroupDetailView`, for a `per_member` group where the viewer's `configuredAt == nil`, show a prominent "Set up your block" button presenting `GroupBlockSetupSheet`. When `configuredAt != nil`, show "✓ You're blocking <N> apps · <limit> min/day" with an "Update apps" action that re-presents the sheet.
- Config-change re-apply: when `loadGroupDetail` shows the group `config.updatedAt` is newer than the local adoption (compare against `configuredAt`), surface a "Group settings changed — re-apply" banner that re-presents `GroupBlockSetupSheet`.

> Codex: match the onboarding BlockSetupPage's FamilyActivityPicker presentation + the simulator guard it uses (FamilyActivityPicker has no selectable apps in the simulator). Keep styling consistent with the existing GroupsView views. Do not add a passcode UI.

- [ ] **Step 2: Build + manual verify**

Run: `xcodebuild … build` → BUILD SUCCEEDED.
Manual (real device, after SQL applied): join a per_member group → "Set up your block" → pick apps → Start → the block appears in Blocking Settings as a daily-limit group; the group member list shows you as ✓ configured; leaving the group removes the local block.

- [ ] **Step 3: Commit**

```bash
git add ScreenTimeSharing/Views/GroupsView.swift
# message: "Add group block setup UI + configured status (SP2 T4)"
```

---

## Final verification (SP2)

- [ ] `swift test` — Core green (existing + new GroupBlock tests).
- [ ] `xcodebuild … build` — app builds.
- [ ] Manual (device, SQL applied): adopt → block enforced as daily limit; configured ✓ syncs; config change prompts re-apply; leave removes the local block + Keychain password.

---

## Self-Review (against spec §5 SP2)

- **Coverage:** local BlockGroup adoption (picker + .timeLimit + auto password) → Tasks 1–4; auto-generated Keychain password → Tasks 1–3; set_member_configured → Task 3; configured ✓/✗ + config-change re-apply → Task 4; leave removes local block → Task 3 (wired into leaveGroup). Pool mode (SP3) and approval unlock (SP4) are out of THIS plan.
- **Placeholder scan:** Core/Keychain shown in full; app tasks give exact AppModel signatures + flow + the onboarding pattern to mirror (no "handle errors" hand-waving). The only deferred detail (exact existing block-delete API) is an explicit "read AppModel and use the real method" instruction, not a gap.
- **Type consistency:** `GroupBlock.makeBlockGroup`/`generatePassword`, `GroupBlockPasswordStore.save/load/delete`, `adoptGroupBlock`/`removeGroupBlock`, block id `"group.<groupID>"`, and `setMemberConfigured(groupID:configured:)` are consistent across tasks and match SP1's committed types.

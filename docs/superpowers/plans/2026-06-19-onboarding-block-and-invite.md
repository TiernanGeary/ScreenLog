# Onboarding Activation (Real Block + Friend Invite) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Project model (CLAUDE.md):** Claude plans & verifies; **Codex implements** (`/codex:rescue --write`). Codex's sandbox blocks `.git`, so **Claude performs all commits** (English messages, append the standard `Co-Authored-By` trailer). Commit step commands below show the staging + message only.

**Goal:** Make onboarding fire real value at peak motivation — start a real time‑limit block (≥1 app, passcode‑gated) and then offer a friend‑invite share — gating completion on an active block.

**Architecture:** Restructure the tail of `OnboardingView.swift` into 8 pages (`… → permissions → block setup → invite`). Reuse the existing blocking system (`BlockGroup` + `AppModel.upsertBlockGroup`) and invite system (`AppModel.createInvite` + `ShareLink`) unchanged. Push all unit‑testable logic (share‑message text, min‑selection gate, default BlockGroup factory) into a new pure Core file so `swift test` covers it; UI wiring is verified by Xcode build + manual run.

**Tech Stack:** SwiftUI, FamilyControls (`FamilyActivityPicker`, `requestScreenTimeAuthorization`), ManagedSettings (via existing `BlockingEnforcementService`), Swift Package `ScreenTimeSharingCore` + XCTest (`swift test`).

**Spec:** `docs/superpowers/specs/2026-06-19-onboarding-block-and-invite-design.md`

**Base branch:** `feature/onboarding-updates` (already checked out, from merged `main` baseline `03e5df2`).

## Global Constraints

- **Reuse only — no parallel systems.** Create/start blocks exclusively via `AppModel.upsertBlockGroup(_:password:)`; create invites via `AppModel.createInvite()`. No new public AppModel methods unless a task explicitly says so.
- **Block defaults (verbatim):** `mode = .timeLimit(limitSeconds: 30*60, days: BlockWeekday.everyDay)`, `isEnabled = true`, non‑empty `name`, `selectionData` = `BlockingSelectionCodec.encode(selection)`, `unblockConfig`/`friendRequestConfig` = type defaults, `password` = user‑entered passcode (required for new groups).
- **Block gate:** completion is blocked unless `applicationTokens.count + categoryTokens.count + webDomainTokens.count >= 1`.
- **Completion gate:** `completeOnboarding()` is reachable only after (1) Screen Time authorized AND (2) ≥1 block group started. Invite is **skippable** and never gates completion.
- **Invite share text:** must contain BOTH the App Store install URL AND the `deny://invite/CODE` invite URL; manual code de‑emphasized/omitted.
- **UI copy language:** English, matching existing onboarding page tone (e.g. "You're all set", "How Deny works"). (Conversation/spec used Japanese for discussion only.)
- **No universal‑link / deferred‑deep‑link work** (out of scope per spec §2).
- **Verification reality:** `swift test` covers Core only (new tests + 66 existing regression). App‑layer changes verified by `xcodebuild` build of the app target + manual run; `FamilyActivityPicker` content and real shielding require a real device.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `Sources/ScreenTimeSharingCore/OnboardingActivation.swift` | **NEW** pure helpers: invite‑message builder, min‑selection predicate, default BlockGroup factory | Create (Tasks 1–3) |
| `Tests/ScreenTimeSharingCoreTests/OnboardingActivationTests.swift` | **NEW** unit tests for the above | Create (Tasks 1–3) |
| `ScreenTimeSharing/AppConfiguration.swift` | App‑wide config constants | Add `appStoreURL` (Task 6) |
| `ScreenTimeSharing/Views/OnboardingView.swift` | Onboarding flow + page subviews | Restructure tail, add 2 pages, wire logic (Tasks 4–6) |

New Core files are auto‑discovered by SwiftPM (`swift test`) and compiled into the app via the package product — **no `.xcodeproj` edits needed**. App‑layer work modifies existing files only (no new app files), so no manual project‑reference additions.

Symbols referenced from existing code (confirm exact current line by symbol name, lines may have shifted):
- `OnboardingView`: `totalPages = 6` (~L32), derived `lastPage`/`profilePage`, primary‑button/permission closure (~L213–246), `FinalPage` (~L1059), `FinalPermissionRow` (~L1143).
- `AppModel`: `upsertBlockGroup(_:password:)` (~L691), `requestScreenTimeAuthorization()` (~L1076), `hasScreenTimeAuthorization` (~L281), `createInvite()` (~L1156), `completeOnboarding()` (~L330).
- Core: `BlockGroup`, `BlockGroupMode.timeLimit`, `BlockWeekday.everyDay`, `BlockUnblockConfig`, `BlockFriendRequestConfig` in `Sources/ScreenTimeSharingCore/BlockingModels.swift`.
- `BlockingSelectionCodec.encode/decode` in `ScreenTimeSharing/Services/BlockingSelectionCodec.swift`.
- Picker pattern + draft→group conversion in `ScreenTimeSharing/Views/BlockingSettingsView.swift` (~L2717, ~L3240).
- Existing invite share text: `InviteFriendsSheet.shareMessage(for:)` (~L168).

---

## Task 1: Core — friend‑invite share‑message builder

Pure function composing the onboarding share text from a display name, App Store URL, and invite URL.

**Files:**
- Create: `Sources/ScreenTimeSharingCore/OnboardingActivation.swift`
- Test: `Tests/ScreenTimeSharingCoreTests/OnboardingActivationTests.swift`

**Interfaces:**
- Produces: `enum OnboardingInvite { static func shareMessage(displayName: String?, appStoreURL: URL, inviteURL: URL) -> String }`

- [ ] **Step 1: Write the failing test**

In `Tests/ScreenTimeSharingCoreTests/OnboardingActivationTests.swift`:

```swift
import XCTest
@testable import ScreenTimeSharingCore

final class OnboardingActivationTests: XCTestCase {
    func test_shareMessage_containsBothAppStoreAndInviteURLs() {
        let appStore = URL(string: "https://apps.apple.com/app/id000000000")!
        let invite = URL(string: "deny://invite/ABCD1234")!

        let msg = OnboardingInvite.shareMessage(
            displayName: "Leo", appStoreURL: appStore, inviteURL: invite)

        XCTAssertTrue(msg.contains(appStore.absoluteString),
                      "share text must include the App Store install URL")
        XCTAssertTrue(msg.contains(invite.absoluteString),
                      "share text must include the deny:// invite URL")
    }

    func test_shareMessage_handlesNilName() {
        let appStore = URL(string: "https://apps.apple.com/app/id000000000")!
        let invite = URL(string: "deny://invite/ABCD1234")!

        let msg = OnboardingInvite.shareMessage(
            displayName: nil, appStoreURL: appStore, inviteURL: invite)

        XCTAssertFalse(msg.isEmpty)
        XCTAssertTrue(msg.contains(invite.absoluteString))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter OnboardingActivationTests`
Expected: FAIL — `OnboardingInvite` / `shareMessage` not found.

- [ ] **Step 3: Write minimal implementation**

In `Sources/ScreenTimeSharingCore/OnboardingActivation.swift`:

```swift
import Foundation

public enum OnboardingInvite {
    /// Share text for the onboarding invite step. Includes BOTH the App Store
    /// install link (for friends who don't have the app) and the deny:// invite
    /// link (taps auto‑connect once installed). Manual code is intentionally omitted.
    public static func shareMessage(displayName: String?,
                                    appStoreURL: URL,
                                    inviteURL: URL) -> String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespaces)
        let who = (trimmed?.isEmpty == false && trimmed != "Me") ? trimmed! : "me"
        return """
        I'm using Deny to take back control of my screen time. Get it: \
        \(appStoreURL.absoluteString)
        Then tap to add \(who): \(inviteURL.absoluteString)
        """
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter OnboardingActivationTests`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ScreenTimeSharingCore/OnboardingActivation.swift Tests/ScreenTimeSharingCoreTests/OnboardingActivationTests.swift
# message: "Add onboarding invite share-message builder (Core)"
```

---

## Task 2: Core — minimum‑selection gate predicate

Pure predicate the block page uses to enforce "≥1 selected" without importing FamilyControls into Core.

**Files:**
- Modify: `Sources/ScreenTimeSharingCore/OnboardingActivation.swift`
- Test: `Tests/ScreenTimeSharingCoreTests/OnboardingActivationTests.swift`

**Interfaces:**
- Produces: `OnboardingBlock.meetsMinimumSelection(appCount: Int, categoryCount: Int, webCount: Int) -> Bool`

- [ ] **Step 1: Write the failing test** (append to `OnboardingActivationTests`)

```swift
func test_meetsMinimumSelection_falseWhenAllZero() {
    XCTAssertFalse(OnboardingBlock.meetsMinimumSelection(appCount: 0, categoryCount: 0, webCount: 0))
}

func test_meetsMinimumSelection_trueWhenAnyNonZero() {
    XCTAssertTrue(OnboardingBlock.meetsMinimumSelection(appCount: 1, categoryCount: 0, webCount: 0))
    XCTAssertTrue(OnboardingBlock.meetsMinimumSelection(appCount: 0, categoryCount: 2, webCount: 0))
    XCTAssertTrue(OnboardingBlock.meetsMinimumSelection(appCount: 0, categoryCount: 0, webCount: 3))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter OnboardingActivationTests`
Expected: FAIL — `OnboardingBlock` not found.

- [ ] **Step 3: Write minimal implementation** (append to `OnboardingActivation.swift`)

```swift
public enum OnboardingBlock {
    /// Onboarding requires at least one app/category/web selection before the
    /// user can start their first block.
    public static func meetsMinimumSelection(appCount: Int,
                                             categoryCount: Int,
                                             webCount: Int) -> Bool {
        (appCount + categoryCount + webCount) >= 1
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter OnboardingActivationTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ScreenTimeSharingCore/OnboardingActivation.swift Tests/ScreenTimeSharingCoreTests/OnboardingActivationTests.swift
# message: "Add onboarding min-selection gate predicate (Core)"
```

---

## Task 3: Core — default onboarding BlockGroup factory

Pure factory that builds the onboarding `BlockGroup` with the agreed defaults, given encoded selection data, a name, and an id. Password is NOT part of the group (it is passed separately to `upsertBlockGroup`).

**Files:**
- Modify: `Sources/ScreenTimeSharingCore/OnboardingActivation.swift`
- Test: `Tests/ScreenTimeSharingCoreTests/OnboardingActivationTests.swift`

**Interfaces:**
- Consumes: existing `BlockGroup`, `BlockGroupMode.timeLimit`, `BlockWeekday.everyDay` (Core).
- Produces: `OnboardingBlock.makeFirstBlockGroup(id: String, name: String, selectionData: Data) -> BlockGroup`

> Codex: use the **actual** `BlockGroup` initializer and supporting types as defined in `BlockingModels.swift`. Set `mode`, `isEnabled`, `name`, `selectionData` exactly as the Global Constraints state; leave `unblockConfig`/`friendRequestConfig` at their type defaults; set `createdAt`/`updatedAt` to the passed/now date as the initializer requires. The test below asserts resulting field values, not the initializer shape.

- [ ] **Step 1: Write the failing test** (append to `OnboardingActivationTests`)

```swift
func test_makeFirstBlockGroup_setsAgreedDefaults() {
    let data = Data([0x01, 0x02, 0x03]) // opaque, non-empty
    let group = OnboardingBlock.makeFirstBlockGroup(
        id: "grp-1", name: "My First Block", selectionData: data)

    XCTAssertEqual(group.id, "grp-1")
    XCTAssertEqual(group.name, "My First Block")
    XCTAssertEqual(group.selectionData, data)
    XCTAssertTrue(group.isEnabled)
    if case let .timeLimit(limitSeconds, days) = group.mode {
        XCTAssertEqual(limitSeconds, 30 * 60)
        XCTAssertEqual(days, BlockWeekday.everyDay)
    } else {
        XCTFail("onboarding block must use .timeLimit mode")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter OnboardingActivationTests`
Expected: FAIL — `makeFirstBlockGroup` not found.

- [ ] **Step 3: Write minimal implementation** (extend `OnboardingBlock` in `OnboardingActivation.swift`)

```swift
extension OnboardingBlock {
    /// Builds the onboarding "first block" with agreed defaults. The caller
    /// passes the resulting group to AppModel.upsertBlockGroup(_:password:),
    /// which persists and immediately enforces it.
    public static func makeFirstBlockGroup(id: String,
                                           name: String,
                                           selectionData: Data) -> BlockGroup {
        BlockGroup(
            id: id,
            name: name,
            // colorHex / unblockConfig / friendRequestConfig / timestamps:
            // use BlockGroup's defaults as defined in BlockingModels.swift
            selectionData: selectionData,
            isEnabled: true,
            mode: .timeLimit(limitSeconds: 30 * 60, days: BlockWeekday.everyDay)
        )
    }
}
```

> If `BlockGroup`'s initializer requires additional non‑defaulted arguments (e.g. `colorHex`, `createdAt`, `updatedAt`), Codex supplies sensible defaults (`colorHex` a fixed brand hex, timestamps = `Date()`), keeping the asserted fields exactly as above.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test` (full Core suite — confirm the 66 existing tests still pass alongside the new ones)
Expected: PASS, no regressions.

- [ ] **Step 5: Commit**

```bash
git add Sources/ScreenTimeSharingCore/OnboardingActivation.swift Tests/ScreenTimeSharingCoreTests/OnboardingActivationTests.swift
# message: "Add default onboarding BlockGroup factory (Core)"
```

---

## Task 4: App — restructure onboarding tail into 8 pages (skeleton)

Grow the flow to 8 pages, insert two new page subviews as **stubs** wired into the `TabView`, move `completeOnboarding()` off the permissions page onto the final invite page, and update progress/constants. Deliverable: app builds and swipes through 8 pages; pages 6/7 are placeholders.

**Files:**
- Modify: `ScreenTimeSharing/Views/OnboardingView.swift`

**Interfaces:**
- Produces (stubs filled by Tasks 5–6): `struct BlockSetupPage: View`, `struct InviteFriendsOnboardingPage: View`, both nested/file‑private in `OnboardingView.swift`, each taking the same `@EnvironmentObject`/bindings the sibling pages use plus an `onAdvance`/`onComplete` closure consistent with existing page wiring.

- [ ] **Step 1: Update page count + derived constants**

Change `totalPages` 6 → 8. Keep `lastPage`/`profilePage` derived if they already are; otherwise set `profilePage = 4` and `lastPage = 7`. Before/after:

```swift
// before
private let totalPages = 6
// after
private let totalPages = 8
```

Confirm the progress‑fraction calc still uses `(currentPage + 1) / totalPages` and the How‑It‑Works quarter‑increment logic is unaffected (it keys off the how‑it‑works page tag, not the count).

- [ ] **Step 2: Add two stub page subviews**

Add file‑private stubs near the other page structs (mirror the signature/styling of `FinalPage`):

```swift
private struct BlockSetupPage: View {
    @EnvironmentObject var model: AppModel
    var onStarted: () -> Void          // call after a block is successfully started
    var body: some View {
        VStack { Text("Block setup (stub)") }   // replaced in Task 5
    }
}

private struct InviteFriendsOnboardingPage: View {
    @EnvironmentObject var model: AppModel
    var onFinish: () -> Void           // call on share-or-skip to complete onboarding
    var body: some View {
        VStack { Text("Invite (stub)") }         // replaced in Task 6
    }
}
```

> Match the actual environment/init pattern the existing pages use (e.g. `@EnvironmentObject var model: AppModel` vs passed bindings). Use whatever the sibling structs use.

- [ ] **Step 3: Wire stubs into the TabView at tags 6 and 7**

In the `TabView`, after the existing `FinalPage` content, the tags become: keep current pages 0–4; **page 5 = permissions** (the existing `FinalPage` permission UI, see Step 4); add:

```swift
BlockSetupPage(onStarted: { withAnimation { currentPage = 7 } })
    .tag(6)

InviteFriendsOnboardingPage(onFinish: { model.completeOnboarding() })
    .tag(7)
```

- [ ] **Step 4: Move completion off the permissions page**

In the permissions primary‑button closure (~L213–246), the success path currently calls `model.completeOnboarding()` after Screen Time + optional notifications/camera. Change it to **advance to the block page instead of completing**:

```swift
// after Screen Time approved (+ optional notif/camera requested):
// before:  model.completeOnboarding(); model.requestScreenTimeReportRefresh()
// after:
model.requestScreenTimeReportRefresh()
withAnimation { currentPage = 6 }   // go to Block setup; do NOT complete here
```

Keep the Screen Time required‑gate + "Try Again" inline error exactly as‑is.

- [ ] **Step 5: Build + manual verify**

Run: `xcodebuild -scheme ScreenTimeSharing -destination 'generic/platform=iOS' build` (or the project's standard build invocation)
Expected: BUILD SUCCEEDED.
Manual: launch onboarding → swipe/advance through all 8 pages; permissions page advances to the Block stub (does not finish onboarding); invite stub's finish calls completion.

- [ ] **Step 6: Commit**

```bash
git add ScreenTimeSharing/Views/OnboardingView.swift
# message: "Restructure onboarding into 8 pages with block + invite stubs"
```

---

## Task 5: App — Block setup page (page 6)

Implement the real block step: pick apps via `FamilyActivityPicker`, set a quick passcode, enforce the ≥1 gate, build the group via the Core factory, and start it via `upsertBlockGroup`. On success, call `onStarted()`.

**Files:**
- Modify: `ScreenTimeSharing/Views/OnboardingView.swift`

**Interfaces:**
- Consumes: `OnboardingBlock.meetsMinimumSelection(...)`, `OnboardingBlock.makeFirstBlockGroup(...)` (Tasks 2–3); `BlockingSelectionCodec.encode(_:)`; `AppModel.upsertBlockGroup(_:password:)`, `AppModel.requestScreenTimeAuthorization()`, `AppModel.hasScreenTimeAuthorization`.

- [ ] **Step 1: Implement the page body**

Replace the `BlockSetupPage` stub with the real implementation. Required behavior (mirror existing page styling and `BlockingSettingsView`'s picker presentation at ~L2717):

```swift
private struct BlockSetupPage: View {
    @EnvironmentObject var model: AppModel
    var onStarted: () -> Void

    @State private var selection = FamilyActivitySelection()
    @State private var isShowingPicker = false
    @State private var passcode = ""
    @State private var isStarting = false

    private var selectedCount: Int {
        selection.applicationTokens.count
        + selection.categoryTokens.count
        + selection.webDomainTokens.count
    }
    private var canStart: Bool {
        OnboardingBlock.meetsMinimumSelection(
            appCount: selection.applicationTokens.count,
            categoryCount: selection.categoryTokens.count,
            webCount: selection.webDomainTokens.count)
        && passcode.count >= 4 && !isStarting
    }

    var body: some View {
        VStack(/* match existing page layout */) {
            // Title: "Block your first app"
            // Subtitle: why blocking now matters
            Button("Choose apps to block") { isShowingPicker = true }
            if selectedCount > 0 { Text("\(selectedCount) selected") }
            // Passcode field (4-digit): "Set a passcode so you can't just turn it off"
            SecureField("4-digit passcode", text: $passcode)
                .keyboardType(.numberPad)
            // Inline hint when canStart == false: "Select at least one app and set a passcode"
            Button("Start blocking") { Task { await start() } }
                .disabled(!canStart)
        }
        .sheet(isPresented: $isShowingPicker) {
            NavigationStack {
                FamilyActivityPicker(selection: $selection)
                    .navigationTitle("Blocked Apps")
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isShowingPicker = false }
                    } }
            }
        }
    }

    @MainActor private func start() async {
        isStarting = true
        defer { isStarting = false }
        if !model.hasScreenTimeAuthorization {
            await model.requestScreenTimeAuthorization()
            guard model.hasScreenTimeAuthorization else { return } // model.message shows the error
        }
        guard let data = try? BlockingSelectionCodec.encode(selection) else { return }
        let group = OnboardingBlock.makeFirstBlockGroup(
            id: UUID().uuidString, name: "My First Block", selectionData: data)
        let ok = model.upsertBlockGroup(group, password: passcode)
        if ok { Haptics.success(); onStarted() }   // failure: model.message is shown, stay on page
    }
}
```

> Match the project's actual symbols: existing haptics helper (`Haptics.success()` / `AppHaptics`), the SecureField/passcode styling, and the page's visual layout (reuse the shared layout bits other pages use). Do not introduce a new blocking path — `upsertBlockGroup` is the only entry point.

- [ ] **Step 2: Confirm the gate blocks completion**

Verify there is no way to reach page 7 / `onStarted()` without `upsertBlockGroup` returning `true`. The `.disabled(!canStart)` plus the `if ok` guard enforce this.

- [ ] **Step 3: Build + manual verify (real device for FamilyControls)**

Run: `xcodebuild -scheme ScreenTimeSharing -destination 'generic/platform=iOS' build`
Expected: BUILD SUCCEEDED.
Manual (real device): "Start blocking" is disabled until ≥1 app chosen AND passcode entered; on success it advances to the invite page and the new block appears in Blocking Settings as an active 30‑min/day time‑limit group.

- [ ] **Step 4: Commit**

```bash
git add ScreenTimeSharing/Views/OnboardingView.swift
# message: "Implement onboarding block setup page (real time-limit block, gated)"
```

---

## Task 6: App — Invite page (page 7) + App Store URL config

Implement the final invite step: add a configurable App Store URL, generate an invite, share App Store + invite links, and complete onboarding on share or skip.

**Files:**
- Modify: `ScreenTimeSharing/AppConfiguration.swift`
- Modify: `ScreenTimeSharing/Views/OnboardingView.swift`

**Interfaces:**
- Consumes: `OnboardingInvite.shareMessage(...)` (Task 1); `AppModel.createInvite()` → `CreatedInvite(code, url, expiresAt)`; `AppModel.completeOnboarding()`; `AppConfiguration.appStoreURL`.

- [ ] **Step 1: Add the App Store URL constant**

In `AppConfiguration.swift`, add (match the file's existing constant style):

```swift
/// Public App Store product URL used in onboarding invite shares.
/// TODO(owner): replace with the real product URL once provided.
static let appStoreURL = URL(string: "https://apps.apple.com/app/idREPLACE_ME")!
```

> The owner will supply the real URL. This is a single configurable constant, not scattered literals.

- [ ] **Step 2: Implement the invite page body**

Replace the `InviteFriendsOnboardingPage` stub:

```swift
private struct InviteFriendsOnboardingPage: View {
    @EnvironmentObject var model: AppModel
    var onFinish: () -> Void

    @State private var invite: CreatedInvite?
    @State private var isGenerating = false

    private var shareText: String? {
        guard let invite else { return nil }
        return OnboardingInvite.shareMessage(
            displayName: model.profile.displayName,
            appStoreURL: AppConfiguration.appStoreURL,
            inviteURL: invite.url)
    }

    var body: some View {
        VStack(/* match existing page layout; OnboardingAllSet asset as hero */) {
            // Title: "You're all set — invite a friend"
            // Subtitle: accountability works better with a friend
            if let text = shareText {
                ShareLink(item: text) { Text("Invite a friend") /* primary button style */ }
                    .simultaneousGesture(TapGesture().onEnded { Haptics.success() })
            } else {
                ProgressView() // while generating; on failure show retry below
            }
            if invite == nil && !isGenerating {
                Button("Try again") { Task { await generate() } }
            }
            Button("Maybe later") { onFinish() }   // small, secondary; skip is allowed
        }
        .task { await generate() }
    }

    @MainActor private func generate() async {
        guard invite == nil, !isGenerating else { return }
        isGenerating = true
        defer { isGenerating = false }
        invite = try? await model.createInvite()  // failure: invite stays nil, "Try again" shows
    }
}
```

> Behavior contract: the primary action shares via `ShareLink`; "Maybe later" always completes. `onFinish` is wired (Task 4) to `model.completeOnboarding()`. Invite‑generation failure must NOT block completion — "Maybe later" remains available. Match the actual `CreatedInvite` shape (`url`, `code`, `expiresAt`) and the project's button/haptic styling.

- [ ] **Step 3: Build + manual verify**

Run: `xcodebuild -scheme ScreenTimeSharing -destination 'generic/platform=iOS' build`
Expected: BUILD SUCCEEDED.
Manual: reaching page 7 generates an invite; "Invite a friend" opens the share sheet with a message containing both the App Store URL and `deny://invite/CODE`; both "share" and "Maybe later" finish onboarding (`hasCompletedOnboarding` true → app tabs); offline → "Try again" appears and "Maybe later" still completes.

- [ ] **Step 4: Commit**

```bash
git add ScreenTimeSharing/AppConfiguration.swift ScreenTimeSharing/Views/OnboardingView.swift
# message: "Add onboarding invite share page and configurable App Store URL"
```

---

## Final verification

- [ ] `swift test` — all Core tests pass (66 existing + new `OnboardingActivationTests`).
- [ ] `xcodebuild … build` — app target builds.
- [ ] Manual end‑to‑end on a real device: cannot finish onboarding without authorizing Screen Time AND starting ≥1 block; invite is skippable; the started block is a live 30‑min/day time‑limit group visible in Blocking Settings.

---

## Self-Review (against spec)

- **Spec coverage:** flow restructure §4 → Task 4; block step §5.2 (picker, passcode, timeLimit default, upsertBlockGroup, ≥1 gate) → Tasks 2,3,5; invite step §5.3 (createInvite, App Store + invite link, skip) → Tasks 1,6; App Store URL config §3/§10 → Task 6; completion gate §6 → Tasks 4,5; error handling §7 → Steps in Tasks 5,6; testing §9 (message builder, BlockGroup factory, gate predicate) → Tasks 1,2,3. Universal links §2 explicitly out of scope — no task (correct).
- **Placeholder scan:** the only `TODO` is the App Store URL constant, which is a real owner‑supplied dependency flagged in spec §10 (a configurable value, not missing logic). No "handle edge cases"/"write tests above"‑style gaps; tests carry real code.
- **Type consistency:** `OnboardingInvite.shareMessage`, `OnboardingBlock.meetsMinimumSelection`, `OnboardingBlock.makeFirstBlockGroup` names/signatures match between their defining tasks (1/2/3) and consuming tasks (5/6). `onStarted`/`onFinish` closure names match between Task 4 wiring and Tasks 5/6 bodies.

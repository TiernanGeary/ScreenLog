# Per-Group Pool Usage Measurement (review M1 follow-up)

**Problem.** SP3's shared pool reports `selectedAppSecondsForPoolGroup` from `DeviceActivityScreenTimeProvider.loadTodayUsage(selection:)`, but that provider **ignores the `selection`** and returns a single whole-device snapshot. So the pool's `used_seconds` is total device screen time, not the group's restricted apps → systematic over-blocking for every pool group.

**iOS constraints (from investigation).**
- DeviceActivity usage data is produced **only while a `DeviceActivityReport` SwiftUI view is rendered** (the report extension's scene `makeConfiguration(representing:)` runs against data filtered by the view's `DeviceActivityFilter`).
- `DeviceActivityReport.Context` for a scene is **static** (declared at compile time) — you cannot mint a per-group context at runtime.
- Same context + different filters rendered simultaneously would collide on one storage slot.
- `DeviceActivityFilter.screenLog(segment:selection:)` already exists and correctly filters by a `FamilyActivitySelection` (apps/categories/webDomains) — this is the proven per-selection filter in `ScreenTimeReportBridgeView`.

**Design — fixed N=5 group-usage slots.**
- Define 5 static contexts `screenLogGroupUsage0…4` + 5 scene structs in the report extension, each persisting the filtered total to its own storage slot key.
- The app assigns each active **pool** group (in `myGroups` order) a stable slot index 0–4 for the session; if >5 pool groups, the extras fall back to whole-device usage and are `log()`-ed (documented cap, acceptable — multi-pool-group membership is rare).
- A hidden host view renders one `DeviceActivityReport(.screenLogGroupUsageN, filter: screenLog(selection: group[N].selection))` per assigned slot, so each slot's snapshot stays fresh while the app is foreground (matching the existing foreground-report model).
- `report_group_usage` is fed the slot value for the group instead of the whole-device duration.

## Components

| File | Change |
|---|---|
| `Sources/ScreenTimeSharingCore/ScreenTimeReportStorage.swift` | Add per-slot group-usage keys + `setGroupUsage(slot:groupBlockID:dayKey:seconds:)` / `groupUsage(slot:groupBlockID:dayKey:)` (store seconds keyed by slot + the rendered group block id + owner-day, so a stale slot for a different group/day reads 0). |
| `ScreenLogDeviceActivityReportExtension/ScreenLogUsageReport.swift` | Add `screenLogGroupUsage0…4` contexts + 5 `ScreenLogGroupUsageReportN` scenes; each calls a builder that totals the filtered seconds and writes its slot. |
| `ScreenLogDeviceActivityReportExtension/ScreenLogUsageReportBuilder.swift` | Add `persistGroupUsageSlot(_ slot:Int, representing data:)` that sums `totalActivityDuration` over the filtered apps and writes the slot via storage. |
| `ScreenLogDeviceActivityReportExtension/ScreenLogDeviceActivityReportExtension.swift` | Register the 5 new scenes in `body`. |
| `ScreenTimeSharing/Views/GroupPoolUsageReporters.swift` (**new**) | A hidden SwiftUI view that renders the per-slot `DeviceActivityReport`s for the app's assigned pool groups; embedded in `RootView`. |
| `ScreenTimeSharing/AppModel.swift` | Maintain `poolGroupSlots: [groupID: Int]` (assigned from `myGroups` pool groups, cap 5); expose the per-slot group selections for the host; `selectedAppSecondsForPoolGroup` reads `ScreenTimeReportStorage.groupUsage(slot:groupBlockID:dayKey:)` for the group's slot (fallback to 0 / whole-device if unassigned). |
| `ScreenTimeSharing/Views/RootView.swift` | Embed the hidden `GroupPoolUsageReporters()` host. |

## Slot keying (correctness)

The slot value is stored keyed by `(slot, renderedGroupBlockID, ownerDayKey)`. The reader passes the group's `"group.<id>"` block id + the group's owner-TZ day key; a mismatch (slot currently rendering a different group, or a stale day) reads 0 rather than another group's number. This prevents cross-group contamination if slot assignment shifts.

## Verification

- `swift test` + `xcodebuild` (compile only — **the DeviceActivity pipeline is device-only; this cannot be functionally verified in CI/simulator**).
- **Device E2E required:** two members in a pool group, each using only some of the group's apps; confirm the pool `used` reflects the group's apps (not other apps), exhausts at `pool_seconds` of the group's apps, and re-shields. This is the gate this design's correctness ultimately rests on.

## Accepted limitations
- ≤5 concurrent pool groups measured precisely; beyond that, whole-device fallback (logged).
- Freshness is bounded by foreground render + the existing publish throttle (best-effort, as the whole pool is).

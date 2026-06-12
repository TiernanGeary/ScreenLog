# Phase 2a: home/stats ロード性能（#3）実装計画

> **For agentic workers:** Codex が実装（CLAUDE.md: Claude が計画・検証、Codex が実装）。各タスクは exact なファイル/前後コードで記述。**Core のメモ化ロジックは `swift test` で自動検証**。アプリ層（ポーリング/デコード/配線）はこの環境に Xcode が無いため**コードレビュー＋Xcode ビルド（ユーザー側）**で検証。進捗はチェックボックスで管理。

**Goal:** 「home/stats が毎回フルロードする」体感を解消する — (1) 純ビルダー（summary/chartBuckets/appUsageRows）を履歴シグネチャでメモ化、(2) スクリーンタイムレポートのポーリングをデータ到着後に早期終了、(3) 共有ストレージのバイト同一データに対する JSON デコードをスキップ。

**Architecture:** ロジックを `ScreenTimeSharingCore` に寄せて単体テスト可能にする（`UsageHistorySignature` ＋ `UsageStatsCache`）。アプリ層（`AppModel` がキャッシュを保持し `StatsView` が参照、3本のポーリングループの早期終了、`loadUsageHistory` のデコードスキップ）は薄い配線に留める。新規型は Core に2つ、アプリの新規フィールドは2つのみ。

**Tech Stack:** Swift / SwiftUI / swift-testing / `ScreenTimeSharingCore`(SPM)。

**Base branch:** `feature/phase2-perf-and-onboarding`（Phase 1 の上に積んだ Phase 2 ブランチ。すでにこのブランチ上にいる）
**確定済み方針（spec §5.1）:** stale-while-revalidate を採用（= 既知データを即表示し裏で静かに更新）。本計画はその「静かに更新」を**安価**にする中核を実装する。
**関連spec:** `docs/specs/2026-06-05-improvement-breakdown.md`（§D）

---

## スコープと「今回見送り」

spec §D-4 は8項目。本計画は**高価値・低リスク・できるだけ Core で検証可能**な3本に絞る:

| 採用 | 項目 | 検証 |
|---|---|---|
| ✅ | ビルダーのメモ化（インメモリ、履歴シグネチャ鍵） | **Core / swift test** |
| ✅ | ポーリング早期終了（既存 `didChange` を活用、データ安定後に停止） | コードレビュー |
| ✅ | デコードスキップ（バイト同一なら decode と @Published 再代入を回避） | コードレビュー |

**今回見送り（理由付き・後続フェーズ候補）:**
- **report-identity 移行（Home/Today を安定IDへ）**: Stats は既に安定ID化済み。Home/Today も同様にできるが、DeviceActivityReport の再生成タイミングを変えるため**実機検証必須**でこの環境では確認不可。上記3本でデコード負荷が激減するため優先度低。
- **date-change debounce**: デコードスキップにより日付スクラブ中の `reloadUsageHistoryFromSharedStorage` がほぼ無償化されるため限界効用が小さい。
- **stale バッジ UI**: 既存データは既に即時表示される（`localSnapshot`）。バッジ追加は純UX増分で、アプリ層のみ＝検証不可。
- **App Group 永続（デコード済み）キャッシュ（L）**: 既に App Group 生データ永続はある。デコード済み結果の永続化は別レイヤで、効果に対し複雑。
- **バックグラウンドデコード**: `AppModel` が `@MainActor` のためアクター跨ぎが必要。デコードスキップで毎秒デコードが消えるため、まずはそちらで十分。

---

## ファイル変更マップ

| ファイル | 役割 | 変更（タスク） |
|---|---|---|
| `Sources/ScreenTimeSharingCore/UsageStatsCache.swift` | **新規** | `UsageHistorySignature` ＋ `UsageStatsCache`（T1/T2） |
| `Tests/ScreenTimeSharingCoreTests/UsageStatsCacheTests.swift` | **新規** | 上記のテスト（T1/T2） |
| `ScreenTimeSharing/AppModel.swift` | 中央状態 | `usageStatsCache` 保持 / `loadUsageHistory` デコードスキップ＋`lastLoadedUsageData`（T3/T5） |
| `ScreenTimeSharing/Views/StatsView.swift` | Stats 画面 | 3 ビルダー呼び出しをキャッシュ経由に（T3） |
| `ScreenTimeSharing/Views/ScreenTimeReportBridgeView.swift` | レポート橋渡し | 3 本のポーリングループに早期終了（T4） |

---

## Task 1: Core — `UsageHistorySignature`（TDD）

履歴の安価な変更検知シグネチャを Core に新設（既存のアプリ内 private `UsageHistorySignature` のロジックを Core へ昇格し、Hashable 化してメモ鍵に使う）。

**Files:**
- Create: `Sources/ScreenTimeSharingCore/UsageStatsCache.swift`
- Create: `Tests/ScreenTimeSharingCoreTests/UsageStatsCacheTests.swift`

- [ ] **Step 1: 失敗するテストを書く**

`Tests/ScreenTimeSharingCoreTests/UsageStatsCacheTests.swift`:

```swift
import Foundation
import Testing
@testable import ScreenTimeSharingCore

private func makeSnapshot(
    id: String,
    date: Date,
    total: TimeInterval,
    lastUpdated: Date
) -> DailyUsageSnapshot {
    DailyUsageSnapshot(
        id: id,
        ownerProfileID: "me",
        date: date,
        calendarIdentifier: "gregorian",
        timeZoneIdentifier: "UTC",
        totalDuration: total,
        selectedAppDuration: nil,
        pickupCount: nil,
        appRows: [],
        lastUpdated: lastUpdated,
        capability: .fullAppDetail
    )
}

@Test func usageHistorySignatureChangesWithContentAndIsStableForEqualInput() {
    let day = Date(timeIntervalSince1970: 1_779_236_400)
    let a = makeSnapshot(id: "d1", date: day, total: 3_600, lastUpdated: day)
    let sigA = UsageHistorySignature(history: [a], hourlyDurationsByDayID: ["d1": [3_600]])
    let sigA2 = UsageHistorySignature(history: [a], hourlyDurationsByDayID: ["d1": [3_600]])
    #expect(sigA == sigA2)

    let b = makeSnapshot(id: "d1", date: day, total: 7_200, lastUpdated: day.addingTimeInterval(60))
    let sigB = UsageHistorySignature(history: [b], hourlyDurationsByDayID: ["d1": [7_200]])
    #expect(sigA != sigB)
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `swift test --filter usageHistorySignatureChangesWithContentAndIsStableForEqualInput`
Expected: コンパイルエラー（`UsageHistorySignature` 未定義）。

> 確認済み: `DailyUsageSnapshot` の init 引数順は `Models.swift` 実体に一致。`capability` は `ScreenTimeCapability` の静的メンバ `.fullAppDetail`（既存テスト `HomeEngagementBuilderTests.swift:294` と同じ用法）。

- [ ] **Step 3: `UsageHistorySignature` を実装**

`Sources/ScreenTimeSharingCore/UsageStatsCache.swift`（新規ファイル冒頭）:

```swift
import Foundation

/// Cheap, value-type change detector for usage history + hourly map.
/// Used as a memoization key and a stale-detection signal.
public struct UsageHistorySignature: Hashable, Sendable {
    public let snapshotCount: Int
    public let latestSnapshotUpdate: Date?
    public let totalDuration: TimeInterval
    public let hourlyDayCount: Int
    public let hourlyDuration: TimeInterval

    public init(
        history: [DailyUsageSnapshot],
        hourlyDurationsByDayID: [String: [TimeInterval]]
    ) {
        snapshotCount = history.count
        latestSnapshotUpdate = history.map(\.lastUpdated).max()
        totalDuration = history.reduce(TimeInterval(0)) { partial, snapshot in
            partial + max(0, snapshot.totalDuration ?? 0)
        }
        hourlyDayCount = hourlyDurationsByDayID.count
        hourlyDuration = hourlyDurationsByDayID.values.reduce(TimeInterval(0)) { partial, values in
            partial + values.reduce(TimeInterval(0)) { $0 + max(0, $1) }
        }
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift test --filter usageHistorySignatureChangesWithContentAndIsStableForEqualInput`
Expected: PASS。

---

## Task 2: Core — `UsageStatsCache`（TDD）

3 ビルダーを (range, period-start, 履歴シグネチャ[, summary は now の日]) でメモ化。ヒット/ミスを `computeCount` で検証可能にする。

**Files:**
- Modify: `Sources/ScreenTimeSharingCore/UsageStatsCache.swift`
- Modify: `Tests/ScreenTimeSharingCoreTests/UsageStatsCacheTests.swift`

- [ ] **Step 1: 失敗するテストを追加**

`UsageStatsCacheTests.swift` に追記:

```swift
@Test func usageStatsCacheMemoizesUntilInputsChange() {
    let cal = Calendar(identifier: .gregorian)
    let now = Date(timeIntervalSince1970: 1_779_236_400)
    let snap = makeSnapshot(id: "d1", date: now, total: 3_600, lastUpdated: now)
    let history = [snap]
    let hourly: [String: [TimeInterval]] = ["d1": [3_600]]
    let cache = UsageStatsCache()

    let r1 = cache.appUsageRows(range: .day, selectedDate: now, history: history, calendar: cal)
    let r2 = cache.appUsageRows(range: .day, selectedDate: now, history: history, calendar: cal)
    // Same inputs -> single computation (cache hit on 2nd call), equal result.
    #expect(r1 == r2)
    #expect(cache.appRowsComputeCount == 1)

    // Correctness: equals a direct builder call.
    let direct = UsageStatsBuilder.appUsageRows(range: .day, selectedDate: now, history: history, calendar: cal)
    #expect(r1 == direct)

    // Changed history -> recompute (miss).
    let snap2 = makeSnapshot(id: "d1", date: now, total: 7_200, lastUpdated: now.addingTimeInterval(60))
    _ = cache.appUsageRows(range: .day, selectedDate: now, history: [snap2], calendar: cal)
    #expect(cache.appRowsComputeCount == 2)
}

@Test func usageStatsCacheReusesAcrossDatesInSamePeriod() {
    let cal = Calendar(identifier: .gregorian)
    let monday = Date(timeIntervalSince1970: 1_779_236_400)
    let snap = makeSnapshot(id: "d1", date: monday, total: 3_600, lastUpdated: monday)
    let cache = UsageStatsCache()

    _ = cache.chartBuckets(range: .week, selectedDate: monday, history: [snap], hourlyDurationsByDayID: [:], calendar: cal)
    // A different date in the SAME week normalizes to the same period-start key -> cache hit.
    let nextDay = monday.addingTimeInterval(24 * 3_600)
    _ = cache.chartBuckets(range: .week, selectedDate: nextDay, history: [snap], hourlyDurationsByDayID: [:], calendar: cal)
    #expect(cache.bucketsComputeCount == 1)
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `swift test --filter usageStatsCache`
Expected: コンパイルエラー（`UsageStatsCache` 未定義）。

- [ ] **Step 3: `UsageStatsCache` を実装**

`Sources/ScreenTimeSharingCore/UsageStatsCache.swift` に追記（`UsageHistorySignature` の下）:

```swift
/// In-memory memoization for the three pure usage-stats builders.
/// Recomputes only when (range, period start, history signature[, today]) changes.
/// Reference type so a single instance can be shared (e.g. held by AppModel).
public final class UsageStatsCache {
    public init() {}

    public private(set) var summaryComputeCount = 0
    public private(set) var bucketsComputeCount = 0
    public private(set) var appRowsComputeCount = 0

    private struct SummaryKey: Equatable {
        let range: StatsRange
        let periodStart: Date
        let signature: UsageHistorySignature
        let today: Date
    }

    private struct BucketsKey: Equatable {
        let range: StatsRange
        let periodStart: Date
        let signature: UsageHistorySignature
    }

    private struct RowsKey: Equatable {
        let range: StatsRange
        let periodStart: Date
        let signature: UsageHistorySignature
    }

    private var summaryKey: SummaryKey?
    private var summaryValue: UsageStatsSummary?
    private var bucketsKey: BucketsKey?
    private var bucketsValue: [UsageChartBucket]?
    private var rowsKey: RowsKey?
    private var rowsValue: [SharedAppUsage]?

    public func summary(
        range: StatsRange,
        selectedDate: Date,
        history: [DailyUsageSnapshot],
        hourlyDurationsByDayID: [String: [TimeInterval]] = [:],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> UsageStatsSummary {
        let key = SummaryKey(
            range: range,
            periodStart: UsageStatsBuilder.periodInterval(for: range, containing: selectedDate, calendar: calendar).start,
            signature: UsageHistorySignature(history: history, hourlyDurationsByDayID: hourlyDurationsByDayID),
            today: calendar.startOfDay(for: now)
        )
        if key == summaryKey, let summaryValue {
            return summaryValue
        }
        let value = UsageStatsBuilder.summary(
            range: range,
            selectedDate: selectedDate,
            history: history,
            calendar: calendar,
            now: now
        )
        summaryKey = key
        summaryValue = value
        summaryComputeCount += 1
        return value
    }

    public func chartBuckets(
        range: StatsRange,
        selectedDate: Date,
        history: [DailyUsageSnapshot],
        hourlyDurationsByDayID: [String: [TimeInterval]] = [:],
        calendar: Calendar = .current
    ) -> [UsageChartBucket] {
        let key = BucketsKey(
            range: range,
            periodStart: UsageStatsBuilder.periodInterval(for: range, containing: selectedDate, calendar: calendar).start,
            signature: UsageHistorySignature(history: history, hourlyDurationsByDayID: hourlyDurationsByDayID)
        )
        if key == bucketsKey, let bucketsValue {
            return bucketsValue
        }
        let value = UsageStatsBuilder.chartBuckets(
            range: range,
            selectedDate: selectedDate,
            history: history,
            hourlyDurationsByDayID: hourlyDurationsByDayID,
            calendar: calendar
        )
        bucketsKey = key
        bucketsValue = value
        bucketsComputeCount += 1
        return value
    }

    public func appUsageRows(
        range: StatsRange,
        selectedDate: Date,
        history: [DailyUsageSnapshot],
        calendar: Calendar = .current
    ) -> [SharedAppUsage] {
        let key = RowsKey(
            range: range,
            periodStart: UsageStatsBuilder.periodInterval(for: range, containing: selectedDate, calendar: calendar).start,
            signature: UsageHistorySignature(history: history, hourlyDurationsByDayID: [:])
        )
        if key == rowsKey, let rowsValue {
            return rowsValue
        }
        let value = UsageStatsBuilder.appUsageRows(
            range: range,
            selectedDate: selectedDate,
            history: history,
            calendar: calendar
        )
        rowsKey = key
        rowsValue = value
        appRowsComputeCount += 1
        return value
    }
}
```

> 確認: `UsageStatsBuilder.periodInterval(for:containing:calendar:)` は public（`Models.swift:1084-1098`）。非 public の場合は本タスクで `public` 化する（純関数のみ、副作用なし）。

- [ ] **Step 4: テストが通ることを確認**

Run: `swift test --filter usageStatsCache`
Expected: 3 テスト PASS。

- [ ] **Step 5: 全コアテストの回帰確認 ＋ コミット**

Run: `swift test`
Expected: 全 PASS。

```bash
git add Sources/ScreenTimeSharingCore/UsageStatsCache.swift Tests/ScreenTimeSharingCoreTests/UsageStatsCacheTests.swift
git commit -m "Add tested usage-stats memoization cache to core (Phase 2a)

Builders (summary/chartBuckets/appUsageRows) are pure but StatsView recomputes
them on every render. Add a Core UsageHistorySignature + UsageStatsCache that
recompute only when (range, period, history) changes, with computeCount-backed
tests so the hit/miss behavior is verified by swift test.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: アプリ配線 — `StatsView` をキャッシュ経由に

**Files:**
- Modify: `ScreenTimeSharing/AppModel.swift`（キャッシュ保持）
- Modify: `ScreenTimeSharing/Views/StatsView.swift`（3 computed をキャッシュ呼び出しに）

- [ ] **Step 1: AppModel にキャッシュを保持**

変更前（`@Published` 群の末尾、`Models.swift` の usage 状態付近 L235-245）:

```swift
    @Published var screenTimeReportStatus = "Waiting for Screen Time setup."
    @Published var screenTimeReportLastGeneratedAt: Date?
```

変更後（直後に非 @Published の共有キャッシュを追加）:

```swift
    @Published var screenTimeReportStatus = "Waiting for Screen Time setup."
    @Published var screenTimeReportLastGeneratedAt: Date?

    let usageStatsCache = UsageStatsCache()
```

> `let` ＋デフォルト初期化なので `init` 変更不要。`@Published` ではない（メモ化は副作用的キャッシュで、観測対象にすると再描画ループになるため）。

- [ ] **Step 2: StatsView の 3 computed をキャッシュ呼び出しに置換**

変更前（`StatsView.swift:13-56`）:

```swift
    private var summary: UsageStatsSummary {
        UsageStatsBuilder.summary(
            range: selectedRange,
            selectedDate: selectedDate,
            history: statsHistory
        )
    }

    private var chartBuckets: [UsageChartBucket] {
        UsageStatsBuilder.chartBuckets(
            range: selectedRange,
            selectedDate: selectedDate,
            history: statsHistory,
            hourlyDurationsByDayID: model.hourlyUsageByDayID
        )
    }

    private var appUsageRows: [SharedAppUsage] {
        UsageStatsBuilder.appUsageRows(
            range: selectedRange,
            selectedDate: selectedDate,
            history: statsHistory
        )
    }
```

変更後（`UsageStatsBuilder` → `model.usageStatsCache`。引数はそのまま。chartBuckets は hourly を渡すので summary の鍵にも反映させるため hourly を渡す）:

```swift
    private var summary: UsageStatsSummary {
        model.usageStatsCache.summary(
            range: selectedRange,
            selectedDate: selectedDate,
            history: statsHistory,
            hourlyDurationsByDayID: model.hourlyUsageByDayID
        )
    }

    private var chartBuckets: [UsageChartBucket] {
        model.usageStatsCache.chartBuckets(
            range: selectedRange,
            selectedDate: selectedDate,
            history: statsHistory,
            hourlyDurationsByDayID: model.hourlyUsageByDayID
        )
    }

    private var appUsageRows: [SharedAppUsage] {
        model.usageStatsCache.appUsageRows(
            range: selectedRange,
            selectedDate: selectedDate,
            history: statsHistory
        )
    }
```

- [ ] **Step 3: 残参照確認（StatsView が直接ビルダーを呼んでいないか）**

Run: `git grep -n "UsageStatsBuilder\." -- ScreenTimeSharing/Views/StatsView.swift`
Expected: `statsHistory` 内の `UsageHistoryCodec.upserting` は残る（別物）。`UsageStatsBuilder.summary/chartBuckets/appUsageRows` の直接呼び出しは 0 件。

- [ ] **Step 4: ビルド確認（Xcode）** — ⌘B。型エラーなし。
- [ ] **Step 5: 手動確認** — Stats を開き、期間/日付を切り替えても表示が従来どおり正しい（数値・チャート・アプリ行）。同一期間内の日付往復でガタつきが減る。
- [ ] **Step 6: コミット**

```bash
git add ScreenTimeSharing/AppModel.swift ScreenTimeSharing/Views/StatsView.swift
git commit -m "Serve Stats builders through the memoization cache (Phase 2a)

StatsView recomputed summary/chartBuckets/appUsageRows on every body pass.
Route them through AppModel's shared UsageStatsCache so unchanged inputs reuse
the previous result instead of rebuilding on each render.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: ポーリングの早期終了（`ScreenTimeReportBridgeView`）

3 本のループは固定 60 回（60秒）回り続け、`reloadUsageHistoryFromSharedStorage()` の `didChange` を捨てている。**データが到着し安定したら停止**する（データが来ない場合は従来どおり 60 秒回す＝退行なし）。

**Files:**
- Modify: `ScreenTimeSharing/Views/ScreenTimeReportBridgeView.swift`

- [ ] **Step 1: 隠し橋渡しポーリング（オーバーレイ無し）の早期終了**

変更前（L40-51）:

```swift
    private func pollForReportSnapshot() async {
        for _ in 0..<60 {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }

            _ = model.reloadUsageHistoryFromSharedStorage()
        }

        model.refreshScreenTimeReportStatus()
    }
```

変更後（変化が3秒連続で止まったら停止。データ未到着なら従来どおり最大60秒）:

```swift
    private func pollForReportSnapshot() async {
        var quietTicks = 0
        for _ in 0..<60 {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }

            let didChange = model.reloadUsageHistoryFromSharedStorage()
            if didChange {
                quietTicks = 0
            } else if hasCachedReportData {
                quietTicks += 1
            }
            if quietTicks >= 3 {
                break
            }
        }

        model.refreshScreenTimeReportStatus()
    }
```

> このビューに `hasCachedReportData` が無い場合は、`model.localSnapshot != nil` を停止条件に使う（同ファイルの他ポーラーが使う readiness 述語に合わせる）。実体に合わせて述語名を確認すること。

- [ ] **Step 2: Today レポートのポーリング早期終了**

変更前（L97-115）:

```swift
    private func pollForReportSnapshot(maxLoadingDuration: TimeInterval) async {
        let startedAt = Date()
        isShowingLoading = !hasCachedTodayReport

        for _ in 0..<60 {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }

            _ = model.reloadUsageHistoryFromSharedStorage()
            if hasCachedTodayReport || Date().timeIntervalSince(startedAt) >= maxLoadingDuration {
                isShowingLoading = false
            }
        }

        isShowingLoading = false
        model.refreshScreenTimeReportStatus()
    }
```

変更後:

```swift
    private func pollForReportSnapshot(maxLoadingDuration: TimeInterval) async {
        let startedAt = Date()
        isShowingLoading = !hasCachedTodayReport

        var quietTicks = 0
        for _ in 0..<60 {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }

            let didChange = model.reloadUsageHistoryFromSharedStorage()
            if hasCachedTodayReport || Date().timeIntervalSince(startedAt) >= maxLoadingDuration {
                isShowingLoading = false
            }
            if didChange {
                quietTicks = 0
            } else if hasCachedTodayReport {
                quietTicks += 1
            }
            if quietTicks >= 3 {
                break
            }
        }

        isShowingLoading = false
        model.refreshScreenTimeReportStatus()
    }
```

- [ ] **Step 3: Stats レポートのポーリング早期終了**

変更前（L245-263）:

```swift
    private func pollForReportSnapshot(maxLoadingDuration: TimeInterval) async {
        let startedAt = Date()
        isShowingLoading = !hasCachedReportData

        for _ in 0..<60 {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }

            _ = model.reloadUsageHistoryFromSharedStorage()
            if hasCachedReportData || Date().timeIntervalSince(startedAt) >= maxLoadingDuration {
                isShowingLoading = false
            }
        }

        isShowingLoading = false
        model.refreshScreenTimeReportStatus()
    }
```

変更後:

```swift
    private func pollForReportSnapshot(maxLoadingDuration: TimeInterval) async {
        let startedAt = Date()
        isShowingLoading = !hasCachedReportData

        var quietTicks = 0
        for _ in 0..<60 {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }

            let didChange = model.reloadUsageHistoryFromSharedStorage()
            if hasCachedReportData || Date().timeIntervalSince(startedAt) >= maxLoadingDuration {
                isShowingLoading = false
            }
            if didChange {
                quietTicks = 0
            } else if hasCachedReportData {
                quietTicks += 1
            }
            if quietTicks >= 3 {
                break
            }
        }

        isShowingLoading = false
        model.refreshScreenTimeReportStatus()
    }
```

- [ ] **Step 4: ビルド確認（Xcode）** — ⌘B。型エラーなし。
- [ ] **Step 5: 手動確認** — Home/Stats を開き、スクリーンタイムデータが表示された後、CPU/電池の無駄な毎秒デコードが止まる（データ未取得時は従来どおり読み込みを続ける）。
- [ ] **Step 6: コミット**

```bash
git add ScreenTimeSharing/Views/ScreenTimeReportBridgeView.swift
git commit -m "Stop report polling once Screen Time data settles (Phase 2a)

All three poll loops ran a fixed 60s, decoding shared storage every second and
discarding reloadUsageHistoryFromSharedStorage()'s didChange flag. Break ~3s
after data stops changing; keep polling the full window when no data has arrived
yet, preserving late-write pickup for the empty case.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: デコードスキップ（`AppModel.loadUsageHistory`）

共有ストレージの生データがバイト同一なら、JSON デコードと `@Published` 再代入を回避する（毎秒デコード＋再 publish を止める）。

**Files:**
- Modify: `ScreenTimeSharing/AppModel.swift`

- [ ] **Step 1: 直近生データを保持するフィールドを追加し、`loadUsageHistory` でスキップ**

変更前（`AppModel.swift:1571-1581`）:

```swift
    private func loadUsageHistory() {
        guard let data = usageHistoryDefaults?.data(forKey: UsageHistoryCodec.storageKey),
              let payload = try? UsageHistoryCodec.decode(data) else {
            usageHistory = []
            hourlyUsageByDayID = [:]
            return
        }

        usageHistory = payload.snapshots
        hourlyUsageByDayID = payload.hourlyDurationsByDayID
    }
```

変更後（直前に `lastLoadedUsageData` を宣言し、バイト同一なら早期 return）:

```swift
    private var lastLoadedUsageData: Data?

    private func loadUsageHistory() {
        let data = usageHistoryDefaults?.data(forKey: UsageHistoryCodec.storageKey)

        if data == lastLoadedUsageData {
            return
        }
        lastLoadedUsageData = data

        guard let data, let payload = try? UsageHistoryCodec.decode(data) else {
            usageHistory = []
            hourlyUsageByDayID = [:]
            return
        }

        usageHistory = payload.snapshots
        hourlyUsageByDayID = payload.hourlyDurationsByDayID
    }
```

> 補足: `data == lastLoadedUsageData` は両方 nil のケース（データ無し→無し）も正しくスキップする。初回（lastLoaded=nil, data≠nil）は不一致→デコード。クリア（data=nil, lastLoaded≠nil）は不一致→空に更新。`reloadUsageHistoryFromSharedStorage` の `didChange` 判定（シグネチャ比較）はこのスキップ時に「不変」を返すため、`message`/`writeWidgetCacheSnapshot` の既存セマンティクスを保つ。

- [ ] **Step 2: ビルド確認（Xcode）** — ⌘B。型エラーなし。
- [ ] **Step 3: 手動確認** — Home/Stats でデータ更新が来たときは反映され（生データが変わるため）、変化が無い間は再デコードされない（ポーリング/日付スクラブが軽くなる）。
- [ ] **Step 4: コミット**

```bash
git add ScreenTimeSharing/AppModel.swift
git commit -m "Skip usage-history decode when shared bytes are unchanged (Phase 2a)

loadUsageHistory() re-read App Group UserDefaults and JSON-decoded on every poll
tick and date scrub, then republished identical @Published arrays. Cache the
last raw Data and bail out when it matches, avoiding redundant decode + publish
while preserving change semantics when bytes differ.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task C: 最終確認

- [ ] **Step 1: 差分レビュー**

Run: `git diff feature/phase1-time-request-and-shield --stat`
Expected: `Sources/ScreenTimeSharingCore/UsageStatsCache.swift`（新規）/ `Tests/.../UsageStatsCacheTests.swift`（新規）/ `AppModel.swift` / `StatsView.swift` / `ScreenTimeReportBridgeView.swift`（+ docs）のみ。

- [ ] **Step 2: コアテスト**

Run: `swift test`
Expected: 全 PASS（新規 `UsageStatsCacheTests` 3 件を含む）。

- [ ] **Step 3: 受け入れ基準（spec §D-5 のうち本スコープ分）**

- [ ] 同一データの再表示でビルダー再計算が起きない（メモ化、`swift test` で担保）。
- [ ] レポートが、データ取得後は無駄に毎秒デコードを続けない（早期終了）。
- [ ] バイト同一の共有データに対する再デコードが起きない（デコードスキップ）。
- [ ] フレンドデータは使用量統計と独立（本変更は使用量パスのみで、フレンド側へ影響しない）。
- [ ] 見送り項目（report-identity 移行 / debounce / stale バッジ / 永続キャッシュ）は本計画スコープ外であることを明記済み。

- [ ] **Step 4: ユーザーへ結果提示**（Codex 出力を verbatim 提示、適用可否を確認 — CLAUDE.md）

---

## Self-Review（計画著者による点検）

- **Spec coverage:** §D-4 の「インメモリキャッシュ＋ビルダーメモ化」= T1/T2/T3、「ポーリング早期終了」= T4、加えて「再デコード回避」= T5。残り（永続キャッシュ L / stale-while-revalidate UI / report-identity / debounce / bg-decode）は**スコープ外として明記**。
- **Placeholder scan:** 「適切に〜」等なし。Core は完全コード＋テスト、アプリ層は exact な before/after。
- **型/シンボル整合:** `UsageHistorySignature`（T1）→ `UsageStatsCache`（T2）が同名参照。`UsageStatsCache`（T2）→ AppModel `usageStatsCache`（T3）→ StatsView 呼び出し（T3）が同シグネチャ。`reloadUsageHistoryFromSharedStorage() -> Bool`（既存）の `didChange` を T4 が使用。`lastLoadedUsageData`（T5）は新規 private フィールド。依存する既存純関数: `UsageStatsBuilder.summary/chartBuckets/appUsageRows/periodInterval`、`UsageHistoryCodec.decode`。
- **検証可能性:** T1/T2 は `swift test` で完全検証。T3/T4/T5 はアプリターゲットのため Xcode ビルド＋手動（ユーザー側）。`periodInterval` が非 public の場合は T2 で public 化が必要（純関数）。
- **リスク:** ポーリング早期終了は「データ未到着時は従来どおり 60 秒」を保つ設計で退行を回避。`hasCachedReportData`/`hasCachedTodayReport` の述語名は実体に合わせて確認。メモ化キャッシュは `@Published` にしない（再描画ループ回避）。
- **スコープ:** 単一の実装計画に収まる（新規2＋既存3ファイル）。

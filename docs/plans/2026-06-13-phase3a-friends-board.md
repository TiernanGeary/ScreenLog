# Phase 3a: 統合フレンドリスト＋鮮度インジケータ（#4）実装計画

> **For agentic workers:** Codex が実装（CLAUDE.md: Claude が計画・検証、Codex が実装）。Task 1（Core）は **`swift test` で自動検証**。Task 2/3（アプリ層）はこの環境に Xcode が無いため**差分突合＋ユーザー側 Xcode ビルド**で検証。進捗はチェックボックスで管理。

**Goal:** `FriendsView` の2セクション分裂（リーダーボード／フレンド使用量）を単一の「Friends」セクション＋モード切替（Activity = スクリーンタイム順 / Leaderboard = 申請時間順・現行維持）に統合し、全行に色分き鮮度（緑<5分/黄5-60分/橙>1時間）、ヘッダに「最終同期＋Sync Now」を常設する。

**Architecture:** 純ロジック（Activity 順ソート・鮮度3段階判定）を Core の新ファイル `FriendBoard.swift` に置いて swift-testing で検証。`AppModel` には同期状態2フィールド（`friendsLastSyncedAt` / `isSyncingFriends`）のみ追加し `reloadFriends()` で更新。`FriendsView` はモード切替 UI（既存 `FriendLeaderboardWindowSelector` と同形）と `@AppStorage` 永続化で再構成。

**Tech Stack:** Swift / SwiftUI / swift-testing / `ScreenTimeSharingCore`(SPM)。

**Base branch:** `feature/phase3-friends-and-invites`（Phase 2 の上に積んだ Phase 3 ブランチ。すでにこのブランチ上にいる）
**確定済み方針（spec §5.1-3）:** リーダーボードのランキングは**「申請時間順」を維持**（リフレーミングしない）。
**関連spec:** `docs/specs/2026-06-05-improvement-breakdown.md`（§E）

---

## スコープと「今回見送り」

spec §E-4 は6項目（うち1つは方針確定で対象外）。本計画は3本:

| 採用 | 項目（spec） | タスク |
|---|---|---|
| ✅ | E-4-1 統合フレンドリスト＋モード切替（M） | T2/T3 |
| ✅ | E-4-2 鮮度インジケータ常設（S） | T1/T2/T3 |
| ✅ | E-4-5 のうち**ウィンドウ/モード選択の UserDefaults 永続化のみ** | T3 |

**今回見送り（理由付き・後続候補）:**
- **E-4-4 フレンド詳細View（L）**: 新画面＋履歴/タイムライン集約で Effort L。統合リストが入ってから詳細導線を設計する方が手戻りが少ない。
- **E-4-6 フレンド管理（unfriend/mute/block）**: unfriend は CloudKit 共有ゾーン削除が必要（spec §E-6）で、実機検証不可のこの環境では破壊的操作のリスクが高い。
- **E-4-5 のサーバ側フィルタ/プリフェッチ**: CloudKit 述語変更は実機検証必須。永続化（体感改善の大半）のみ先行。
- **E-4-3**: 方針確定により対象外（申請時間順維持）。

---

## ファイル変更マップ

| ファイル | 役割 | 変更（タスク） |
|---|---|---|
| `Sources/ScreenTimeSharingCore/FriendBoard.swift` | **新規** | `FriendFreshness` ＋ `FriendBoardBuilder.activityRows`（T1） |
| `Tests/ScreenTimeSharingCoreTests/FriendBoardTests.swift` | **新規** | 上記のテスト（T1） |
| `ScreenTimeSharing/AppModel.swift` | 中央状態 | `friendsLastSyncedAt`/`isSyncingFriends` ＋ `reloadFriends` 配線（T2） |
| `ScreenTimeSharing/Views/FriendsView.swift` | Friends 画面 | 統合セクション＋モード切替＋鮮度＋同期ヘッダ（T3） |

---

## Task 1: Core — `FriendFreshness` ＋ `FriendBoardBuilder`（TDD）

**Files:**
- Create: `Sources/ScreenTimeSharingCore/FriendBoard.swift`
- Create: `Tests/ScreenTimeSharingCoreTests/FriendBoardTests.swift`

- [ ] **Step 1: 失敗するテストを書く**

`Tests/ScreenTimeSharingCoreTests/FriendBoardTests.swift`:

```swift
import Foundation
import Testing
@testable import ScreenTimeSharingCore

private func makeSummary(
    id: String,
    name: String,
    total: TimeInterval?,
    lastUpdated: Date? = nil
) -> FriendUsageSummary {
    FriendUsageSummary(
        id: id,
        displayName: name,
        avatarColorHex: "#FFAA00",
        totalDuration: total,
        selectedAppDuration: nil,
        capability: .fullAppDetail,
        lastUpdated: lastUpdated,
        isStale: false
    )
}

@Test func friendFreshnessTierMapsElapsedTimeToSpecBuckets() {
    let now = Date(timeIntervalSince1970: 1_780_000_000)
    #expect(FriendFreshness.tier(lastUpdated: nil, now: now) == .missing)
    #expect(FriendFreshness.tier(lastUpdated: now.addingTimeInterval(-60), now: now) == .fresh)
    #expect(FriendFreshness.tier(lastUpdated: now.addingTimeInterval(-10 * 60), now: now) == .aging)
    #expect(FriendFreshness.tier(lastUpdated: now.addingTimeInterval(-2 * 3_600), now: now) == .stale)
}

@Test func activityRowsSortByUsageThenNameWithMissingDataLast() {
    let rows = FriendBoardBuilder.activityRows([
        makeSummary(id: "c", name: "Cara", total: nil),
        makeSummary(id: "a", name: "Avery", total: 3_600),
        makeSummary(id: "b", name: "Blake", total: 7_200),
        makeSummary(id: "d", name: "Drew", total: 3_600)
    ])
    #expect(rows.map(\.id) == ["b", "a", "d", "c"])
}
```

> 確認済み: `FriendUsageSummary` の init 引数順は `WidgetCache.swift:14-34` の実体に一致（`avatarImageData` はデフォルト nil なので省略可）。`.fullAppDetail` は `ScreenTimeCapability` の静的メンバ（`CapabilityStatus.swift:18`）。

- [ ] **Step 2: テストが失敗することを確認**

Run: `swift test --filter friendFreshness`
Expected: コンパイルエラー（`FriendFreshness` 未定義）。

- [ ] **Step 3: 実装**

`Sources/ScreenTimeSharingCore/FriendBoard.swift`（新規）:

```swift
import Foundation

/// Freshness tier for a friend's shared data, keyed off the snapshot's
/// lastUpdated timestamp. Thresholds follow the spec: green < 5 min,
/// yellow 5-60 min, orange beyond an hour.
public enum FriendFreshness: Equatable, Sendable {
    case fresh
    case aging
    case stale
    case missing

    public static func tier(lastUpdated: Date?, now: Date = Date()) -> FriendFreshness {
        guard let lastUpdated else {
            return .missing
        }

        let elapsed = now.timeIntervalSince(lastUpdated)
        if elapsed < 5 * 60 {
            return .fresh
        }
        if elapsed < 60 * 60 {
            return .aging
        }
        return .stale
    }
}

/// Pure ordering for the unified friends list's Activity mode:
/// highest screen time first, friends without data last, stable name order.
public enum FriendBoardBuilder {
    public static func activityRows(_ summaries: [FriendUsageSummary]) -> [FriendUsageSummary] {
        summaries.sorted { lhs, rhs in
            switch (lhs.totalDuration, rhs.totalDuration) {
            case let (left?, right?) where left != right:
                return left > right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                break
            }

            let nameOrder = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }

            return lhs.id < rhs.id
        }
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift test --filter "friendFreshness|activityRows"`
Expected: 2 テスト PASS。

- [ ] **Step 5: 全コアテストの回帰確認 ＋ コミット（Claude が実行）**

Run: `swift test`
Expected: 68件 PASS（66 + 新規2）。

```bash
git add Sources/ScreenTimeSharingCore/FriendBoard.swift Tests/ScreenTimeSharingCoreTests/FriendBoardTests.swift
git commit -m "Add tested friend-board ordering and freshness tiers to core (Phase 3a)

The unified friends list needs activity ordering (screen time desc, missing
data last) and the spec's three freshness buckets (green <5m, yellow 5-60m,
orange >1h). Keep both as pure core functions so swift test verifies them.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 2: `AppModel` — 同期状態の公開

**Files:**
- Modify: `ScreenTimeSharing/AppModel.swift`

- [ ] **Step 1: @Published フィールドを追加**

変更前（L238 付近）:

```swift
    @Published var friendSummaries: [FriendUsageSummary] = []
    @Published var leaderboardEntries: [LeaderboardEntry] = []
```

変更後:

```swift
    @Published var friendSummaries: [FriendUsageSummary] = []
    @Published var friendsLastSyncedAt: Date?
    @Published var isSyncingFriends = false
    @Published var leaderboardEntries: [LeaderboardEntry] = []
```

- [ ] **Step 2: `reloadFriends()` で同期状態を更新**

変更前（L1215-1220 付近）:

```swift
    func reloadFriends() async {
        do {
            let previousFriendIDs = Set(friendSummaries.map(\.id))
            let hadLoadedFriends = hasLoadedFriendsOnce
            let friends = try await snapshotStore.fetchFriendSummaries(for: profile)
            friendSummaries = friends
```

変更後（開始/終了マーカー＋成功時刻）:

```swift
    func reloadFriends() async {
        isSyncingFriends = true
        defer { isSyncingFriends = false }

        do {
            let previousFriendIDs = Set(friendSummaries.map(\.id))
            let hadLoadedFriends = hasLoadedFriendsOnce
            let friends = try await snapshotStore.fetchFriendSummaries(for: profile)
            friendSummaries = friends
            friendsLastSyncedAt = Date()
```

> `friendsLastSyncedAt` は成功パスのみ更新（失敗時は古い時刻が残り「最後に成功した同期」を正しく表す）。

- [ ] **Step 3: コミット（Claude が実行）**

```bash
git add ScreenTimeSharing/AppModel.swift
git commit -m "Track friends sync state on AppModel (Phase 3a)

The Friends screen needs 'last synced' and an in-flight indicator for its
header. Record the last successful fetchFriendSummaries time and expose an
isSyncingFriends flag around reloadFriends().

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 3: `FriendsView` — 統合セクション＋モード切替＋鮮度

**Files:**
- Modify: `ScreenTimeSharing/Views/FriendsView.swift`

- [ ] **Step 1: `FriendsView` 本体を統合構成に置換**

変更前（L6-84 の `FriendsView` 全体）:

```swift
struct FriendsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedLeaderboardWindow: LeaderboardWindow = .week
    @State private var isShowingShareSheet = false

    private var leaderboardEntries: [LeaderboardEntry] {
        let friendEntries = model.leaderboardEntries.filter { $0.userID != model.profile.id }
        return StatsBoardBuilder.mostExtraRequested(entries: friendEntries)
    }

    var body: some View {
        NavigationStack {
            AppScreenScroll {
                AppSection("Leaderboard") {
                    VStack(alignment: .leading, spacing: 10) {
                        FriendLeaderboardWindowSelector(selection: $selectedLeaderboardWindow)

                        FriendLeaderboardCard(entries: leaderboardEntries)
                    }
                }

                AppSection("Friend Usage") {
                    if model.friendSummaries.isEmpty {
                        AppCard {
                            ContentUnavailableView(
                                "No Friends Yet",
                                systemImage: "person.2.slash",
                                description: Text("Invite a friend or accept their invite to start sharing requests.")
                            )
                            .appCardRow(verticalPadding: 16)
                        }
                    } else {
                        AppCard {
                            ForEach(Array(model.friendSummaries.enumerated()), id: \.element.id) { index, friend in
                                FriendSummaryRow(friend: friend)
                                    .appCardRow(verticalPadding: 8)

                                if index < model.friendSummaries.count - 1 {
                                    AppCardDivider()
                                }
                            }
                        }
                    }
                }

            }
            .refreshable {
                AppHaptics.selectionChanged()
                await refreshFriends()
            }
            .navigationTitle("Friends")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        AppHaptics.buttonTap()
                        isShowingShareSheet = true
                    } label: {
                        Label("Invite Friends", systemImage: "person.crop.circle.badge.plus")
                    }
                    .accessibilityLabel("Invite Friends")
                }
            }
            .onAppear {
                model.setLeaderboardWindow(selectedLeaderboardWindow)
            }
            .onChange(of: selectedLeaderboardWindow) { _, newWindow in
                model.setLeaderboardWindow(newWindow)
            }
            .sheet(isPresented: $isShowingShareSheet) {
                CloudShareSheet(store: model.snapshotStore, profile: model.profile)
            }
        }
    }

    private func refreshFriends() async {
        await model.reloadFriends()
        await model.syncFriendRequests()
    }
}
```

変更後:

```swift
struct FriendsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("friends.boardMode") private var boardMode: FriendBoardMode = .activity
    @AppStorage("friends.leaderboardWindow") private var selectedLeaderboardWindow: LeaderboardWindow = .week
    @State private var isShowingShareSheet = false

    private var leaderboardEntries: [LeaderboardEntry] {
        let friendEntries = model.leaderboardEntries.filter { $0.userID != model.profile.id }
        return StatsBoardBuilder.mostExtraRequested(entries: friendEntries)
    }

    private var activityRows: [FriendUsageSummary] {
        FriendBoardBuilder.activityRows(model.friendSummaries)
    }

    var body: some View {
        NavigationStack {
            AppScreenScroll {
                AppSection("Friends") {
                    VStack(alignment: .leading, spacing: 10) {
                        syncStatusRow

                        FriendBoardModePicker(selection: $boardMode)

                        if boardMode == .leaderboard {
                            FriendLeaderboardWindowSelector(selection: $selectedLeaderboardWindow)

                            FriendLeaderboardCard(entries: leaderboardEntries)
                        } else {
                            activityCard
                        }
                    }
                }
            }
            .refreshable {
                AppHaptics.selectionChanged()
                await refreshFriends()
            }
            .navigationTitle("Friends")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        AppHaptics.buttonTap()
                        isShowingShareSheet = true
                    } label: {
                        Label("Invite Friends", systemImage: "person.crop.circle.badge.plus")
                    }
                    .accessibilityLabel("Invite Friends")
                }
            }
            .onAppear {
                model.setLeaderboardWindow(selectedLeaderboardWindow)
            }
            .onChange(of: selectedLeaderboardWindow) { _, newWindow in
                model.setLeaderboardWindow(newWindow)
            }
            .sheet(isPresented: $isShowingShareSheet) {
                CloudShareSheet(store: model.snapshotStore, profile: model.profile)
            }
        }
    }

    private var syncStatusRow: some View {
        HStack(spacing: 8) {
            Text(UsageFormatting.lastUpdated(model.friendsLastSyncedAt))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button {
                AppHaptics.buttonTap()
                Task { await refreshFriends() }
            } label: {
                if model.isSyncingFriends {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Sync Now", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.isSyncingFriends)
            .accessibilityLabel("Sync friends now")
        }
    }

    private var activityCard: some View {
        AppCard {
            if activityRows.isEmpty {
                ContentUnavailableView(
                    "No Friends Yet",
                    systemImage: "person.2.slash",
                    description: Text("Invite a friend or accept their invite to start sharing requests.")
                )
                .appCardRow(verticalPadding: 16)
            } else {
                ForEach(Array(activityRows.enumerated()), id: \.element.id) { index, friend in
                    FriendSummaryRow(friend: friend)
                        .appCardRow(verticalPadding: 8)

                    if index < activityRows.count - 1 {
                        AppCardDivider()
                    }
                }
            }
        }
    }

    private func refreshFriends() async {
        await model.reloadFriends()
        await model.syncFriendRequests()
    }
}

private enum FriendBoardMode: String, CaseIterable {
    case activity
    case leaderboard

    var label: String {
        switch self {
        case .activity:
            return "Activity"
        case .leaderboard:
            return "Leaderboard"
        }
    }
}

private struct FriendBoardModePicker: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: FriendBoardMode
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(FriendBoardMode.allCases, id: \.self) { mode in
                Button {
                    if selection != mode {
                        AppHaptics.selectionChanged()
                    }
                    selection = mode
                } label: {
                    Text(mode.label)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .foregroundStyle(selection == mode ? .white : .primary)
                        .background {
                            if selection == mode {
                                Capsule()
                                    .fill(Color.blue)
                                    .matchedGeometryEffect(id: "selected-friend-board-mode", in: namespace)
                                    .shadow(color: Color.blue.opacity(0.18), radius: 7, x: 0, y: 3)
                            }
                        }
                        .appCapsuleButtonHitArea()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            Capsule()
                .fill(backgroundColor)
                .overlay {
                    Capsule()
                        .strokeBorder(borderColor, lineWidth: 0.8)
                }
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.05), radius: 14, x: 0, y: 7)
        }
        .animation(.snappy(duration: 0.22), value: selection)
    }

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.075, green: 0.085, blue: 0.10)
            : Color.white.opacity(0.72)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.045) : Color.white.opacity(0.86)
    }
}

private extension FriendFreshness {
    var indicatorColor: Color {
        switch self {
        case .fresh:
            return .green
        case .aging:
            return .yellow
        case .stale:
            return .orange
        case .missing:
            return Color.secondary
        }
    }
}
```

> `FriendBoardModePicker` は既存 `FriendLeaderboardWindowSelector`（同ファイル）と同形の2択カプセル。`@AppStorage` は `LeaderboardWindow`/`FriendBoardMode` が `String` raw の `RawRepresentable` なのでそのまま使える（E-4-5 の永続化）。

- [ ] **Step 2: `FriendSummaryRow` の Stale バッジを色分き鮮度に置換**

変更前（L311-320）:

```swift
                HStack(alignment: .firstTextBaseline) {
                    Text(friend.displayName)
                        .font(.headline)

                    if friend.isStale {
                        Text("Stale")
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                    }
                }
```

変更後:

```swift
                HStack(alignment: .firstTextBaseline) {
                    Text(friend.displayName)
                        .font(.headline)

                    Spacer(minLength: 8)

                    Text(UsageFormatting.lastUpdated(friend.lastUpdated))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(FriendFreshness.tier(lastUpdated: friend.lastUpdated).indicatorColor)
                }
```

> `FriendUsageSummary.isStale` フィールド自体は残す（Widget が使用）。表示だけ「Updated Xm ago」＋色分けに置換。

- [ ] **Step 3: `FriendLeaderboardRow` に鮮度行を追加**

変更前（L231-235、subtitle の Text）:

```swift
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
```

変更後（`lastUpdated` がある行のみ表示。ローカル導出エントリは nil のため「Never updated」のノイズを避ける）:

```swift
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                if let lastUpdated = entry.lastUpdated {
                    Text(UsageFormatting.lastUpdated(lastUpdated))
                        .font(.caption2)
                        .foregroundStyle(FriendFreshness.tier(lastUpdated: lastUpdated).indicatorColor)
                }
```

- [ ] **Step 4: 検証（残参照と整合）**

Run: `grep -n "AppSection\|boardMode\|FriendBoardBuilder\|FriendFreshness" ScreenTimeSharing/Views/FriendsView.swift`
Expected: `AppSection("Friends")` が1つ（"Leaderboard"/"Friend Usage" は消える）。`FriendBoardBuilder.activityRows` 1箇所、`FriendFreshness.tier` 2箇所＋`indicatorColor` 定義。

- [ ] **Step 5: コミット（Claude が実行）**

```bash
git add ScreenTimeSharing/Views/FriendsView.swift
git commit -m "Unify friends list with mode toggle and always-on freshness (Phase 3a)

FriendsView split friends across two sections (leaderboard by requested time,
usage list by lastUpdated) with stale info only as an orange badge. Merge them
into one Friends section with an Activity/Leaderboard mode toggle (ranking
order unchanged per the decided policy), color-coded 'Updated Xm ago' on every
row, a last-synced header with Sync Now, and persisted mode/window selection.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task C: 最終確認

- [ ] **Step 1: 差分レビュー**

Run: `git diff 8533363 --stat`
Expected: `FriendBoard.swift`（新規）/ `FriendBoardTests.swift`（新規）/ `AppModel.swift` / `FriendsView.swift`（+ docs）のみ。

- [ ] **Step 2: コアテスト**

Run: `swift test`
Expected: 68件 PASS（新規 `FriendBoardTests` 2件を含む）。

- [ ] **Step 3: 受け入れ基準（spec §E-5 のうち本スコープ分）**

- [ ] フレンドが単一の統合ビューでモード切替可能（2セクションのマージ不要）。
- [ ] 全行に鮮度インジケータ（Activity 行は常時、Leaderboard 行はデータがある場合）、ヘッダに最終同期＋Sync Now。
- [ ] ランキングは現行の申請時間順を維持（`StatsBoardBuilder.mostExtraRequested` を変更しない）。
- [ ] モード/ウィンドウ選択が再起動後も保持される（@AppStorage）。
- [ ] 見送り項目（詳細View / 管理 / サーバ側フィルタ）は明記済み。

---

## Self-Review（計画著者による点検）

- **Spec coverage:** E-4-1 = T3、E-4-2 = T1+T3（しきい値は spec の 緑<5分/黄5-60分/橙>1時間 に一致）、E-4-5（永続化）= T3。E-4-4/E-4-6/E-4-3 は理由付き見送り。§5.1-3（申請時間順維持）に整合 — ランキング計算は一切触らない。
- **Placeholder scan:** なし。全ステップ exact before/after または完全コード。
- **型/シンボル整合:** `FriendFreshness`/`FriendBoardBuilder`（T1）→ FriendsView 参照（T3）が同名・同シグネチャ。`friendsLastSyncedAt`/`isSyncingFriends`(T2) → `syncStatusRow`(T3)。既存依存: `UsageFormatting.lastUpdated`（Core, public）、`StatsBoardBuilder.mostExtraRequested`、`AppHaptics`、`appCapsuleButtonHitArea()`（SharedViewBits.swift:242）。`FriendSummaryRow` の使用箇所は FriendsView のみ（Widget は独自 Row）を確認済み。
- **検証可能性:** T1 は `swift test` で完全検証。T2/T3 はアプリ層＝差分突合＋ユーザー側 Xcode。
- **リスク:** (1) `@AppStorage` のキーは新規（既存キーと衝突なし）。(2) Leaderboard 行の鮮度は `lastUpdated != nil` ガードでローカル導出エントリのノイズを回避。(3) `reloadFriends` の `defer` は throw しない関数でも安全（catch 内で return しないため必ず実行）。
- **スコープ:** Codex には T1 / T2+T3 の2回に分けて委譲（約2タスク/回の停止傾向に対応）。

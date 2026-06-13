# 全ボタン・全アクション 触覚フィードバック（ドーパミン機能）実装計画

> **For agentic workers:** Codex が実装（CLAUDE.md: Claude が計画・検証、Codex が実装）。**この環境にはフル Xcode (26.5) があり、各チャンク後に `xcodebuild` でビルド検証する**。**シミュレータには Taptic Engine が無く触覚は体感不可** — ビルド成功＋配線レビューで担保し、実際の振動確認はユーザー側実機。進捗はチェックボックスで管理。

**Goal:** アプリの全ボタン・全アクションに触覚フィードバックを付与し、操作の意味ごとに使い分ける（タップ＝軽い衝撃、選択＝selection、承認/送信成功＝success、削除/取消＝warning）。新規ボタンも自動で振動する仕組みにする。

**Architecture:** (1) `AppHaptics` を意味別 API に拡張（既存 `buttonTap()`/`selectionChanged()` の104呼び出しは温存）。(2) `HapticButtonStyle`（`.plain` 相当の見た目＋押下で触覚）を新設し `.buttonStyle(.plain)` を `.buttonStyle(.haptic)` に置換、その際に**二重発火を避けるため action 内の手動 `buttonTap()` を除去**。(3) 状態変化（オンボーディングのページ、タブ、Picker、Toggle、Slider）は iOS17 `.sensoryFeedback` で宣言的に。(4) 非同期の意味的イベント（承認/送信/招待作成=success、取消/削除=warning）に semantic 触覚。

**Tech Stack:** SwiftUI / UIKit feedback generators / iOS 17 `.sensoryFeedback` / `ScreenTimeSharing` アプリターゲット。

**Base branch:** `feature/phase3-friends-and-invites`（現在のブランチ）
**ビルド検証コマンド:**
```
xcodebuild build -project ScreenTimeSharing.xcodeproj -scheme ScreenTimeSharing \
  -destination 'id=09F71C08-6927-440A-A958-7054381D9133' -configuration Debug CODE_SIGNING_ALLOWED=NO
```

---

## 二重発火の方針（最重要）

- `HapticButtonStyle` は押下時に触覚を1回発火する。
- よって `.plain` → `.haptic` に置換したボタンの **action 内に残る `AppHaptics.buttonTap()` / `Haptics.tap()` は必ず削除**する（残すと2回鳴る）。
- action 内が `AppHaptics.selectionChanged()` だったボタンは `.buttonStyle(.haptic(.selection))` にし、手動呼び出しを削除。
- `.bordered` / `.borderedProminent`（システム装飾、計9箇所）は `HapticButtonStyle` に置換せず**システムスタイルのまま**、action 内の既存触覚を意味に合わせて残す/付与（これらは主役 CTA で既に大半が振動済み）。
- 状態変化に付ける `.sensoryFeedback` はボタン押下とは別物なので二重発火しない。

---

## ファイル変更マップ

| ファイル | 変更 |
|---|---|
| `ScreenTimeSharing/Views/SharedViewBits.swift` | `AppHaptics` 拡張 ＋ `HapticStyle` ＋ `HapticButtonStyle`（T1） |
| `ScreenTimeSharing/Views/OnboardingView.swift` | ページ変化に sensoryFeedback / `.plain`→`.haptic`（T2,T3） |
| `ScreenTimeSharing/Views/RootView.swift` | タブ選択に sensoryFeedback / `.plain`→`.haptic`（T2,T3） |
| `ScreenTimeSharing/Views/DashboardView.swift` 他 Views | Picker/Toggle/Slider に sensoryFeedback / `.plain`→`.haptic` / 手動除去（T2,T3） |
| 各承認・送信・招待フロー | semantic success/warning（T4） |

---

## Task 1: 触覚インフラ（`SharedViewBits.swift`）

**Files:** Modify `ScreenTimeSharing/Views/SharedViewBits.swift`

- [ ] **Step 1: `AppHaptics` を意味別 API に拡張**

変更前（L248-271、現状の `AppHaptics`）:

```swift
enum AppHaptics {
    #if canImport(UIKit)
    @MainActor private static let buttonTapGenerator = UIImpactFeedbackGenerator(style: .light)
    @MainActor private static let selectionGenerator = UISelectionFeedbackGenerator()
    #endif

    static func buttonTap() {
        #if canImport(UIKit)
        Task { @MainActor in
            buttonTapGenerator.impactOccurred(intensity: 0.68)
            buttonTapGenerator.prepare()
        }
        #endif
    }

    static func selectionChanged() {
        #if canImport(UIKit)
        Task { @MainActor in
            selectionGenerator.selectionChanged()
            selectionGenerator.prepare()
        }
        #endif
    }
}
```

変更後（既存2メソッドは温存し、意味別メソッドを追加）:

```swift
enum AppHaptics {
    #if canImport(UIKit)
    @MainActor private static let buttonTapGenerator = UIImpactFeedbackGenerator(style: .light)
    @MainActor private static let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    @MainActor private static let selectionGenerator = UISelectionFeedbackGenerator()
    @MainActor private static let notificationGenerator = UINotificationFeedbackGenerator()
    #endif

    /// Light tap for ordinary button presses.
    static func buttonTap() {
        #if canImport(UIKit)
        Task { @MainActor in
            buttonTapGenerator.impactOccurred(intensity: 0.68)
            buttonTapGenerator.prepare()
        }
        #endif
    }

    /// Selection change for toggles, pickers, segmented controls, tab switches.
    static func selectionChanged() {
        #if canImport(UIKit)
        Task { @MainActor in
            selectionGenerator.selectionChanged()
            selectionGenerator.prepare()
        }
        #endif
    }

    /// Soft, low-key feedback for incidental state changes.
    static func soft() {
        #if canImport(UIKit)
        Task { @MainActor in
            softGenerator.impactOccurred(intensity: 0.5)
            softGenerator.prepare()
        }
        #endif
    }

    /// Strong, rewarding success — approvals, sends, invite creation.
    static func success() {
        #if canImport(UIKit)
        Task { @MainActor in
            notificationGenerator.notificationOccurred(.success)
            notificationGenerator.prepare()
        }
        #endif
    }

    /// Warning — cancel, revoke, destructive confirmations.
    static func warning() {
        #if canImport(UIKit)
        Task { @MainActor in
            notificationGenerator.notificationOccurred(.warning)
            notificationGenerator.prepare()
        }
        #endif
    }

    /// Error — failed operations.
    static func error() {
        #if canImport(UIKit)
        Task { @MainActor in
            notificationGenerator.notificationOccurred(.error)
            notificationGenerator.prepare()
        }
        #endif
    }
}
```

- [ ] **Step 2: `HapticStyle` ＋ `HapticButtonStyle` を追加**

`AppHaptics` の閉じ括弧直後（既存 `enum Haptics` の直前）に挿入:

```swift
/// Semantic haptic vocabulary used by HapticButtonStyle and call sites.
enum HapticStyle {
    case tap
    case selection
    case soft
    case success
    case warning

    @MainActor func fire() {
        switch self {
        case .tap: AppHaptics.buttonTap()
        case .selection: AppHaptics.selectionChanged()
        case .soft: AppHaptics.soft()
        case .success: AppHaptics.success()
        case .warning: AppHaptics.warning()
        }
    }
}

/// Plain-looking button style that adds a haptic on press-down, so every button
/// using it buzzes without a manual call. Visually matches `.plain` (renders the
/// label unchanged); the haptic is the only added behavior.
struct HapticButtonStyle: ButtonStyle {
    var haptic: HapticStyle = .tap

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    haptic.fire()
                }
            }
    }
}

extension ButtonStyle where Self == HapticButtonStyle {
    /// Drop-in replacement for `.plain` that also fires a light tap.
    static var haptic: HapticButtonStyle { HapticButtonStyle() }

    /// Variant for buttons whose meaning warrants a different haptic.
    static func haptic(_ style: HapticStyle) -> HapticButtonStyle {
        HapticButtonStyle(haptic: style)
    }
}
```

> `.onChange(of:)` の2引数クロージャは iOS17+。本アプリは既に iOS17 API（`.onChange(of:initial:)` 等）使用のため整合。`configuration.label` のみ返すので `.plain` と同じ見た目（押下時の装飾なし）。

- [ ] **Step 3: ビルド検証**

Run: 上記 `xcodebuild`。Expected: BUILD SUCCEEDED（既存104呼び出しは無改変で温存）。

- [ ] **Step 4: コミット（Claude が実行）**

```bash
git add ScreenTimeSharing/Views/SharedViewBits.swift
git commit -m "Add semantic haptic vocabulary and a haptic button style (dopamine T1)

Expand AppHaptics with soft/success/warning/error alongside the existing tap
and selection, and add a HapticButtonStyle (.haptic) that fires on press so
buttons buzz without a manual call. Infrastructure only; call sites follow.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: 状態変化の触覚（`.sensoryFeedback`）

ボタン押下とは独立した状態変化に宣言的に付与（二重発火しない）。

**Files:** `OnboardingView.swift` / `RootView.swift` / `DashboardView.swift`（および Picker/Toggle/Slider を持つ Views）

- [ ] **Step 1: オンボーディングのページ変化**

`OnboardingView.swift` の TabView（`.tabViewStyle(.page(...))` の直後、`.ignoresSafeArea()` 付近）に追加:

```swift
                .sensoryFeedback(.selection, trigger: currentPage)
```

- [ ] **Step 2: アプリのタブ切替**

`RootView.swift` の `AppTabs.body`、`.animation(.snappy(duration: 0.22), value: selection)` の直後に追加:

```swift
        .sensoryFeedback(.selection, trigger: selection)
```

- [ ] **Step 3: 全 Picker / Toggle / Slider**

各 `Picker(...)` / `Toggle(...)` / `Slider(...)` の呼び出しに、その**選択/値の state を trigger にした** `.sensoryFeedback(.selection, trigger: <boundValue>)` を付ける（Slider は `.selection` でドラッグ中の値変化に追従）。例（minutes Picker）:

```swift
                Picker("Minutes", selection: $minutes) { ... }
                .sensoryFeedback(.selection, trigger: minutes)
```

Toggle 例:

```swift
                Toggle("...", isOn: $flag)
                    .sensoryFeedback(.selection, trigger: flag)
```

> 対象: `git grep -n "Picker(\|Toggle(\|Slider(" -- ScreenTimeSharing/Views` で列挙し、各バインド変数を trigger にする。`.photosPicker` は対象外（ボタン側で扱う）。

- [ ] **Step 4: ビルド検証** → Run 上記 `xcodebuild`、BUILD SUCCEEDED。
- [ ] **Step 5: コミット**

```bash
git add -A
git commit -m "Add selection haptics to pages, tabs, pickers, toggles, sliders (dopamine T2)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: 全ボタンを `.haptic` 化（`.plain`→`.haptic` ＋ 手動除去）

`.buttonStyle(.plain)`（65箇所）を `.buttonStyle(.haptic)` に置換し、**同じボタンの action 内に残る `AppHaptics.buttonTap()` / `Haptics.tap()` を削除**（二重発火回避）。action が `AppHaptics.selectionChanged()` のボタンは `.buttonStyle(.haptic(.selection))` にして手動呼び出しを削除。

**Files:** Views ディレクトリの各ファイル。**1ファイルずつ**実施し、各ファイル後にビルド。

- [ ] **Step 1: ファイル一覧の確定**

Run: `git grep -ln "buttonStyle(.plain)" -- ScreenTimeSharing/Views`

- [ ] **Step 2〜N: 各ファイルで置換＋手動除去**（ファイルごとに）

各ファイルで:
1. `.buttonStyle(.plain)` → `.buttonStyle(.haptic)`（action が selection 意味なら `.haptic(.selection)`）。
2. そのボタンの action 内の `AppHaptics.buttonTap()` / `Haptics.tap()`（selection 化したものは `selectionChanged()`）を削除。
3. ビルド検証（`xcodebuild`、BUILD SUCCEEDED）。
4. コミット（例）:

```bash
git add ScreenTimeSharing/Views/<File>.swift
git commit -m "Route <File> buttons through the haptic button style (dopamine T3)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

> `.bordered`/`.borderedProminent` は据え置き（手動 action 触覚を維持）。`GlassTabButton`（タブ）は T2 の tab sensoryFeedback と二重にならないよう、ボタン自体は `.haptic` にしない（タブ切替の触覚は selection 側で担保）。実体に合わせて確認。

---

## Task 4: 意味的イベント触覚（success / warning）

主要フローの「結果」に報酬的触覚を付与。

**Files:** 該当フローの View / AppModel 呼び出し箇所。

- [ ] **Step 1: success を付与**（各ボタンの action か結果ハンドラ）
  - 時間リクエスト送信成功、フレンド申請の承認、招待リンク作成成功、フレンド招待の受諾成功 → `AppHaptics.success()`。
  - 既に `.haptic(.success)` スタイルで代替できる主役ボタンはスタイル側で対応（二重回避のため action からは外す）。
- [ ] **Step 2: warning を付与**
  - 招待の取消（`PendingInviteRow` の確認後）、申請の拒否（deny）、破壊的確認 → `AppHaptics.warning()`。
- [ ] **Step 3: ビルド検証 ＋ コミット**

```bash
git add -A
git commit -m "Add success/warning haptics to approve, send, invite, cancel flows (dopamine T4)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task C: 最終確認

- [ ] **Step 1: 二重発火スキャン** — `.haptic` 化したボタンの action に手動 `buttonTap`/`tap` が残っていないか:
  Run: `git grep -n "AppHaptics.buttonTap\|Haptics.tap" -- ScreenTimeSharing/Views`（残るのは `.bordered`/`.borderedProminent` と HapticStyle 内部のみ想定）。
- [ ] **Step 2: 全体ビルド** — `xcodebuild` BUILD SUCCEEDED（アプリ＋拡張）。
- [ ] **Step 3: `swift test`** — 68件 PASS（Core 無変更の回帰）。
- [ ] **Step 4: ユーザーへ報告** — 実機での体感確認が必要な旨を明記。

---

## Self-Review

- **網羅性:** ボタン=HapticButtonStyle（`.plain`置換）＋ `.bordered`系は手動、状態変化=sensoryFeedback、イベント=semantic。新規 `.plain`→`.haptic` 運用で将来も自動。
- **二重発火:** スタイル化したボタンの手動呼び出しを必ず除去（Task3/Task C で担保）。sensoryFeedback はボタンと独立。
- **検証可能性:** 全タスク Xcode ビルドで検証可（フル Xcode あり）。触覚の体感のみ実機。Core 無変更で `swift test` は回帰確認。
- **リスク:** `HapticButtonStyle` は `.plain` と同じ見た目（label のみ）なので 65箇所の視覚退行なし。`GlassTabButton` の二重発火に注意（タブは sensoryFeedback 側）。
- **スコープ:** Codex には T1 / T2 / T3（ファイル単位）/ T4 と小分け委譲、各回ビルド。

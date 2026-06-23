# Phase 0: タイムリクエスト・ボタンUX改善 実装計画

> **For agentic workers:** この計画は **Codex が実装**する前提（本リポジトリの `CLAUDE.md`: Claude が計画・検証、Codex が実装）。各タスクは exact なファイル/前後コードで記述。SwiftUI View 層の変更が中心で、この環境にフルXcodeが無いため**検証はXcodeビルド＋手動確認**（`swift test` 対象の純ロジック変更はなし）。チェックボックス（`- [ ]`）で進捗管理する。

**Goal:** 最頻機能であるタイムリクエストの導線を改善する — (1) Home の申請ボタンを「Ask Friends」に改称し主役（塗りつぶし）化、(2) Feed タブの申請作成ボタンを撤去して受信専用化する。

**Architecture:** 既存の `accountability-locks` 枝に対する 2 ファイルの View 改修のみ。新規型・新規ロジックなし。Feed 撤去は「自分の変更が生んだ孤立物」を併せて除去（CLAUDE.md Principle 3）。

**Tech Stack:** Swift / SwiftUI / iOS（FamilyControls 系のアプリ本体ターゲット `ScreenTimeSharing`）。

**Base branch:** `origin/product/accountability-locks`（現行プロダクト。`main` ではない）
**Design decision:** Home ボタン = Option 1「改称＋主役化（インライン維持）」（2026-06-05 ユーザー確定）
**関連spec:** `docs/specs/2026-06-05-improvement-breakdown.md`（§A, §2/#6）

---

## 重要な制約・前提

- **対象は枝 `accountability-locks`。** 作業はこの枝から切ったフィーチャーブランチ上で行う（Task 0）。`main` には適用しない。
- **この環境ではアプリをビルド/実行できない**（CLI Tools のみ、フルXcodeなし）。最終検証は **Xcode でビルド＋シミュレータ/実機の目視**。Codex/実装者がXcode環境で実施する。
- **TDD非適用の理由:** 変更は View の見た目（ラベル/塗り/撤去）のみで新規ロジックがなく、プロジェクトの `swift test` は `ScreenTimeSharingCore`（純ロジック）専用。よって本 Phase は単体テストを追加しない。代わりに**ビルド成功＋手動シナリオ確認**を受け入れ基準とする。
- **サージカル原則:** 指定箇所のみ変更。隣接コードの「改善」や無関係なリファクタは禁止。既存スタイル（`appCapsuleButtonHitArea` 等のヘルパ、`Color.accentColor`）に合わせる。

---

## ファイル変更マップ

| ファイル | 役割 | 変更 |
|---|---|---|
| `ScreenTimeSharing/Views/DashboardView.swift` | Home のブロックグループ行 | `friendRequestButton(for:)` を改称＋主役化。`unblockButton(for:)` を任意で副次化。 |
| `ScreenTimeSharing/Views/BlockingSettingsView.swift` | Feed（`RequestFeedView`） | 申請作成ツールバーボタン＋孤立した dialog/sheet/alert/state/computed を撤去。 |

---

## Task 0: フィーチャーブランチの作成

**Files:** （リポジトリ操作のみ）

- [ ] **Step 1: 最新の枝を取得**

```bash
git fetch origin
```

- [ ] **Step 2: 枝から作業ブランチを作成**

```bash
git switch -c feature/phase0-request-button-ux origin/product/accountability-locks
```

Expected: `accountability-locks` の内容で新ブランチに切り替わる（`DashboardView.swift` 等が枝の内容になる）。

- [ ] **Step 3: 起点を確認**

Run: `git log --oneline -1`
Expected: `accountability-locks` の HEAD コミットが表示される。

> 注: `docs/` 配下の spec/plan は untracked のため、ブランチ切替後も作業ツリーに残る。必要なら本ブランチでまとめてコミットしてよい。

---

## Task 1: Home 申請ボタンの改称＋主役化（#2/#6-1）

**Files:**
- Modify: `ScreenTimeSharing/Views/DashboardView.swift`（`friendRequestButton(for:)` 〜 L975-1000 / 任意で `unblockButton(for:)` L941-973）

### 設計
- ラベル `"Request"` → `"Ask Friends"`（アイコン `hands.sparkles.fill` は維持）。
- 背景を **塗りつぶしの accent**（主役）に。文字色を白に。
- `unblockButton` は **任意**で副次（アウトライン）化。塗りの Request と並ぶことで主役/副次が成立するため、Unblock 変更は省略しても可。

- [ ] **Step 1: `friendRequestButton(for:)` のラベル・背景・前景を変更**

変更前（該当部分）:

```swift
            Label("Request", systemImage: "hands.sparkles.fill")
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    Capsule()
                        .fill(isEnabled ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.12))
                )
                .appCapsuleButtonHitArea()
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
```

変更後:

```swift
            Label("Ask Friends", systemImage: "hands.sparkles.fill")
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(
                    Capsule()
                        .fill(isEnabled ? Color.accentColor : Color.secondary.opacity(0.12))
                )
                .appCapsuleButtonHitArea()
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? Color.white : Color.secondary)
```

- [ ] **Step 2: （任意）`unblockButton(for:)` を副次（アウトライン）化**

> 主役/副次のコントラストが弱いと感じた場合のみ適用。シミュレータで確認して採否を決める。

変更前（背景）:

```swift
                .background(
                    Capsule()
                        .fill(isDisabled ? Color.secondary.opacity(0.12) : Color.accentColor.opacity(0.14))
                )
```

変更後（アウトライン）:

```swift
                .background(
                    Capsule()
                        .strokeBorder(
                            isDisabled ? Color.secondary.opacity(0.25) : Color.accentColor.opacity(0.5),
                            lineWidth: 1
                        )
                )
```

- [ ] **Step 3: アクセシビリティ文言の整合（任意・微修正）**

`friendRequestButton(for:)` の `accessibilityLabel` は既存の "Request time from friends for \(group.name)" を維持して可（意味は不変）。変更しないことを選んでよい。

- [ ] **Step 4: ビルド確認（Xcode）**

Run: Xcode で `ScreenTimeSharing` スキームをビルド（⌘B）
Expected: ビルド成功（型エラーなし）。

- [ ] **Step 5: 手動確認（シミュレータ）**

確認項目:
1. Home のブロックグループ行で、申請ボタンが **塗りつぶし＋「Ask Friends」** で表示される。
2. ボタン押下で `FriendApprovalRequestView`（カメラ申請フロー）が開く（挙動は従来どおり）。
3. `friendRequestConfig` 無効グループでは従来どおり無効表示（secondary）。
4. Unblock ボタンが相対的に控えめに見える。

- [ ] **Step 6: コミット**

```bash
git add ScreenTimeSharing/Views/DashboardView.swift
git commit -m "Promote Home time-request button to primary 'Ask Friends' affordance

The most-used action was a generic, low-emphasis 'Request' capsule sitting
beside Unblock, hurting discoverability. Make it the filled primary so users
recognize the request flow at a glance."
```

---

## Task 2: Feed を受信専用化（#2/#6-2）

**Files:**
- Modify: `ScreenTimeSharing/Views/BlockingSettingsView.swift`（`RequestFeedView`）

### 撤去対象（すべて「申請作成ツールバーボタン」専用で、撤去により孤立する）
- ツールバーの作成ボタン `ToolbarItem(.topBarTrailing)`（`hands.sparkles.fill` / `startInAppFriendRequest()`）。**`if showsDoneButton { ToolbarItem(.cancellationAction) ... }` は残す。**
- `.confirmationDialog("Choose App Group", ...)`
- `.sheet(item: $requestGroup) { ... }`
- `.alert("No Friend Request Group", ...)`
- `private func startInAppFriendRequest()`
- `@State private var isChoosingRequestGroup`, `@State private var requestGroup`, `@State private var isShowingNoRequestGroupAlert`
- `private var eligibleRequestGroups: [BlockGroup]`（上記2箇所のみで使用 → 孤立）

> タブアイコンは変更不要（`RootView.swift` の `AppTab.feed` は既に `tray.full`）。Feed は受信した申請の表示・承認/拒否に専念する。

- [ ] **Step 1: ツールバーの作成ボタンのみ撤去**

変更前（`RequestFeedView` の `.toolbar` 内・冒頭）:

```swift
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    startInAppFriendRequest()
                } label: {
                    Image(systemName: "hands.sparkles.fill")
                }
                .accessibilityLabel("Create friend request")
            }

            if showsDoneButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        AppHaptics.buttonTap()
                        dismiss()
                    }
                }
            }
        }
```

変更後（作成ボタンの `ToolbarItem` を削除、Done は維持）:

```swift
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        AppHaptics.buttonTap()
                        dismiss()
                    }
                }
            }
        }
```

- [ ] **Step 2: 直後の `.confirmationDialog` / `.sheet(item: $requestGroup)` / `.alert` を削除**

変更前（`.toolbar { ... }` の直後に続くモディファイア群）:

```swift
        .confirmationDialog(
            "Choose App Group",
            isPresented: $isChoosingRequestGroup,
            titleVisibility: .visible
        ) {
            ForEach(eligibleRequestGroups) { group in
                Button(group.name) {
                    AppHaptics.buttonTap()
                    requestGroup = group
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pick which blocked app group this request is for.")
        }
        .sheet(item: $requestGroup) { group in
            FriendApprovalRequestView(group: group)
        }
        .alert("No Friend Request Group", isPresented: $isShowingNoRequestGroupAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Turn on friend requests for an active block group before creating an in-app request.")
        }
```

変更後: **上記ブロックを丸ごと削除**（他のモディファイア順序は維持）。

- [ ] **Step 3: 孤立した `@State` 3 つを削除**

削除する宣言（`RequestFeedView` 先頭付近）:

```swift
    @State private var isChoosingRequestGroup = false
    @State private var requestGroup: BlockGroup?
    @State private var isShowingNoRequestGroupAlert = false
```

- [ ] **Step 4: 孤立した `eligibleRequestGroups` computed と `startInAppFriendRequest()` を削除**

削除する `eligibleRequestGroups`（L28 付近）:

```swift
    private var eligibleRequestGroups: [BlockGroup] {
        // ...（本体ごと削除）
    }
```

削除する `startInAppFriendRequest()`（L386 付近）:

```swift
    private func startInAppFriendRequest() {
        // switch eligibleRequestGroups.count { ... isShowingNoRequestGroupAlert / requestGroup / isChoosingRequestGroup }
    }
```

> 実装者へ: 上記2つは複数行のため、定義範囲全体を削除すること。削除後に下記 Step 5 で残参照ゼロを必ず確認。

- [ ] **Step 5: 残参照がないことを確認（孤立除去の検証）**

Run:
```bash
git grep -nE 'startInAppFriendRequest|isChoosingRequestGroup|eligibleRequestGroups|isShowingNoRequestGroupAlert|requestGroup' -- ScreenTimeSharing/Views/BlockingSettingsView.swift
```
Expected: **ヒット0件**（すべて撤去済み）。`requestGroup` が別用途で残っていないかも併せて確認。

- [ ] **Step 6: ビルド確認（Xcode）**

Run: Xcode で `ScreenTimeSharing` をビルド（⌘B）
Expected: 未使用変数・未定義参照のエラーなしでビルド成功。

- [ ] **Step 7: 手動確認（シミュレータ）**

確認項目:
1. Feed タブのツールバーから申請作成ボタン（`hands.sparkles`）が消えている。
2. Feed は受信した申請の表示・承認/拒否が従来どおり機能する。
3. 申請の作成は **Home の「Ask Friends」**（および従来のブロック詳細・Shield 経由）から行える。
4. `showsDoneButton` が true の文脈（シート表示時など）で Done ボタンが従来どおり出る。

- [ ] **Step 8: コミット**

```bash
git add ScreenTimeSharing/Views/BlockingSettingsView.swift
git commit -m "Make Feed receive-only by removing in-feed request composer entry

Two competing ways to start a request (Home + Feed toolbar) blurred the model.
Consolidate creation onto Home and let Feed focus on incoming approvals;
remove the now-orphaned dialog/sheet/alert/state and helpers."
```

---

## Task 3: 最終確認

- [ ] **Step 1: 差分レビュー**

Run: `git diff origin/product/accountability-locks --stat`
Expected: 変更は `DashboardView.swift` と `BlockingSettingsView.swift` の 2 ファイルのみ。

- [ ] **Step 2: 受け入れ基準（spec §A-6 / #2/#6）との突き合わせ**

- [ ] Home に主役の申請CTA（テキスト明示「Ask Friends」）が存在する。
- [ ] アイコンのみ・確認ダイアログ経由の遠回り導線（Feed 作成ボタン）が主導線から排除されている。
- [ ] 申請開始 → カメラ起動の挙動が維持されている。
- [ ] 2 ファイル以外に変更がない（サージカル）。

- [ ] **Step 3: ユーザーへ結果提示**（Codex の出力を verbatim で提示し、適用可否を確認 — CLAUDE.md）

---

## Self-Review（計画著者による点検）

- **Spec coverage:** #2/#6-1（Home ボタン改称・主役化）= Task 1、#2/#6-2（Feed 受信専用化）= Task 2。spec §A-5 の項目1・2 に対応。残り（メッセージ前出し/バッジ/下書き/コーチマーク）は Phase 1 で対象外。
- **Placeholder scan:** 撤去対象の複数行関数（`eligibleRequestGroups` / `startInAppFriendRequest`）は本体省略表記だが、Step 5 の grep 検証で実体除去を担保（プレースホルダではなく「全体削除＋残参照0検証」の指示）。
- **型/シンボル整合:** 追加シンボルなし。削除シンボル（`startInAppFriendRequest`, `isChoosingRequestGroup`, `requestGroup`, `isShowingNoRequestGroupAlert`, `eligibleRequestGroups`）は grep で全参照が撤去対象に含まれることを確認済み。
- **スコープ:** 単一の実装計画に収まる（2 ファイル・View 層のみ）。

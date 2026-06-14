# Phase 1: タイムリクエスト体験の磨き込み + Shield連携の検証/磨き込み 実装計画

> **For agentic workers:** この計画は **Codex が実装**する前提（本リポジトリの `CLAUDE.md`: Claude が計画・検証、Codex が実装）。各タスクは exact なファイル/前後コードで記述。SwiftUI/UIKit View 層が中心で、この環境にフルXcodeが無いため**検証は Xcode ビルド＋手動確認**。唯一の純ロジック追加（F4 のコア関数）のみ `swift test` で自動検証する。進捗はチェックボックス（`- [ ]`）で管理。

**Goal:** Phase 0（Home の `Ask Friends` 主役化・Feed 受信専用化）に続き、最頻機能であるタイムリクエストの**コンポーザ体験**を磨き（メッセージ前出し・保留バッジ・下書き復帰・初回コーチマーク・分数ヒント・アクセシビリティ）、**Shield連携(#7)** の実機動作を検証し軽微に磨き込む（カメラ拒否時の設定誘導・無効グループの設定誘導）。

**Architecture:** 既存の `feature/phase0-request-button-ux`（= `accountability-locks` ベース）に対する **View層中心の追加・改修**。新規型は最小（AppModel に in-memory 下書き 1 構造体、コア `BlockingStateResolver` に送信済み保留の集計関数 1 つ）。`FriendApprovalRequestView`（`DashboardView.swift` 内）と `BlockingOverviewCard`（同）、カメラ Representable/VC（同）、コア `BlockingModels.swift`、`AppModel.swift` を触る。

**Tech Stack:** Swift / SwiftUI / UIKit（カメラVC）/ swift-testing（`import Testing`, `#expect`）/ `ScreenTimeSharingCore`(SPM)。

**Base branch:** `feature/phase0-request-button-ux`（Phase 0 がコミット済み。Phase 1 はこの上に積む。`main` は対象外）
**確定済み設計判断（2026-06-11 ユーザー確定）:**
1. **#7 範囲** = 検証チェックリスト＋軽微な磨き込み（**S4 URLスキーム deep-link は見送り**。既存の通知タップ経路が機能するため）
2. **F5 下書き** = アプリ起動中のみ保持（AppModel に in-memory 保持、アプリ終了で破棄）
3. **F4 バッジ** = 自分が送った保留中リクエスト（グループ別、`isSent(byAny:) && status == .pending && groupID 一致`）

**関連spec:** `docs/specs/2026-06-05-improvement-breakdown.md`（§A タイムリクエスト体験 / §B #7）

---

## 重要な制約・前提

- **対象ブランチは `feature/phase0-request-button-ux`。** Phase 1 用の作業ブランチをここから切る（Task 0）。`main` には適用しない。
- **この環境ではアプリをビルド/実行できない**（CLI Tools のみ、フルXcodeなし）。View 系の最終検証は **Xcode ビルド＋シミュレータ/実機の目視**。Codex/実装者が Xcode 環境で実施する。
- **#7 のコアは既に実装済み**（コード再確認で判明）。Shield→カメラ自動起動（`requestStep` 既定 `.capture`）、押下後フィードバック（Shield Config 拡張の "Request ready" 状態）、無効時グレー表示は**既存**。よって #7 は **(a) 実機動作確認（B1）** と **(b) 軽微な磨き込み（B2: カメラ拒否時の設定誘導／S5: 無効グループの設定誘導は A4 に内包）** に絞る。`openedFromShield` フラグは**追加しない**（自動カメラ到達は既存挙動で満たされ、フラグは死にコードになるため。CLAUDE.md Principle 2 簡潔性）。
- **TDD は F4 のコア関数のみ。** 他は View の見た目/導線変更で純ロジックがなく、`swift test` 対象は `ScreenTimeSharingCore` のみ。F4 はロジックをコアへ寄せて 1 件のユニットテストで検証する。残りは**ビルド成功＋手動シナリオ確認**を受け入れ基準とする。
- **サージカル原則:** 指定箇所のみ変更。隣接コードの「改善」や無関係なリファクタは禁止。既存スタイル（`AppCard`/`AppSection`/`AppCardDivider`/`appCardRow`/`appCapsuleButtonHitArea`/`AppHaptics`/`Color.accentColor`）に合わせる。
- **行番号は着手時点の概算**（編集で前後する）。各ステップの「変更前」スニペットで照合してから編集すること。

---

## ファイル変更マップ

| ファイル | 役割 | 変更（タスク） |
|---|---|---|
| `Sources/ScreenTimeSharingCore/BlockingModels.swift` | コア集計 | 送信済み保留の集計関数を追加（A4） |
| `Tests/ScreenTimeSharingCoreTests/BlockingModelsTests.swift` | コアテスト | 上記関数のテスト追加（A4） |
| `ScreenTimeSharing/AppModel.swift` | 中央状態 | F4 グループ別保留数 computed、F5 in-memory 下書きストア（A3/A4） |
| `ScreenTimeSharing/Views/DashboardView.swift` | Home＋コンポーザ | F8 a11y（A1）/ F3+F7 コンポーザ再構成（A2）/ F5 下書き（A3）/ F4バッジ+F8ボタン+S5（A4）/ F6 コーチマーク（A5）/ B2 カメラ拒否誘導（B2） |

> `BlockingSettingsView.swift` / `RootView.swift` / Shield 拡張は **Phase 1 で変更しない**（#7 はコード変更なしの検証＝B1 と、`DashboardView` 内カメラの磨き込み＝B2 が中心）。

---

## Task 0: フィーチャーブランチの作成

**Files:**（リポジトリ操作のみ）

- [ ] **Step 1: 現在地を確認**

Run: `git branch --show-current`
Expected: `feature/phase0-request-button-ux`（Phase 0 がコミット済みのブランチ）。

- [ ] **Step 2: Phase 1 ブランチを作成**

```bash
git switch -c feature/phase1-time-request-and-shield
```

Expected: Phase 0 の内容を引き継いだ新ブランチに切り替わる（`DashboardView.swift` に `"Ask Friends"` が存在する状態）。

- [ ] **Step 3: 起点を確認**

Run: `git grep -n '"Ask Friends"' -- ScreenTimeSharing/Views/DashboardView.swift`
Expected: 1 件ヒット（Phase 0 の成果が土台にある）。

> 注: `docs/` の spec/plan は本ブランチへまとめてコミットしてよい。

---

# タスク群A: アプリ内コンポーザ体験（#2/#6 残り）

`FriendApprovalRequestView`（`ScreenTimeSharing/Views/DashboardView.swift` 内）と `BlockingOverviewCard`（同）が中心。小さく独立した A1 から着手し、構造変更（A2）→状態追加（A3/A4）→カード（A5）の順で before/after の食い違いを避ける。

---

## Task A1: コンポーザのアクセシビリティ強化（F8）

最小・独立。送信ボタンとフレンド選択行に a11y を付与する。

**Files:**
- Modify: `ScreenTimeSharing/Views/DashboardView.swift`（`sendButton` 〜 L1831-1855、Friends セクションのトグル 〜 L1700-1730）

- [ ] **Step 1: 送信ボタンに a11y ラベル/ヒントを追加**

変更前（`sendButton` の Button 部分）:

```swift
            .buttonStyle(.plain)
            .foregroundStyle(canSendRequest ? Color.white : Color.secondary)
            .disabled(!canSendRequest)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }
```

変更後（`.disabled(!canSendRequest)` の直後に a11y を追加）:

```swift
            .buttonStyle(.plain)
            .foregroundStyle(canSendRequest ? Color.white : Color.secondary)
            .disabled(!canSendRequest)
            .accessibilityLabel("Send time request")
            .accessibilityHint(
                canSendRequest
                    ? "Sends your photo request to the selected friends."
                    : "Take a photo and choose at least one friend to enable sending."
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }
```

- [ ] **Step 2: フレンド選択行に a11y を追加**

変更前（Friends セクションの各行 Button の末尾、`.buttonStyle(.plain)` の直後）:

```swift
                                .appCardRow()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .onTapGesture {
                isMessageFocused = false
            }
```

変更後（`.buttonStyle(.plain)` の直後に a11y を追加。チェックマーク画像は要素統合で読み上げから除外）:

```swift
                                .appCardRow()
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(friend.name)
                            .accessibilityValue(selectedFriendIDs.contains(friend.id) ? "Selected" : "Not selected")
                            .accessibilityHint("Double tap to toggle selection.")
                            .accessibilityAddTraits(
                                selectedFriendIDs.contains(friend.id) ? [.isButton, .isSelected] : .isButton
                            )
                        }
                    }
                }
            }
            .onTapGesture {
                isMessageFocused = false
            }
```

- [ ] **Step 3: ビルド確認（Xcode）** — `ScreenTimeSharing` を ⌘B。型エラーなし。
- [ ] **Step 4: 手動確認（VoiceOver）** — 送信ボタンが「Send time request」、無効時にヒントが読まれる。各フレンド行が名前＋選択状態（Selected/Not selected）で読まれる。
- [ ] **Step 5: コミット**

```bash
git add ScreenTimeSharing/Views/DashboardView.swift
git commit -m "Add accessibility labels to time-request composer controls

The send button and friend-selection rows exposed no VoiceOver context
(selection state was conveyed by a checkmark glyph only). Announce intent
and selection state so the most-used flow is usable with VoiceOver."
```

---

## Task A2: メッセージ欄を Step2(Review) へ前出し ＋ 分数ヒント（F3 / F7）

「写真＋お願い文」を Review で一緒に組ませる（F3）。分数選択の近くに静的ヒントを置く（F7。承認率データは存在しないため**静的コピー**で確定 — spec §A-5 項目7）。

**Files:**
- Modify: `ScreenTimeSharing/Views/DashboardView.swift`（`reviewStep` L1603-1629 / `detailsStep` Request セクション L1643-1682 / キーボードツールバー gate L1531-1539）

- [ ] **Step 1: `reviewStep` にメッセージ欄を追加**

変更前（`reviewStep`）:

```swift
    @ViewBuilder
    private var reviewStep: some View {
        AppScreenScroll(backgroundStyle: .white) {
            if let selectedPhotoData, let image = requestImage(from: selectedPhotoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4 / 5, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
            } else {
                AppCard {
                    ContentUnavailableView(
                        "Photo Not Ready",
                        systemImage: "camera.fill",
                        description: Text("Retake the photo to continue.")
                    )
                    .appCardRow(verticalPadding: 24)
                }
            }
        }
    }
```

変更後（写真ブロックの後に Message セクションを追加し、スクロールでキーボードを閉じる）:

```swift
    @ViewBuilder
    private var reviewStep: some View {
        AppScreenScroll(backgroundStyle: .white) {
            if let selectedPhotoData, let image = requestImage(from: selectedPhotoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4 / 5, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
            } else {
                AppCard {
                    ContentUnavailableView(
                        "Photo Not Ready",
                        systemImage: "camera.fill",
                        description: Text("Retake the photo to continue.")
                    )
                    .appCardRow(verticalPadding: 24)
                }
            }

            AppSection("Message") {
                AppCard {
                    TextField("Optional message", text: $message, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($isMessageFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            isMessageFocused = false
                        }
                        .appCardRow()
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
```

- [ ] **Step 2: `detailsStep` の Request セクションからメッセージ欄を撤去し、分数ヒントを追加（F3 撤去 + F7 追加）**

変更前（`detailsStep` の Request セクション）:

```swift
            AppSection("Request") {
                AppCard {
                    Button {
                        AppHaptics.buttonTap()
                        isMessageFocused = false
                        isShowingMinutePicker = true
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Time")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Text(RequestMinuteFormatting.label(requestedMinutes))
                                    .font(.title3.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.primary)
                            }

                            Spacer()

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .appCardRow()
                    }
                    .buttonStyle(.plain)

                    AppCardDivider()

                    TextField("Optional message", text: $message, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($isMessageFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            isMessageFocused = false
                        }
                        .appCardRow()
                }
            }
```

変更後（`AppCardDivider()` + メッセージ TextField を削除し、ヒント Text を AppCard の外・セクション内に追加）:

```swift
            AppSection("Request") {
                AppCard {
                    Button {
                        AppHaptics.buttonTap()
                        isMessageFocused = false
                        isShowingMinutePicker = true
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Time")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Text(RequestMinuteFormatting.label(requestedMinutes))
                                    .font(.title3.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.primary)
                            }

                            Spacer()

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .appCardRow()
                    }
                    .buttonStyle(.plain)
                }

                Text("Shorter requests (5–15 min) tend to get approved faster.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
```

- [ ] **Step 3: キーボードツールバーの表示条件を `.review` に変更**

変更前（`body` の `.toolbar` 内）:

```swift
                ToolbarItemGroup(placement: .keyboard) {
                    if requestStep == .details && isMessageFocused {
                        Spacer()

                        Button("Done") {
                            isMessageFocused = false
                        }
                    }
                }
```

変更後（メッセージ欄が Review に移ったため `.review` でツールバー Done を出す）:

```swift
                ToolbarItemGroup(placement: .keyboard) {
                    if requestStep == .review && isMessageFocused {
                        Spacer()

                        Button("Done") {
                            isMessageFocused = false
                        }
                    }
                }
```

- [ ] **Step 4: 残参照の確認（孤立除去）**

Run:
```bash
git grep -n 'Optional message' -- ScreenTimeSharing/Views/DashboardView.swift
```
Expected: **1 件のみ**（`reviewStep` に移動した TextField）。`detailsStep` 側に残っていないこと。

- [ ] **Step 5: ビルド確認（Xcode）** — ⌘B。型エラーなし。
- [ ] **Step 6: 手動確認（シミュレータ）**

1. 撮影 → Review でメッセージを入力でき、キーボード上に Done が出る。スクロールでキーボードが閉じる。
2. Continue → Details では Time 行の下に「Shorter requests (5–15 min)…」ヒントが出る。メッセージ欄は Details にはもう無い。
3. 送信後、メッセージが申請に含まれる（従来どおり `requestFriendTime(message:)` に渡る）。

- [ ] **Step 7: コミット**

```bash
git add ScreenTimeSharing/Views/DashboardView.swift
git commit -m "Move request message into the photo review step and add a minute hint

Composing the pleading message next to the photo makes the 'package' obvious
and surfaces a field that was buried in step 3. Add a static hint that shorter
requests get approved faster to nudge realistic asks."
```

---

## Task A3: 下書き/復帰（アプリ起動中のみ保持）（F5）

撮影写真・分数・メッセージ・選択フレンドを AppModel に in-memory で保持。同一起動中にコンポーザを再度開くと復元。送信成功で破棄。アプリ終了で破棄（永続化しない）。

**Files:**
- Modify: `ScreenTimeSharing/AppModel.swift`（`requestFriendTime` の直後に下書きストアを追加）
- Modify: `ScreenTimeSharing/Views/DashboardView.swift`（`FriendApprovalRequestView` の状態・ライフサイクル・`sendRequest`）

- [ ] **Step 1: AppModel に in-memory 下書きストアを追加**

挿入位置: `func requestFriendTime(...) -> Bool { ... }` の閉じ括弧（〜L887）の直後。

追加コード:

```swift
    // MARK: - Friend request draft (in-memory, current app session only)

    struct FriendRequestDraft {
        var photoJPEGData: Data?
        var requestedMinutes: Int
        var message: String
        var selectedFriendIDs: [String]
    }

    private var friendRequestDrafts: [String: FriendRequestDraft] = [:]

    func friendRequestDraft(for groupID: String) -> FriendRequestDraft? {
        friendRequestDrafts[groupID]
    }

    func saveFriendRequestDraft(_ draft: FriendRequestDraft, for groupID: String) {
        friendRequestDrafts[groupID] = draft
    }

    func clearFriendRequestDraft(for groupID: String) {
        friendRequestDrafts.removeValue(forKey: groupID)
    }
```

> 補足: `friendRequestDrafts` はデフォルト値付きの stored property なので `init` 変更は不要。`@Published` にはしない（コンポーザは onAppear で読み、onDisappear で書くだけで、リアクティブ購読は不要）。

- [ ] **Step 2: `FriendApprovalRequestView` に送信完了フラグを追加**

変更前（状態宣言の末尾）:

```swift
    @State private var message = ""
    @FocusState private var isMessageFocused: Bool

    private let minuteOptions = [5, 10, 15, 20, 30, 45, 60]
```

変更後（`@FocusState` の直後に `didSendRequest` を追加）:

```swift
    @State private var message = ""
    @FocusState private var isMessageFocused: Bool
    @State private var didSendRequest = false

    private let minuteOptions = [5, 10, 15, 20, 30, 45, 60]
```

- [ ] **Step 3: `body` に復元/保存のライフサイクルを付与**

変更前（`body` 冒頭の `requestStepContent` + `navigationTitle`）:

```swift
    var body: some View {
        NavigationStack {
            requestStepContent
                .navigationTitle(navigationTitle)
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
```

変更後（`navigationTitle` の直後に onAppear/onDisappear を追加）:

```swift
    var body: some View {
        NavigationStack {
            requestStepContent
                .navigationTitle(navigationTitle)
                .onAppear {
                    restoreDraftIfAvailable()
                }
                .onDisappear {
                    persistDraftIfNeeded()
                }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
```

- [ ] **Step 4: 復元/保存ヘルパを追加**

挿入位置: `private func sendRequest()` の直前（〜L1857）。

追加コード:

```swift
    private func restoreDraftIfAvailable() {
        guard selectedPhotoData == nil,
              message.isEmpty,
              selectedFriendIDs.isEmpty,
              let draft = model.friendRequestDraft(for: group.id) else {
            return
        }

        selectedPhotoData = draft.photoJPEGData
        requestedMinutes = draft.requestedMinutes
        message = draft.message
        selectedFriendIDs = Set(draft.selectedFriendIDs)

        if selectedPhotoData != nil {
            requestStep = .review
        }
    }

    private func persistDraftIfNeeded() {
        if didSendRequest {
            model.clearFriendRequestDraft(for: group.id)
            return
        }

        let hasContent = selectedPhotoData != nil
            || !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !selectedFriendIDs.isEmpty

        if hasContent {
            model.saveFriendRequestDraft(
                AppModel.FriendRequestDraft(
                    photoJPEGData: selectedPhotoData,
                    requestedMinutes: requestedMinutes,
                    message: message,
                    selectedFriendIDs: Array(selectedFriendIDs)
                ),
                for: group.id
            )
        } else {
            model.clearFriendRequestDraft(for: group.id)
        }
    }
```

- [ ] **Step 5: `sendRequest` 成功時に送信フラグを立てる**

変更前:

```swift
        if model.requestFriendTime(
            groupID: group.id,
            seconds: TimeInterval(requestedMinutes * 60),
            selectedFriendIDs: Array(selectedFriendIDs),
            message: message,
            photoJPEGData: selectedPhotoData
        ) {
            AppHaptics.buttonTap()
            dismiss()
        }
```

変更後（`dismiss()` の前に `didSendRequest = true`。onDisappear で下書きが破棄される）:

```swift
        if model.requestFriendTime(
            groupID: group.id,
            seconds: TimeInterval(requestedMinutes * 60),
            selectedFriendIDs: Array(selectedFriendIDs),
            message: message,
            photoJPEGData: selectedPhotoData
        ) {
            AppHaptics.buttonTap()
            didSendRequest = true
            dismiss()
        }
```

- [ ] **Step 6: ビルド確認（Xcode）** — ⌘B。型エラーなし。
- [ ] **Step 7: 手動確認（シミュレータ）**

1. 撮影→メッセージ入力→Cancel で閉じる→再度 `Ask Friends` を開くと、写真・分数・メッセージ・選択フレンドが復元され、Review から再開できる。
2. 送信して閉じた後に再度開くと**下書きは空**（送信で破棄）。
3. 別グループの `Ask Friends` を開くと、そのグループの下書きは独立（groupID キー）。
4. アプリを完全終了して再起動すると下書きは消える（in-memory のみ）。

- [ ] **Step 8: コミット**

```bash
git add ScreenTimeSharing/AppModel.swift ScreenTimeSharing/Views/DashboardView.swift
git commit -m "Keep an in-memory time-request draft within the app session

Leaving the composer mid-flow discarded the captured photo, forcing a reshoot.
Hold the photo/minutes/message/friends per group in memory and restore on
reopen; clear on successful send. Intentionally not persisted across launches."
```

---

## Task A4: 保留中バッジ ＋ ボタンa11y ＋ 無効時の設定誘導（F4 / F8 / S5）

`friendRequestButton(for:)` を**一度だけ書き換え**、3 つの改善を同時に入れる。集計ロジックは**コアへ寄せてユニットテスト**する。

**Files:**
- Modify: `Sources/ScreenTimeSharingCore/BlockingModels.swift`（`BlockingStateResolver` に関数追加）
- Modify: `Tests/ScreenTimeSharingCoreTests/BlockingModelsTests.swift`（テスト追加）
- Modify: `ScreenTimeSharing/AppModel.swift`（グループ別保留数 computed）
- Modify: `ScreenTimeSharing/Views/DashboardView.swift`（`friendRequestButton(for:)` 書き換え）

### A4-1: コア集計関数（TDD）

- [ ] **Step 1: 失敗するテストを書く**

挿入位置: `Tests/ScreenTimeSharingCoreTests/BlockingModelsTests.swift` の既存テスト群の末尾（`pendingReceivedFriendRequestsMatchLegacyProfileAliases` の後あたり）。

```swift
@Test func pendingSentFriendRequestsAreGroupScopedAndPendingOnly() {
    let now = Date(timeIntervalSince1970: 1_779_236_400)
    let sentPendingSocial = BlockFriendRequest(
        id: "sent-pending-social",
        groupID: "social",
        requestedSeconds: 15 * 60,
        selectedFriendIDs: ["sam"],
        message: "",
        requesterID: "me",
        createdAt: now
    )
    let sentPendingGames = BlockFriendRequest(
        id: "sent-pending-games",
        groupID: "games",
        requestedSeconds: 15 * 60,
        selectedFriendIDs: ["sam"],
        message: "",
        requesterID: "me",
        createdAt: now.addingTimeInterval(-10)
    )
    let sentApprovedSocial = BlockFriendRequest(
        id: "sent-approved-social",
        groupID: "social",
        requestedSeconds: 15 * 60,
        selectedFriendIDs: ["sam"],
        message: "",
        requesterID: "me",
        status: .approved,
        createdAt: now.addingTimeInterval(-20)
    )
    let receivedPendingSocial = BlockFriendRequest(
        id: "received-pending-social",
        groupID: "social",
        requestedSeconds: 15 * 60,
        selectedFriendIDs: ["me"],
        message: "",
        requesterID: "sam",
        createdAt: now.addingTimeInterval(-5)
    )
    let state = BlockingState(
        friendRequests: [sentPendingSocial, sentPendingGames, sentApprovedSocial, receivedPendingSocial],
        lastUpdated: now
    )
    let currentIDs: Set<String> = ["me", "profile-me"]

    let ids = BlockingStateResolver.pendingSentFriendRequests(
        forAny: currentIDs,
        inGroup: "social",
        in: state
    ).map(\.id)

    #expect(ids == ["sent-pending-social"])
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `swift test --filter pendingSentFriendRequestsAreGroupScopedAndPendingOnly`
Expected: コンパイルエラー or 失敗（`pendingSentFriendRequests(forAny:inGroup:in:)` 未定義）。

- [ ] **Step 3: コア関数を実装**

挿入位置: `Sources/ScreenTimeSharingCore/BlockingModels.swift` の `BlockingStateResolver` 内、既存 `pendingReceivedFriendRequests(forAny:in:)`（〜L1064）の直後。

```swift
    public static func pendingSentFriendRequests(
        forAny userIDs: Set<String>,
        inGroup groupID: String,
        in state: BlockingState
    ) -> [BlockFriendRequest] {
        state.friendRequests
            .filter { $0.groupID == groupID && $0.isSent(byAny: userIDs) && $0.status == .pending }
            .sorted { $0.createdAt > $1.createdAt }
    }
```

> 既存の `pendingReceivedFriendRequests(forAny:in:)` と対称。`isSent(byAny:)` は `BlockFriendRequest` の既存ヘルパ（テスト L470 で使用実績あり）。

- [ ] **Step 4: テストが通ることを確認**

Run: `swift test --filter pendingSentFriendRequestsAreGroupScopedAndPendingOnly`
Expected: PASS。

- [ ] **Step 5: 全コアテストの回帰確認**

Run: `swift test`
Expected: 全 PASS（既存テストを壊していない）。

### A4-2: AppModel computed

- [ ] **Step 6: AppModel にグループ別の送信済み保留数を追加**

挿入位置: `ScreenTimeSharing/AppModel.swift` の `var pendingBlockRequestCount: Int { ... }`（〜L364）の直後。

```swift
    func pendingOutgoingFriendRequestCount(for groupID: String) -> Int {
        BlockingStateResolver.pendingSentFriendRequests(
            forAny: currentFriendIdentityIDs,
            inGroup: groupID,
            in: blockingState
        ).count
    }
```

> `currentFriendIdentityIDs` は既存（AppModel.swift:378-380 = `Set([profile.id, "profile-\(profile.id)"])`）。

### A4-3: `friendRequestButton(for:)` の書き換え

- [ ] **Step 7: `friendRequestButton(for:)` を書き換え（F4 バッジ + F8 a11y + S5 無効時→設定）**

変更前:

```swift
    private func friendRequestButton(for group: BlockGroup) -> some View {
        let isEnabled = group.friendRequestConfig.isEnabled

        return Button {
            AppHaptics.buttonTap()
            friendRequestGroup = group
        } label: {
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
        .disabled(!isEnabled)
        .accessibilityLabel(
            isEnabled
                ? "Request time from friends for \(group.name)"
                : "Friend requests disabled for \(group.name)"
        )
    }
```

変更後:

```swift
    private func friendRequestButton(for group: BlockGroup) -> some View {
        let isEnabled = group.friendRequestConfig.isEnabled
        let pendingCount = model.pendingOutgoingFriendRequestCount(for: group.id)

        return Button {
            AppHaptics.buttonTap()
            if isEnabled {
                friendRequestGroup = group
            } else {
                viewedGroup = group
            }
        } label: {
            Label(
                isEnabled ? "Ask Friends" : "Enable Requests",
                systemImage: isEnabled ? "hands.sparkles.fill" : "gearshape.fill"
            )
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
                .overlay(alignment: .topTrailing) {
                    if isEnabled && pendingCount > 0 {
                        Text("\(pendingCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.red))
                            .offset(x: 6, y: -6)
                            .accessibilityHidden(true)
                    }
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? Color.white : Color.secondary)
        .accessibilityLabel(
            isEnabled
                ? (pendingCount > 0
                    ? "Request time from friends for \(group.name), \(pendingCount) pending"
                    : "Request time from friends for \(group.name)")
                : "Enable friend requests for \(group.name) in settings"
        )
    }
```

> 変更点: (F4) `pendingCount > 0` のとき右上に赤バッジを overlay。(S5) `.disabled(!isEnabled)` を撤去し、無効時はラベルを「Enable Requests / gearshape.fill」にして `viewedGroup = group`（= `BlockGroupConfigurationView` を提示する既存 sheet）へ誘導。(F8) a11y ラベルに保留数/誘導文言を反映。`viewedGroup` は `BlockingOverviewCard` の既存 `@State`（L768、sheet は L819-821）。

- [ ] **Step 8: ビルド確認（Xcode）** — ⌘B。型エラーなし。
- [ ] **Step 9: 手動確認（シミュレータ）**

1. friendRequest 有効グループで申請を 1 件以上送ると、`Ask Friends` の右上に件数バッジ（赤）が出る。承認/失効で件数が減る。
2. friendRequest 無効グループ（active だが config off）では「Enable Requests」（歯車）になり、タップで当該グループの設定（`BlockGroupConfigurationView`）が開く。
3. VoiceOver で保留数/誘導文言が読まれる。

- [ ] **Step 10: コミット**

```bash
git add Sources/ScreenTimeSharingCore/BlockingModels.swift Tests/ScreenTimeSharingCoreTests/BlockingModelsTests.swift ScreenTimeSharing/AppModel.swift ScreenTimeSharing/Views/DashboardView.swift
git commit -m "Show pending count on Ask Friends and route disabled groups to settings

Add a tested core helper for group-scoped outgoing pending requests, surface
the count as a badge to nudge re-engagement, and turn the previously dead
greyed button into an 'Enable Requests' affordance that opens group settings."
```

---

## Task A5: 初回コーチマーク（F6）

friendRequest 有効グループがある初回に、`BlockingOverviewCard` に一度だけ説明カードを出す。TipKit 等の既存部品は無いためスクラッチ実装し、`@AppStorage` で一回限り。

**Files:**
- Modify: `ScreenTimeSharing/Views/DashboardView.swift`（`BlockingOverviewCard`）

- [ ] **Step 1: 一回限りフラグと表示条件を追加**

変更前（`BlockingOverviewCard` の `@State` 群）:

```swift
private struct BlockingOverviewCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var newGroupDraft: BlockGroupDraft?
    @State private var viewedGroup: BlockGroup?
    @State private var unblockConfirmationGroup: BlockGroup?
    @State private var friendRequestGroup: BlockGroup?
```

変更後（`@AppStorage` フラグを追加）:

```swift
private struct BlockingOverviewCard: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("hasSeenAskFriendsCoachmark.v1") private var hasSeenAskFriendsCoachmark = false
    @State private var newGroupDraft: BlockGroupDraft?
    @State private var viewedGroup: BlockGroup?
    @State private var unblockConfirmationGroup: BlockGroup?
    @State private var friendRequestGroup: BlockGroup?
```

- [ ] **Step 2: 表示条件 computed とカード View を追加**

挿入位置: `BlockingOverviewCard` の `inactiveGroups` computed（〜L783）の直後。

```swift
    private var showsAskFriendsCoachmark: Bool {
        !hasSeenAskFriendsCoachmark && activeGroups.contains { $0.friendRequestConfig.isEnabled }
    }

    private var askFriendsCoachmarkCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Stuck? Ask a friend for time", systemImage: "hands.sparkles.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)

                Text("When you want more time on a blocked app, tap “Ask Friends” below to send a selfie request. Once a friend approves, the app unlocks for a while.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    AppHaptics.buttonTap()
                    hasSeenAskFriendsCoachmark = true
                } label: {
                    Text("Got it")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
            .appCardRow(verticalPadding: 14)
        }
    }
```

- [ ] **Step 3: 非空ブランチの VStack にカードを挿入**

変更前（`body` の `else` 分岐の VStack 末尾、`New Group` の AppCard 直前）:

```swift
                    if !inactiveGroups.isEmpty {
                        blockGroupSection("Inactive", groups: inactiveGroups, isMuted: true)
                    }

                    AppCard {
                        HStack(spacing: 12) {
                            Button {
                                AppHaptics.buttonTap()
                                newGroupDraft = BlockGroupDraft()
                            } label: {
                                Label("New Group", systemImage: "plus.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                        }
                        .appCardRow(verticalPadding: 14)
                    }
```

変更後（`New Group` AppCard の直前にコーチマークを挿入）:

```swift
                    if !inactiveGroups.isEmpty {
                        blockGroupSection("Inactive", groups: inactiveGroups, isMuted: true)
                    }

                    if showsAskFriendsCoachmark {
                        askFriendsCoachmarkCard
                    }

                    AppCard {
                        HStack(spacing: 12) {
                            Button {
                                AppHaptics.buttonTap()
                                newGroupDraft = BlockGroupDraft()
                            } label: {
                                Label("New Group", systemImage: "plus.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                        }
                        .appCardRow(verticalPadding: 14)
                    }
```

- [ ] **Step 4: ビルド確認（Xcode）** — ⌘B。型エラーなし。
- [ ] **Step 5: 手動確認（シミュレータ）**

1. friendRequest 有効グループがある初回、コーチマークカードが Active/Inactive セクションと New Group の間に出る。
2. 「Got it」で消え、再表示されない（アプリ再起動後も `@AppStorage` で非表示）。
3. friendRequest 有効グループが 1 つも無い場合は出ない。

- [ ] **Step 6: コミット**

```bash
git add ScreenTimeSharing/Views/DashboardView.swift
git commit -m "Add a one-time Ask Friends coachmark on Home

New users had no in-context explanation of the core loop. Show a single
dismissible card once a friend-request-enabled group exists, gated by an
AppStorage flag so it never reappears."
```

---

# タスク群B: Shield連携（#7 検証＋軽微な磨き込み）

#7 のコアは実装済み（B0 参照）。本群は **B1 実機検証（コード変更なし）** と **B2 カメラ拒否時の設定誘導** に限定。S4 URLスキーム deep-link は**今回見送り**（既存の通知タップ経路で機能）。

> **B0（前提・コード変更なし）:** Shield→申請の往復は実装済み。Shield Config 拡張 `ShieldCopy.make`（`ScreenLogShieldConfigurationExtension.swift:79-90`）が「Request ready / Tap the deny notification…」状態を表示（S3 相当）。Shield Action 拡張がローカル通知（category `shield-friend-time-request`, userInfo `shieldFriendRequestGroupID`）を発火、`AppDelegate.userNotificationCenter(_:didReceive:)` → `ShieldFriendRequestNotificationCenter.shared.receive(groupID:)` → `AppModel.openPendingShieldFriendRequestFromNotification(groupID:)` → `RootView.swift:33-44` の `.sheet` が `FriendApprovalRequestView(group:)` を `.capture` から提示（S2 相当の自動カメラ到達は既存）。

---

## Task B1: 実機動作確認チェックリスト（S1・コード変更なし）

この環境では実行不可。実機（承認済み Capability＋iCloud アカウント）で以下を確認する。**コード変更はしない。**

- [ ] **Step 1: 準備** — friendRequest を有効化したブロックグループを 1 つ作成し、対象アプリをブロック。通知権限を許可。フレンドを 1 名以上接続。
- [ ] **Step 2: Shield 表示** — ブロック対象アプリを開く → Shield に「Request time from friends」セカンダリボタンが表示される。
- [ ] **Step 3: 押下→通知** — セカンダリ押下で Shield が閉じ、ローカル通知「Request time from friends」が発火する。
- [ ] **Step 4: Shield 再表示で "Request ready"** — 再度ブロック対象を開くと Shield が「Request ready / Tap the deny notification…」表示になっている（10分以内）。
- [ ] **Step 5: 通知タップ→コンポーザ** — 通知をタップ → アプリが起動/前面化し、該当グループの `FriendApprovalRequestView` が**カメラ（.capture）から**自動提示される。
- [ ] **Step 6: 送信/キャンセル** — 送信で申請が作成され Push が飛ぶ。キャンセル/dismiss で `clearPendingShieldFriendRequest()` され、再度 Shield から再開できる。
- [ ] **Step 7: 無効/失効** — 全グループで friendRequest 無効なら Shield セカンダリが「Friend request disabled」グレー。groupID が無効化/削除済みなら通知タップ後に「That request is no longer available.」表示でクリアされる。
- [ ] **Step 8: 結果を記録** — 上記の合否と気づきをこの計画に追記（不具合があれば別タスク化）。

> 既知の限界（要観察）: 通知権限が `.denied` の場合、Shield Action はローカル通知を黙って捨てる一方 `.close` を返すため、Shield が閉じてアプリに戻れない経路がある（B2 とは別。重大なら別途タスク化）。

---

## Task B2: カメラ拒否時の「設定を開く」誘導（S2 隣接の磨き込み）

カメラ拒否時、現状はぼかしカードのテキストのみで設定への導線が無い。Representable に権限拒否コールバックを追加（既存 `onCancel` パターンに倣う）し、コンポーザで「設定を開く」アラートを出す。Home/Shield 両経路に効く。

**Files:**
- Modify: `ScreenTimeSharing/Views/DashboardView.swift`（`FriendRequestCameraCaptureView` Representable / `FriendRequestCameraViewController` / `captureStep` / `FriendApprovalRequestView` 状態）

- [ ] **Step 1: Representable に `onPermissionDenied` を追加**

変更前:

```swift
    let showsCloseButton: Bool
    let onCancel: (() -> Void)?
    let onImage: (UIImage) -> Void

    init(
        showsCloseButton: Bool = false,
        onCancel: (() -> Void)? = nil,
        onImage: @escaping (UIImage) -> Void
    ) {
        self.showsCloseButton = showsCloseButton
        self.onCancel = onCancel
        self.onImage = onImage
    }

    func makeUIViewController(context: Context) -> FriendRequestCameraViewController {
        FriendRequestCameraViewController(
            colorScheme: colorScheme,
            showsCloseButton: showsCloseButton,
            onCapture: { image in
                onImage(image)
            },
            onCancel: {
                onCancel?()
            }
        )
    }
```

変更後:

```swift
    let showsCloseButton: Bool
    let onCancel: (() -> Void)?
    let onPermissionDenied: (() -> Void)?
    let onImage: (UIImage) -> Void

    init(
        showsCloseButton: Bool = false,
        onCancel: (() -> Void)? = nil,
        onPermissionDenied: (() -> Void)? = nil,
        onImage: @escaping (UIImage) -> Void
    ) {
        self.showsCloseButton = showsCloseButton
        self.onCancel = onCancel
        self.onPermissionDenied = onPermissionDenied
        self.onImage = onImage
    }

    func makeUIViewController(context: Context) -> FriendRequestCameraViewController {
        FriendRequestCameraViewController(
            colorScheme: colorScheme,
            showsCloseButton: showsCloseButton,
            onCapture: { image in
                onImage(image)
            },
            onCancel: {
                onCancel?()
            },
            onPermissionDenied: {
                onPermissionDenied?()
            }
        )
    }
```

- [ ] **Step 2: VC にプロパティと init 引数を追加**

変更前（プロパティ宣言、`private let onCancel: (() -> Void)?` の行）:

```swift
    private let onCancel: (() -> Void)?
```

変更後（直後に追加）:

```swift
    private let onCancel: (() -> Void)?
    private let onPermissionDenied: (() -> Void)?
```

変更前（init）:

```swift
    init(
        colorScheme: ColorScheme,
        showsCloseButton: Bool,
        onCapture: @escaping (UIImage) -> Void,
        onCancel: (() -> Void)?
    ) {
        self.colorScheme = colorScheme
        self.showsCloseButton = showsCloseButton
        self.onCapture = onCapture
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }
```

変更後:

```swift
    init(
        colorScheme: ColorScheme,
        showsCloseButton: Bool,
        onCapture: @escaping (UIImage) -> Void,
        onCancel: (() -> Void)?,
        onPermissionDenied: (() -> Void)? = nil
    ) {
        self.colorScheme = colorScheme
        self.showsCloseButton = showsCloseButton
        self.onCapture = onCapture
        self.onCancel = onCancel
        self.onPermissionDenied = onPermissionDenied
        super.init(nibName: nil, bundle: nil)
    }
```

- [ ] **Step 3: 権限拒否の各分岐でコールバックを呼ぶ**

変更前（`requestAccessAndConfigureCamera` の notDetermined→!granted と denied/restricted）:

```swift
                } else {
                    DispatchQueue.main.async {
                        self.showUnavailable(
                            title: "Camera Access Off",
                            detail: "Enable camera access to send a photo request."
                        )
                    }
                }
            }
        case .denied, .restricted:
            showUnavailable(
                title: "Camera Access Off",
                detail: "Enable camera access to send a photo request."
            )
```

変更後（各 `showUnavailable(...)` の直後に `onPermissionDenied?()` を追加）:

```swift
                } else {
                    DispatchQueue.main.async {
                        self.showUnavailable(
                            title: "Camera Access Off",
                            detail: "Enable camera access to send a photo request."
                        )
                        self.onPermissionDenied?()
                    }
                }
            }
        case .denied, .restricted:
            showUnavailable(
                title: "Camera Access Off",
                detail: "Enable camera access to send a photo request."
            )
            onPermissionDenied?()
```

- [ ] **Step 4: コンポーザ状態に alert フラグを追加**

変更前（`private let minuteOptions = ...` の行）:

```swift
    private let minuteOptions = [5, 10, 15, 20, 30, 45, 60]
```

変更後（直後に追加）:

```swift
    private let minuteOptions = [5, 10, 15, 20, 30, 45, 60]
    @State private var isShowingCameraSettingsAlert = false
```

- [ ] **Step 5: `captureStep` でコールバックを配線し、設定誘導アラートを出す**

変更前（`captureStep` の UIKit ブランチ）:

```swift
        #if canImport(UIKit)
        FriendRequestCameraCaptureView { image in
            acceptCapturedPhoto(image)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea(edges: .bottom)
        #else
```

変更後:

```swift
        #if canImport(UIKit)
        FriendRequestCameraCaptureView(
            onPermissionDenied: {
                isShowingCameraSettingsAlert = true
            },
            onImage: { image in
                acceptCapturedPhoto(image)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea(edges: .bottom)
        .alert("Camera Access Off", isPresented: $isShowingCameraSettingsAlert) {
            Button("Open Settings") {
                openCameraSettings()
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Photo requests need camera access. Turn it on for Deny in Settings.")
        }
        #else
```

- [ ] **Step 6: `openCameraSettings()` ヘルパを追加**

挿入位置: `FriendApprovalRequestView` 内、`returnToCamera()` の `#if/#else` ブロック付近（`requestImage(from:)` の直後など、struct 内であればよい）。

```swift
    private func openCameraSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
```

- [ ] **Step 7: ビルド確認（Xcode）** — ⌘B。型エラーなし。
- [ ] **Step 8: 手動確認（実機推奨／シミュレータ）**

1. カメラ権限を一度拒否 → `Ask Friends` でカメラステップに入ると「Camera Access Off」アラートが出る。
2. 「Open Settings」で設定アプリの当該アプリ画面が開く。「Not Now」で閉じる。
3. 設定でカメラを許可 → 再度開くと通常どおり撮影できる。

- [ ] **Step 9: コミット**

```bash
git add ScreenTimeSharing/Views/DashboardView.swift
git commit -m "Offer a Settings shortcut when camera access is denied

The camera step dead-ended on a blur card with no recovery path. Surface a
permission-denied callback and present an alert that deep-links to Settings so
users can re-enable the camera for photo requests."
```

---

## Task C: 最終確認

- [ ] **Step 1: 差分レビュー**

Run: `git diff feature/phase0-request-button-ux --stat`
Expected: 変更は `Sources/ScreenTimeSharingCore/BlockingModels.swift` / `Tests/ScreenTimeSharingCoreTests/BlockingModelsTests.swift` / `ScreenTimeSharing/AppModel.swift` / `ScreenTimeSharing/Views/DashboardView.swift` の 4 ファイル（+ `docs/`）。`BlockingSettingsView.swift` / `RootView.swift` / Shield 拡張は**無変更**。

- [ ] **Step 2: コアテストの最終確認**

Run: `swift test`
Expected: 全 PASS（新規 `pendingSentFriendRequestsAreGroupScopedAndPendingOnly` を含む）。

- [ ] **Step 3: 受け入れ基準（spec §A-6 / §B-5）との突き合わせ**

- [ ] F3: メッセージ欄が遅くとも Step2(Review) で到達できる。
- [ ] F4: 申請ステータス（保留件数）が詳細を開かず Home の `Ask Friends` 上で見える。
- [ ] F5: 途中離脱しても同一起動中は写真を再撮影せず再開できる。
- [ ] F6: 初見ユーザーに核心機能のコーチマークが一度だけ出る。
- [ ] F7: 分数選択近くに「短い申請ほど承認されやすい」ヒントがある。
- [ ] F8: 申請ボタン/送信ボタン/フレンド行の a11y が具体化されている。
- [ ] S1: Shield→申請の往復が実機で動作する（B1 チェック済み）。
- [ ] S5: 無効グループの導線が「設定で有効化」へ誘導される。
- [ ] B2: カメラ拒否時に設定への導線がある。
- [ ] 4 ファイル（+docs）以外に変更がない（サージカル）。

- [ ] **Step 4: ユーザーへ結果提示**（Codex の出力を verbatim で提示し、適用可否を確認 — CLAUDE.md）

---

## Self-Review（計画著者による点検）

- **Spec coverage:**
  - §A-5 項目3（メッセージ前出し）= A2 / 項目4（送信中バッジ）= A4 / 項目5（下書き復帰）= A3 / 項目6（初回コーチマーク）= A5 / 項目7（分数ヒント）= A2 / 項目8（a11y）= A1+A4。
  - §B（#7）: 項目1（実機確認）= B1 / S2 隣接（カメラ拒否誘導）= B2 / S5（無効ガイダンス）= A4 に内包。**S4（URLスキーム）と項目「Shield起点フラグ」は確定判断で見送り**（B0 で自動カメラ到達が既存、URL は通知タップで代替）。
- **Placeholder scan:** 「TBD / 適切に処理」等なし。すべて exact な before/after を提示。F5 の下書き、A4 のコア関数は完全コードを記載。
- **型/シンボル整合:**
  - `AppModel.FriendRequestDraft`（A3 で定義）を A3 の `persistDraftIfNeeded()` で同名参照。
  - `BlockingStateResolver.pendingSentFriendRequests(forAny:inGroup:in:)`（A4-1 で定義）を A4-2 の AppModel computed で同シグネチャ呼び出し、A4-1 のテストでも同シグネチャ。
  - `pendingOutgoingFriendRequestCount(for:)`（A4-2）を `friendRequestButton(for:)`（A4-3）で同名呼び出し。
  - `viewedGroup`（既存 `@State`）/ `friendRequestGroup`（既存）/ `currentFriendIdentityIDs`（既存）/ `isSent(byAny:)`（既存）に依存。新規シンボルは上記 3 つ（Draft 構造体・コア関数・AppModel computed）＋ View 内 helper（`restoreDraftIfAvailable`/`persistDraftIfNeeded`/`openCameraSettings`/`askFriendsCoachmarkCard`/`showsAskFriendsCoachmark`）＋ `@State`（`didSendRequest`/`isShowingCameraSettingsAlert`）＋ `@AppStorage`（`hasSeenAskFriendsCoachmark.v1`）。
- **同一ファイル編集の順序:** DashboardView は A1(送信/行a11y)→A2(reviewStep/Request/keyboard gate)→A3(状態/ライフサイクル/sendRequest)→A4(friendRequestButton)→A5(BlockingOverviewCard)→B2(カメラ)。各タスクの編集領域は重複せず、before スニペットは前タスクの after で無効化されない。
- **`requesterID` がオプショナル:** `BlockFriendRequest.requesterID: String?`。F4 は `isSent(byAny:)`（既存ヘルパ）経由で判定するため直接比較せず、オプショナルでも安全。
- **スコープ:** 単一の実装計画に収まる（4 ファイル + テスト + docs、View 中心 + コア関数1）。

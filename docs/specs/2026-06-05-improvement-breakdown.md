# Deny / ScreenLog 改善ブレイクダウン

| 項目 | 内容 |
|---|---|
| 作成日 | 2026-06-05 |
| 対象ブランチ（現状基準） | `origin/product/accountability-locks` |
| ステータス | v1.2（コード再確認による #7 の訂正を反映） |
| スコープ | ユーザー指定の7改善領域の詳細ブレイクダウン（**実装計画ではなく要件・設計の分解**） |
| 補足 | 本書のファイル参照・行番号は枝コードの静的解析時点の概算。実装着手時に再確認すること。 |

---

## 0. はじめに（この文書の前提）

ユーザーから提示された7つの改善要望を、**現行プロダクトのコードに対して**詳細に分解したもの。

> ⚠️ **重要な認識:** これらの機能の大半は **既に実装済み** であり、改善の本質は「新規開発」ではなく **既存実装の磨き込み（UX/導線/性能）** である。`main` は初期プロトタイプで本体機能を含まないため、本書はすべて `accountability-locks` 枝を「現状」として記述する。

### 要望と本書セクションの対応

| 要望（ユーザー原文） | 本書ID | セクション |
|---|---|---|
| タイムリクエスト + タイムリクエストボタンがわかりづらい | #2 / #6 | [A](#a-タイムリクエスト体験-23-最優先) |
| ブロックされたアプリのブロック画面に「友達に申請する」ボタン | #7 | [B](#b-ブロック画面からの申請ボタン-7-クイックウィン) |
| アプリ初回の使い方・コンセプトのオンボーディング | #5 | [C](#c-オンボーディング-5) |
| データ表示(home/stats)が毎度ロードしてる | #3 | [D](#d-homestats-のロード性能-3) |
| フレンドのスクリーンタイムを一覧表示 | #4 | [E](#e-フレンドのスクリーンタイム一覧-4) |
| フレンド申請 | #1 | [F](#f-フレンド申請add-friend-1) |

---

## 1. 現状プロダクトの全体像

### 1.1 コンセプト（コアループ）

生産性のためのアプリブロッカー。**フック = ブロック中のアプリで追加時間が欲しいとき、自撮りの「お願い写真（begging photo）」＋「X分」の申請を友達に送り、友達がフィードで承認/拒否する。** 承認されると申請秒数だけ一時的にアンロックされる。

```
アプリをブロック → 開こうとするとShield画面 → 「友達に申請」
  → 自撮り＋分数＋メッセージ → 送信(CloudKit + Push)
  → 友達のFeedに表示 → 承認/拒否 → 承認なら time collect でアンロック
```

### 1.2 技術スタック / ターゲット構成

- **App（SwiftUI）:** `ScreenTimeSharing` 本体
- **App Extensions（Xcode管理、SPMターゲットではない）:**
  - `ScreenLogShieldConfigurationExtension` — ブロック画面（Shield）の見た目
  - `ScreenLogShieldActionExtension` — Shieldのボタン押下処理
  - `ScreenLogActivityMonitorExtension` — ブロック発火監視
  - `ScreenLogDeviceActivityReportExtension` — スクリーンタイム集計
- **Core（SPM）:** `ScreenTimeSharingCore` — モデル/集計/コーデックのユニットテスト対象
- **Widget:** `ScreenTimeSharingWidget`（friend usage / stats）
- **バックエンド:** `push-server/`（Cloudflare Worker、APNs中継）、CloudKit（共有レコード/ゾーン）、Apple Sign In（ID基盤）、サブスク課金（`SubscriptionService`）

### 1.3 情報設計（IA）— 5タブ構成

| タブ | 主担当View | 内容 |
|---|---|---|
| **Home/Today** | `DashboardView` | `TodayScreenTimeCard` / `HomeROICard` / `BlockingOverviewCard`（各ブロックグループの行＋申請ボタン） |
| **Stats** | `StatsView` | 期間セレクタ（日/週/月）＋使用量サマリ＋時間帯チャート |
| **Feed** | `RequestFeedView`（`BlockingSettingsView.swift`内） | 受信した申請の写真スタック＋ログ。承認/拒否/collect |
| **Friends** | `FriendsView` | リーダーボード（申請時間順）＋フレンド使用量リスト |
| **Profile/Settings** | `SettingsView` | プロフィール/外観/アカウント復元/サブスク |

**ゲーティング:** `RootView` で `hasCompletedOnboarding` → `OnboardingView`、次に `isAuthenticated` → `SignInGateView`（Apple Sign In）、その後 `AppTabs`。

**中央状態:** `AppModel`（`@MainActor`, `ObservableObject`）が `blockingState` / `friendSummaries` / `leaderboardEntries` / `profile` 等を保持。`ScreenTimeSharingApp.onAppear` で `model.load()`。

---

## 2. 改善サマリ & 優先度

| ID | 領域 | 種別 | 現状実装度 | 規模 | 優先度 |
|---|---|---|---|---|---|
| **#2/#6** | タイムリクエスト体験・導線 | UX改善 | 機能は完成、導線が脆弱 | S〜M（複数） | **P0（ユーザー指定の最優先）** |
| **#7** | ブロック画面の申請ボタン | 磨き込み | **コア結線は完了済み（要・実機動作確認）** | 残: S（任意） | P1 |
| **#5** | オンボーディング | コンテンツ追加 | 6ページ実装済みだがコア機構を未説明 | M | P1 |
| **#3** | home/stats のロード性能 | パフォーマンス | キャッシュ層なし | M〜L | P1 |
| **#4** | フレンドのスクリーンタイム一覧 | UX再設計 | リーダーボード＋使用量リストが分裂 | M | P2 |
| **#1** | フレンド申請（招待リンクUX） | UX改善 | CloudKit共有リンクのみ（サーバ拡張なし） | S〜M | P2 |

> **重要な訂正（2026-06-05 コード再確認）:** #7 の「Shield→申請コンポーザ」の結線は **既に完了**していた（`RootView.swift` L33-44 の `.sheet`）。当初「欠落」とした調査結論は誤り。#7 は新規実装ではなく **動作確認＋任意の磨き込み** が対象。よって Phase 0 の中心は **#2/#6 のボタンUX改善** となる。

---

## A. タイムリクエスト体験（#2/#6）★最優先

### A-1. 現状（as-is）

タイムリクエストは**3ステップのモーダルで完全実装済み**。

- **Step 1 Capture:** 全画面カメラ `FriendRequestCameraCaptureView`。`FriendRequestBeautyRenderer` が `CIDetector` で顔検出し軽い美顔補正（明度 +0.006 / 彩度 ×1.01 / コントラスト −0.995）。
- **Step 2 Review:** 撮影画像プレビュー（4:5）。「撮り直す / 続ける」。
- **Step 3 Details:** 写真サムネ＋**分数ピッカー**（`RequestMinuteCarouselPicker`、選択肢 `[5,10,15,20,30,45,60]`、デフォルト15、ハプティクスあり）＋**任意メッセージ**＋**フレンド選択**（チェックトグル）＋**送信**（写真と最低1名選択まで `canSendRequest` で無効化）。
- **送信ロジック:** `AppModel.requestFriendTime`（写真を ~1400px/JPEG82% で保存 → `BlockFriendRequest` 生成 → `blockingState.friendRequests` 先頭に挿入 → `PushServerClient.notify()` でAPNs → `CloudKitUsageSnapshotStore.publishFriendRequest*` で private/shared ゾーンに配信）。
- **受信〜承認:** 友達は `RequestFeedView` の写真カルーセルで受信 → `FriendRequestDetailView` で承認/拒否 → 申請者にPush返信 → 申請者は status `.approved` で「Collect Time」→ `collectFriendRequest` でアンロック。
- **ライフサイクル:** `BlockRequestStatus`（pending → approved/denied → collected/expired）。pending失効・collection失効（承認後1時間など）あり。

### A-2. 現状の申請開始エントリーポイント（4箇所・すべて弱い）

| # | 場所 | 表現 | 問題 |
|---|---|---|---|
| 1 | Home `BlockingOverviewCard` | 高さ32pxの小さな「Request」カプセル（`hands.sparkles.fill`）、`Unblock X/Y` の隣 | タップ領域が小さく、`Unblock` の方が目立つ。「Request」だけでは写真フローと分からない |
| 2 | ブロック詳細のダミープレビュー | 「Request time from friends」ボタン | グループ詳細にドリルダウンしないと見えない |
| 3 | **Feed タブ** ツールバー | **アイコンのみ**の `hands.sparkles.fill` | Feedを開く必要＋アイコンのみで意味不明＋確認ダイアログ（グループ選択）で手数が多い |
| 4 | Settings/Blocking | グループ行のインラインボタン | Dashboardと重複し、導線が不明瞭 |

### A-3. 課題（#6 の核心）

1. **ラベルが汎用すぎる**：「Request」では「自撮りして友達にお願いする」と伝わらない。
2. **導線が分散**：4箇所に散り、初見ユーザーはどこを見ればよいか分からない。最頻機能なのに第一級の扱いになっていない。
3. **配置が窮屈**：Homeのカプセルは横並びHStackに押し込まれ、`minimumScaleFactor(0.72)` で文字が縮む可能性。
4. **ブロック中の即時CTAがない**：ブロック画面（Shield）から直接申請に飛べない（→ #7 で解決）。
5. **メッセージ欄がStep3に埋没**：個人的な「お願い文」を書けることに気づきにくい。
6. **下書き/復帰なし**：途中離脱で撮影写真が消える。

### A-4. 改善ゴール

- 初見ユーザーがHomeを見て **30秒以内**にタイムリクエスト機能を発見できる。
- 申請のプライマリCTAが **Homeに第一級**で存在し、ラベルだけで「写真でお願いする」が伝わる。
- ブロック中の文脈（Shield）からも開始できる（#7連携）。
- アイコンのみ・確認ダイアログ経由のような遠回り導線を排除。

### A-5. UX案

1. **プライマリCTAの刷新（Effort S）** — `friendRequestButton` のラベルを「Request」→**「友達に時間をお願い」/「Ask Friends」**へ。フル幅〜半幅のpill、グループ行の上部に主役配置、`Unblock` は副次扱い。`filesToTouch: DashboardView.swift（friendRequestButton 付近 L975）`
2. **Feedタブの役割明確化（Effort S）** — Feedツールバーの申請作成アイコンを撤去し、Feedは**受信専用**に。タブアイコンを `tray.and.arrow.down.fill`、ラベル「申請」へ。「送る＝Home、受け取る＝Feed」のメンタルモデルに統一。`RootView.swift（AppTab.feed）` / `BlockingSettingsView.swift（RequestFeedView toolbar L101-106）`
3. **メッセージ欄の前出し（Effort M）** — メッセージ入力をStep3→**Step2 Review**へ移動し、写真と一緒に「お願いパッケージ」を組ませる。
4. **送信中バッジ（Effort M）** — 申請ボタンに「1件保留中」バッジを表示し再エンゲージを促す。`AppModel` に保留申請数の computed を追加。
5. **下書き/復帰（Effort M）** — 撮影写真を一時保持し、数分以内の再開で再撮影不要に。
6. **初回コーチマーク（Effort M）** — friendRequest有効グループを初作成した直後、`BlockingOverviewCard` に「行き詰まったら友達に時間をお願いできます」カードを1回だけ表示。
7. **分数選択時のヒント（Effort S）** — 「短い申請ほど承認されやすい（5〜15分）」の補足を表示。
8. **アクセシビリティ強化（Effort S）** — 申請ボタンの `accessibilityLabel` を具体化。

### A-6. 成功基準（検証可能）

- [ ] Homeを見た初見ユーザーが外部説明なしで申請機能を発見できる（アイコンのみボタンを主導線から排除）。
- [ ] 申請CTAがHome（プライマリ・テキスト明示）に存在し、`Ask`/`友達`/`写真` 等の語を含む2〜3語ラベル。
- [ ] プライマリボタン→カメラ起動が**2秒以内・確認ダイアログ0**。
- [ ] メッセージ欄が遅くともStep2までに到達可能。
- [ ] 申請ステータス（pending/approved/...）がHomeまたはFeedで詳細を開かずに見える。
- [ ] （計測可）UI変更後2週間で申請機能の利用が増加し、承認率は悪化しない。

### A-7. 依存・iOS制約

- フレンドが0だと申請不可 → **#1（フレンド申請）と #5（オンボーディングで初回フレンド獲得）に依存**。
- カメラ権限（`NSCameraUsageDescription`）。拒否時はカメラ非表示のフォールバック。
- 写真はCloudKit 4MB制限のため 1400px/JPEG82% に圧縮。端末ローカル保存で**端末間ローミングなし**（同一端末で承認前提）。
- Push未許可/DND時は配信保証なし。

---

## B. ブロック画面からの申請ボタン（#7）★クイックウィン

### B-1. 現状（as-is）— **コア機構は実装済み**

iOSのShield（`ManagedSettings` のシステムオーバーレイ）に、**すでに「Request time from friends」セカンダリボタンが存在**し、申請コンポーザまで往復が配線されている。

- `ScreenLogShieldConfigurationExtension`：タイトル/サブタイトル＋プライマリ「OK」＋**セカンダリ「Request time from friends」**（`ShieldCopy.isFriendRequestEnabled` で活性/非活性）。状態は App Group UserDefaults（`group.com.jdco.ScreenLog`）の intent キーを参照。
- `ScreenLogShieldActionExtension`：セカンダリ押下で `queueFriendRequestDraft()` → App Groupに intent を保存（10分で失効 `expirationSeconds = 600`）→ **ローカル通知**（category `shield-friend-time-request`、`userInfo` に groupID）をスケジュール → `.close`。
- 通知タップ：`CloudKitShareAcceptance.swift` のAppDelegateが受信 → `ShieldFriendRequestNotificationCenter.shared.receive(groupID:)`。
- App側：`ScreenTimeSharingApp` 起動時に handler 登録 → `AppModel.openPendingShieldFriendRequestFromNotification(groupID:)`（L1479）→ `loadPendingShieldFriendRequest(preferredGroupID:)`（L1486、intent読込・失効チェック・グループ検証）→ `pendingShieldFriendRequestGroupID` を**セット**。
- **提示（重要）:** `RootView.swift` **L33-44** の `.sheet(item:)` が `model.pendingShieldFriendRequestGroup`（有効＋friendRequest有効を検証する computed、`AppModel` L366）を監視し、非nilで **`FriendApprovalRequestView(group:)` を自動提示**、dismissで `clearPendingShieldFriendRequest()`。→ **Shield→申請コンポーザの往復は完成している。**

### B-2. 課題 — **コア結線は完了。残るは任意の磨き込み**

> **訂正:** 当初調査は「最後のUIバインディングが欠落」としたが、**実コードでは `RootView.swift` L33-44 に既に存在**する。Shield→通知→handler→状態→`.sheet`→コンポーザの往復は**実装済み**。

残る改善余地（いずれも任意・P1以下）:

- Shield起点で開いた時に、その文脈を活かした最適化（`.capture` カメラステップへの自動前進・カメラ権限の先行要求）が未実装。
- Shieldボタン押下直後のアプリ内視覚フィードバックが弱い。
- 通知タップが handler closure 依存（バックグラウンド復帰時の堅牢性は URL スキーム化で改善余地）。
- 複数該当グループ時に Shield ボタンへグループ名を出していない。

**最優先で必要なのは「実機での動作確認」**（コードは揃っているため、まず期待どおり動くかを検証する）。

### B-3. 改善ゴール

ブロックされたアプリを開く → Shieldの「友達に申請」→（通知タップ）→ アプリが申請コンポーザを提示、の往復は**既に動作する想定**。ゴールは、この既存フローを**実機で確認**し、Shield起点の文脈最適化（カメラ即起動・押下フィードバック）で磨くこと。

### B-4. UX案 / 技術タスク

1. **【まず実施】既存フローの実機動作確認** — `RootView.swift` L33-44 の `.sheet` は実装済み。新規結線ではなく、Shield押下→通知→コンポーザ提示が実機で期待どおり動くかを検証する。
2. **Shield起点フラグでカメラ即起動（Effort M）** — Shield経由で開いた場合は `openedFromShield` フラグを渡し `.capture` ステップへ自動前進＋カメラ権限を先行要求。
3. **Shield押下時の視覚フィードバック（Effort S）** — `ShieldCopy` の「Request ready / 通知をタップして写真を撮ってください」状態を押下直後に確実に反映。
4. **URLスキームでのディープリンク化（Effort M）** — handler closure依存をやめ `screenlog://shield-request?groupID=...` でルーティングし、バックグラウンド復帰に強くする。`CloudKitShareAcceptance.swift` / `ScreenTimeSharingApp.swift`
5. **無効時のガイダンス（Effort S）** — `friendRequestConfig.isEnabled` が false の時にボタンを明確に無効化、または「設定で友達申請を有効化」を案内。

### B-5. 成功基準

- [ ] Shieldセカンダリ押下 → intentがApp Group保存 → ローカル通知発火。
- [ ] 通知タップ → `pendingShieldFriendRequestGroupID` セット → **アプリが自動で `FriendApprovalRequestView` を該当グループ・`.capture` で提示**。
- [ ] 送信/キャンセルで状態クリア。再度Shieldから再開可能。
- [ ] 全グループで friendRequest 無効なら Shield ボタンが視覚的に無効。
- [ ] groupIDが無効（削除/無効化）なら簡潔なエラー表示後にクリア。

### B-6. iOS制約（重要）

- Shield拡張は**別プロセス（XPC）**。メインアプリと直接IPC不可、**通信はApp Group UserDefaultsのみ**。
- ShieldはUI（UIView/SwiftUI/カメラ/写真ピッカー）を一切提示不可。撮影は必ずメインアプリ側。
- Shieldからの通知は**ローカル通知**（push不可）。アプリ終了に耐えるが、**端末再起動でタップ前に消える**。
- 全拡張・本体に App Group（`group.com.jdco.ScreenLog`）と FamilyControls エンタイトルメントが必要。メモリ/実行時間が厳しいため Shield 内で重い処理は不可。

### B-7. 未確認事項

- Shield経由でコンポーザを開いた際、グループ選択をロックすべきか（現状は任意グループに変更可）。
- 複数グループ該当時のShieldボタン文言（現状グループ名なし）。
- 10分失効をユーザー設定可能にするか。

---

## C. オンボーディング（#5）

### C-1. 現状（as-is）

`OnboardingView` に**6ページ実装済み**：① 年齢スライダ ② 1日スクリーンタイム見積 ③ 浪費時間の算出表示 ④ フレンド見守りコンセプト（"Let a friend monitor you"）⑤ Apple Sign In＋プロフィール作成 ⑥ 最終確認（スクリーンタイム権限付与）。

別枝 `origin/feature/multi-page-onboarding` では Apple Sign In ページを **アプリ選択（`AppPickerPage`、3アプリ）** に差し替えている（WIP）。

### C-2. 課題

1. **コア機構を説明していない（最大ギャップ）**：④は「友達に見守ってもらう」一般論のみで、**「自撮り→X分申請→友達が承認/拒否→承認で一時アンロック」というこのアプリの肝を一度も説明しない**。
2. **ブロックするアプリ選択がオンボーディングにない**：`FamilyActivityPicker` は完了後の `BlockingSettingsView` 内。何を選んだか曖昧。
3. **フレンドがオンボーディング中に増えない**：完了後にFriendsタブで招待リンクを作る必要。誰を招待するかの誘導もなし。
4. **権限プロンプトが非協調**：スクリーンタイムは最終ページ（OK）だが、**通知権限はアプリ起動時に突然**、カメラ権限は初回撮影時に突然。
5. **写真要件の不意打ち**：初めて申請してカメラが出て驚く。
6. **サインイン必須の価値が伝わらない**：ページ⑤で未認証だと進めない（`isPrimaryDisabled`）。必須自体は方針として維持するが、**なぜ必要かの説明が乏しく離脱要因**になりうる。

### C-3. 改善ゴール

- 完了直後のユーザーがコア機構を自分の言葉で言える：「写真を撮って友達に時間をお願いし、相手が承認するとアンロックされる」。
- 完了から**初回申請までの体験を3分以内**に、追加タップ最小で到達。

### C-4. UX案 / 技術タスク

1. **「使い方」ページ追加（Effort M）** — ④の後に1〜2ページ挿入し、**自撮り→分数→友達が写真付きで受信→承認/拒否→アンロック**をモック/ステップ図で具体化。`OnboardingView.swift`
2. **サインイン前の価値訴求（Effort S）** — **サインインは必須のまま（ゲスト開始は不可）**。代わりにサインインページの直前に「なぜ必要か（フレンド/同期/復元）」を1画面で説明し、離脱を減らす。`OnboardingView.swift`
3. **アプリ選択をオンボーディングに統合（Effort L）** — multi-page-onboarding枝の `AppPickerPage` を発展させ、`FamilyActivityPicker` で2〜3アプリ選択→最終ページで `BlockGroup` 生成。
4. **完了後ガイド（Effort M）** — フレンド0/グループ0なら「① 友達を招待 ② ブロックするアプリを選ぶ」のボトムシートを提示。`RootView.swift`
5. **権限の協調（Effort M）** — 最終ページでスクリーンタイム/カメラ/通知を順に説明・要求（カメラ/通知はスキップ可、スクリーンタイムは必須）。
6. **スクリーンタイム認可失敗のハンドリング（Effort S）** — 失敗時はインラインエラー＋「再試行」。未認可のまま完了させない（または警告付きスキップ）。
7. **Quick Startカード（Effort M）** — 完了後Home上に「3ステップで初回申請」の折り畳みガイド。

### C-5. 成功基準

- [ ] 完了後ユーザーがコア機構を説明できる。
- [ ] お願い写真フローがプロフィール設定の**前に**テキスト/モックで説明される。
- [ ] サインインは必須のまま、直前に必要性が説明され離脱が抑えられている。
- [ ] アプリ選択がオンボーディング内で完了、または完了後ガイドで誘導。
- [ ] スクリーンタイム/カメラ/通知が最終ページで論理的順序に要求され、起動後の不意打ちなし。

### C-6. 依存

- #1（フレンド申請）— オンボーディング内で初回フレンドを獲得させるなら、招待UXの改善が前提。
- #2/#6 — コア機構説明はタイムリクエスト体験と整合させる。

---

## D. home/stats のロード性能（#3）

### D-1. 現状（as-is）— **キャッシュ層なし**

HomeとStatsを開く/操作するたびに**全使用量データを毎回フル再ロード**している。

- **Home（`DashboardView.onAppear`）:** `reloadUsageHistoryFromSharedStorage()` → App Group UserDefaults から全スナップショット `UsageHistoryCodec.decode` → 今日分再構築 → `screenTimeReportRefreshID = UUID()` で `DeviceActivityReport` を再描画。`ScreenTimeLiveTodayReport` が**1秒間隔で最大60秒ポーリング**。
- **Stats（`StatsView.onAppear` ＋ 期間/日付の `.onChange` 毎）:** 同じフル再デコード → `requestScreenTimeReportRefresh()`（UUID再生成で `DeviceActivityReport` をteardown/rebuild）→ `ScreenTimeLiveStatsReport` が再ポーリング。さらに3つの computed（`summary` / `chartBuckets` / `appUsageRows` = `UsageStatsBuilder`）が**毎レンダー再計算**（O(n·m)、メモ化なし）。
- **コスト:** Stats表示1回あたり中央値 **約5〜10秒**（レポート3〜6秒＋デコード＋ビルダー）。期間切替・日付移動のたびに再ポーリングが走り、素早い操作でガタつく。
- 既存の App Group キャッシュ（`AppGroupWidgetCacheWriter` / `WidgetCache`）は**フレンド/リーダーボードのみ**で、使用量統計には適用されていない。

### D-2. 課題

1. 同じ期間を再表示しても全デコード＋3〜6秒のレポートポーリング。
2. 期間切替（日↔週↔月）で `screenTimeReportRefreshID` 再生成 → レポート再構築＋60秒ポーリングを毎回ゼロから。
3. ビルダー3種が毎レンダー再計算（`@State` 依存でジェスチャー毎にも再計算）。
4. データ到着後も60秒ポーリングを継続しCPU/電池を浪費。
5. メインスレッドでの同期デコードが長履歴で100〜500msブロックの恐れ。

### D-3. 改善ゴール

> **方針確定:** stale-while-revalidate（staleバッジ付き即時表示）を採用する。

- Stats初回表示で**前回データを500ms以内に表示**（skeleton/stale badge）し、裏で静かに更新。
- 期間切替**1秒以内**、同一データならレポート再ポーリングなし。
- 直近5〜10分以内に読んだデータは再appearでスピナーを出さない。

### D-4. UX案 / 技術タスク

1. **インメモリ・スナップショットキャッシュ＋TTL（5〜10分）（Effort M）** — `AppModel` にデコード済み `UsageHistoryPayload` と `lastLoadedAt` を保持。新鮮なら再デコードせず即返す。明示更新（pull-to-refresh等）で無効化。`AppModel.swift` / `StatsView.swift` / `DashboardView.swift`
2. **ビルダー出力のメモ化（Effort M）** — `summary/chartBuckets/appUsageRows` を `(range, selectedDate, historyHash)` でキャッシュ。履歴不変なら再計算しない。`StatsView.swift` / `Models.swift`
3. **レポートポーリングの早期終了（Effort S）** — `pollForReportSnapshot` でデータ到着時に即break。`maxLoadingDuration` を2〜3秒へ短縮、未到着ならstale表示。`ScreenTimeReportBridgeView.swift`
4. **日付連打のデバウンス（Effort S）** — `primeStatsReport()` をデバウンス/スロットル（2秒に1回まで）。
5. **デコードのバックグラウンド化（Effort M）** — `UsageHistoryCodec.decode()` を別キューへ。メインスレッドのストール防止。
6. **App Group永続キャッシュへ拡張（Effort L）** — `UsageHistoryCachePayload`（snapshots＋hourly＋lastUpdated＋signature）を `AppGroupWidgetCacheWriter` パターンで保存し、コールドスタート短縮。
7. **stale-while-revalidate UI（Effort M）** — 既知データを即表示（staleバッジ）しつつ裏で更新。
8. **`reportIdentity` 最適化の検証（Effort S）** — 日付変更で不要に `requestScreenTimeReportRefresh()` を呼んでいないか監査し、明示更新時のみUUID再生成に限定。

### D-5. 成功基準

- [ ] Stats再表示で直近5〜10分のデータはスピナーなしで即表示。
- [ ] 期間切替が1秒以内、データ新鮮ならレポート再ポーリングなし。
- [ ] 同一range内の日付移動でデコード/ポーリングを再実行しない。
- [ ] レポートポーリングが日<2秒・週月<3秒で早期終了。
- [ ] 1〜3ヶ月履歴でもメインスレッドストール>100msなし（iPhone 11級）。
- [ ] フレンドデータは使用量統計と独立にロード（レポートが遅くても1秒以内に表示）。

### D-6. 未確認事項（着手前に計測推奨）

- iOSはスクリーンタイム更新を通知するか、ポーリング必須か（→不要なポーリングを置換できる可能性）。
- 典型的な月/年履歴での `decode()` 実コスト（<100ms か >500ms か）。
- 60秒ポーリングは本当に必要か、5秒＋指数バックオフで足りるか。

---

## E. フレンドのスクリーンタイム一覧（#4）

### E-1. 現状（as-is）

`FriendsView` は**2つのセクションに分裂**：

1. **リーダーボード** — `StatsBoardBuilder.mostExtraRequested()` で**「申請した追加時間」順**にランキング（`FriendLeaderboardCard/Row/Bar`、週/全期間セレクタ）。出典は `leaderboardEntries`（`AccountabilityEvent` 由来）。
2. **フレンド使用量リスト** — `FriendSummaryRow`（アバター/名前/総使用時間/選択アプリ時間/staleバッジ）。出典は `friendSummaries`（CloudKit共有ゾーンの最新 `DailyUsageSnapshot`）、`lastUpdated` 降順。

### E-2. 課題

1. **2系統の分裂**：リーダーボード（申請量）とフレンド使用量（スクリーンタイム）で**出典・並び・鮮度がバラバラ**。ユーザーが頭の中でマージする必要。
2. **リーダーボードが「申請時間順＝ネガ指標」**：追加時間を多く要求した人が上位＝「シェイム」寄り。サブタイトルに拒否数も出て批判的。
3. **鮮度表示が弱い**：staleはフレンド使用量行のオレンジバッジのみ。リーダーボードに鮮度なし。「最終同期X分前」がどこにもない。
4. **フレンド詳細なし**：行タップで何も起きない。プロフィール/履歴に遷移不可。
5. **管理UXなし**：unfriend/mute/block不可。
6. **ウィンドウ選択が非永続**：再起動/タブ切替でリセット。ローカル後フィルタで非効率。

### E-3. 改善ゴール

> **方針確定:** リーダーボードのランキングは現行の「申請時間順」を維持する。

「フレンドのスクリーンタイムを**一覧で**見たい」という要望に直接応える、**単一の統合フレンドリスト**を提供。鮮度が一目で分かり、行タップで詳細に入れる。

### E-4. UX案 / 技術タスク

1. **統合フレンドリスト（Effort M）** — リーダーボードと使用量リストを1ビューに統合し、**モード切替**（「アクティビティ＝スクリーンタイム順」/「リーダーボード＝申請時間順（現行維持）」）。共通カードデザイン。`FriendsView.swift` / `AppModel.swift`
2. **鮮度インジケータの常設（Effort S）** — 全行に「最終更新X分前」。色分け（緑<5分/黄5-60分/橙>1時間）。ヘッダ/フッタに「最終同期」＋「今すぐ同期」。`FriendsView.swift` / `AppModel.swift（lastSyncedAt, isSyncing）`
3. **（対象外）ポジティブ・リフレーミング** — 「申請時間順」を維持する方針のため、ストリーク/承認時間中心への転換は**今回は行わない**。
4. **フレンド詳細View（Effort L）** — 行タップで `FriendDetailView`（プロフィール/各期間スタッツ/申請履歴＋写真/承認タイムライン/アクション）。
5. **ウィンドウ選択の永続化＋サーバ側フィルタ（Effort M）** — 選択を UserDefaults 保存、CloudKit述語で期間絞り込み、各ウィンドウを起動時プリフェッチ。
6. **フレンド管理（Effort M）** — スワイプ/長押しで unfriend / mute / block。

### E-5. 成功基準

- [ ] フレンドが単一の統合ビューで、ソート/フィルタ切替可能（2セクションのマージ不要）。
- [ ] 全行に鮮度インジケータ、ヘッダ/フッタに最終同期。
- [ ] 行タップで詳細（プロフィール/履歴/スタッツ/アクション）に遷移。
- [ ] ランキングは現行の申請時間順を維持しつつ、鮮度と詳細導線が改善されている。
- [ ] `FriendsView` がアプリ起動後1秒以内に表示（キャッシュ/プリフェッチ）。

### E-6. iOS制約

- フレンドのスクリーンタイムは**相手端末のDevice Activity許可に依存**。未許可なら `ScreenTimeCapability.unavailable`。
- CloudKit共有ゾーンは受諾後に相手の将来スナップショットを全取得。粒度別許可なし。unfriendはゾーン削除が必要。
- アバターはCloudKitのDataフィールド（最大4MB）。事前縮小はクライアント責務。

---

## F. フレンド申請（Add Friend, #1）

### F-1. 現状（as-is）

**CloudKit共有リンク方式のみ**。

1. `FriendsView`/`SettingsView` の「Invite Friends」→ `CloudShareSheet`（作成中 → URL準備完了で「Share Invite（`UICloudSharingController`）/ Copy Link」）。
2. 実体は `CloudKitUsageSnapshotStore.prepareProfileShare()`：招待ごとにUUIDの pairwise「channel」を作成し、リンク共有用 `CKShare` を生成。
3. 招待される側がリンクを開く → `ShareAcceptingSceneDelegate` が `CKShare.Metadata` を捕捉 → `acceptFriendShareInvite()`（ゾーン永続化＋ミラー書き戻し＋ `reloadFriends()`＋招待者へPush）。
- ID基盤は **Apple Sign In**（`appleUserID` を `UserProfile` に永続化、再インストール時に `fetchExistingProfile` で復元）。

### F-2. 課題

1. **アプリ内ディレクトリ/名簿がない**：名前/メール/電話で検索・追加できず、毎回リンクを作って外部送信する儀式が必要。
2. **保留中招待の可視化がない**：送信済み/受信済み/承認済みの区別、再送なし。
3. **連絡先サジェスト/一括招待なし**。
4. **Apple Sign In依存の制約**：唯一のID基盤。Apple ID喪失時の復元手段なし。

### F-3. 改善ゴール

> **方針確定:** サーバ側ディレクトリは新設しない。CloudKit共有リンク方式の枠内で体験を磨く。

招待リンクのフローを、**送信/受信/承認の状態が見える・再送できる**形にし、儀式感を減らす。

### F-4. UX案 / 技術タスク

1. **招待状態の可視化（Effort M）** — 「送信済み招待」「受信済み招待」「承認済みフレンド」を区別して一覧表示。`CloudShareSheet` の単発フローを、状態を持つ招待リストへ拡張。`FriendsView.swift` / `AppModel.swift`
2. **保留招待の再送・取消（Effort S〜M）** — 未承認の招待を再送・取消、リンク再生成。`CloudShareSheet.swift` / `CloudKitUsageSnapshotStore.swift`
3. **招待リンク導線の改善（Effort S）** — 招待ボタンの発見性向上、共有→コピーの手数削減、QR表示など共有リンクの提示方法を改善。`FriendsView.swift` / `CloudShareSheet.swift`
4. **（参考・対象外）** メール/ユーザー名検索・連絡先サジェストは**サーバ側ディレクトリ前提のため今回スコープ外**。

### F-5. 成功基準

- [ ] 送信済み/受信済み/承認済みの招待状態が明確に区別して表示される。
- [ ] 未承認の招待を再送・取消できる。
- [ ] （オンボーディング統合時）完了後2タップ以内で招待ボタンに到達。

### F-6. iOS制約 / 依存

- CloudKitコンテナID固定（変更は全共有破壊＋移行必要）。
- Apple Sign Inが唯一のID。**サーバ側ディレクトリは新設しない方針のため、「メール/名前で検索追加」は実現しない**（共有リンク方式を維持）。
- #5（オンボーディング）での初回フレンド獲得と密接に連携。

---

## 3. 横断的事項（共通基盤）

複数領域に効く基盤的改善。本書のスコープ外だが、上記タスクの土台として記録。

| 項目 | 効く領域 | 概要 |
|---|---|---|
| **通知の統合インボックス** | #2/#6, #1, IA | 3つの通知センター（`CloudKitShareAcceptanceCenter` / `FriendRequestNotificationCenter` / `ShieldFriendRequestNotificationCenter`）と `RootView` の複数 `.sheet` を、単一の `ActionNotificationCenter`＋インボックスに集約。 |
| **準リアルタイム同期** | #2/#6, #4 | 15秒ポーリングをCloudKitサブスクリプション/push-serverのwebhookに置換し、承認/拒否を数秒で反映。 |
| **使用量のキャッシュ基盤** | #3, #4, Widget | App Group永続キャッシュ（既存のWidgetCacheパターン）を使用量履歴にも展開。 |
| **ブランド（確定: 現状維持）** | — | 表示名 **「Deny」** のまま（`ScreenTimeSharing/Info.plist` CFBundleDisplayName）。内部 `PRODUCT_NAME=ScreenTimeSharing`／拡張 `ScreenLog*` も現状維持。識別子整合作業は**不要**（2026-06-05 判断）。 |

---

## 4. 推奨実装順序（フェーズ案）

> あくまで提案。承認後に各フェーズを `writing-plans` で実装計画化する。

- **Phase 0（クイックウィン, ~数時間）**
  - **#7 動作確認** Shield→申請コンポーザの既存フローを実機で検証（コードは結線済み、新規実装なし）。
  - **#2/#6-1** Homeの申請ボタン改称・主役化（`friendRequestButton(for:)` の "Request"／`hands.sparkles.fill` 小カプセル）（Effort S）。
  - **#2/#6-2** Feedの申請作成ツールバーボタンを撤去し受信専用化（タブアイコンは既に `tray.full`）（Effort S）。
- **Phase 1（コア体験, 最優先領域）**
  - **#2/#6** 残り（メッセージ前出し/バッジ/下書き/コーチマーク）。
  - **#7** カメラ即起動・フィードバック・ディープリンク化。
- **Phase 2（定着・性能）**
  - **#5** オンボーディングに「使い方」ページ＋権限協調＋（任意）サインイン。
  - **#3** インメモリキャッシュ＋ビルダーメモ化＋ポーリング早期終了。
- **Phase 3（ネットワーク拡張）**
  - **#4** フレンドリスト統合＋鮮度＋詳細View。
  - **#1** 招待リンクUX改善（送信/受信/承認の状態＋再送/取消）。
  - 横断: 通知インボックス統合 / 準リアルタイム同期。

---

## 5. 決定事項と残論点

### 5.1 確定済み（2026-06-05 ユーザー判断）

1. **#1 フレンド申請**: サーバ側ディレクトリは**新設しない**。CloudKit共有リンク方式を維持し、改善は**招待リンク体験の磨き込み（状態表示/再送/取消）に限定**。メール/ユーザー名検索は対象外。
2. **#5 Apple Sign In**: **ゲスト開始は許容しない**。サインインはオンボーディングの必須ステップのまま（直前の価値訴求で離脱を抑える）。
3. **#4 リーダーボード**: 現行の**「申請時間順」を維持**。ストリーク/承認時間への転換は行わない（統合/鮮度/詳細Viewの改善は実施）。
4. **ブランド**: 現行の表示名 **「Deny」** のまま。識別子整合作業は**不要**。
5. **#3 stale表示**: 「staleバッジ付き即時表示（stale-while-revalidate）」を**採用**。Stats/Homeは前回データを即時表示し、裏で更新する。

### 5.2 着手方針

全確認事項は確定。**Phase 0 から着手**する。ただし #7 はコア結線が完了済みのため新規実装ではなく**実機動作確認**とし、実体のある作業は **#2/#6 のHomeボタン改称・Feed受信専用化** が中心。

---

## 付録: 主要ファイル早見表（accountability-locks 枝）

| 領域 | 主ファイル |
|---|---|
| IA/状態 | `ScreenTimeSharing/Views/RootView.swift`, `AppModel.swift`, `ScreenTimeSharingApp.swift` |
| タイムリクエスト | `Views/DashboardView.swift`（`FriendApprovalRequestView`, camera, `RequestMinuteCarouselPicker`）, `Views/BlockingSettingsView.swift`（`RequestFeedView`, `FriendRequestDetailView`）, `Sources/.../BlockingModels.swift`（`BlockFriendRequest`） |
| ブロック画面/Shield | `ScreenLogShieldConfigurationExtension/…`, `ScreenLogShieldActionExtension/…`, `Services/CloudKitShareAcceptance.swift`（`ShieldFriendRequestNotificationCenter`） |
| 配信 | `Services/PushServerClient.swift`, `Services/CloudKitUsageSnapshotStore.swift`, `push-server/` |
| home/stats | `Views/StatsView.swift`, `Views/ScreenTimeReportBridgeView.swift`, `Services/ScreenTimeReportContext.swift`, `Sources/.../ScreenTimeReportStorage.swift`, `Sources/.../Models.swift`（`UsageStatsBuilder`） |
| フレンド/リーダーボード | `Views/FriendsView.swift`, `Sources/.../AccountabilityModels.swift`（`LeaderboardBuilder`）, `Services/CloudShareSheet.swift`, `Services/AppleSignInService.swift` |
| オンボーディング | `Views/OnboardingView.swift`（＋ `origin/feature/multi-page-onboarding` 枝） |

# 設計スペック: オンボーディング内アクティベーション（実ブロック＋友達招待）

> **For agentic workers:** Claude が計画・検証、Codex が実装（CLAUDE.md）。本ドキュメントは設計合意（spec）であり、step-by-step 実装プランは後続の writing-plans で別途作成する。

- **日付:** 2026-06-19
- **ブランチ:** `feature/onboarding-updates`（マージ済み main ベース `03e5df2` から分岐）
- **ステータス:** 設計合意済み（ユーザーレビュー待ち）

---

## 1. Goal（狙い）

オンボーディングの「一番熱が高い瞬間」に**実際の価値を発火**させ、初日アクティベーションとネットワーク効果を最大化する。具体的には:

1. **実ブロックのアクティベーション** — オンボーディング内で本物のアプリ制限を**最低1つ**開始する。これを完了の**ハードゲート**にし、「オンボーディングを抜けた全員が必ず1つは制限を開始している」状態を保証する。
2. **バイラルループの埋め込み** — ブロック開始の達成感の直後に、友達を招待する共有ステップを置く。「App Store インストールリンク＋友達招待リンク」を共有してもらい、ネットワーク効果を狙う。共有は強く促すが skip 可（離脱抑制）。

現状のオンボーディングは権限取得までで終わり、実ブロック設定（アプリ選択）は意図的に後回し（Phase 2b で C-4-3 deferred）だった。本設計はそれをオンボーディングに取り込む。

---

## 2. スコープ（A案: 送信フローに集中）

### In Scope
- オンボーディング末尾を「権限 → 実ブロック → 招待」に再構成（新規2ステップ）。
- 実ブロックは既存ブロッキング基盤（`BlockGroup` / `upsertBlockGroup` / `BlockingEnforcementService`）に**そのまま乗せる**（並行実装を作らない）。
- 招待は既存招待基盤（`createInvite` / `deny://invite/CODE` / `ShareLink`）を流用し、共有文面に **App Store インストールリンクを追加**。
- `AppConfiguration` に設定可能な App Store URL 定数を追加。

### Out of Scope（理由付き・後続候補）
- **受信側のシームレス自動連携（C案/B案）**: Universal Link（Associated Domains + push-server の `apple-app-site-association` + `/invite/:code` ランディング）、および deferred deep link（install 後の自動受諾）。性質の異なる別サブシステムで 1 スペックに収まらず検証も膨らむため、別スペックで段階的に強化する。
  - 現状の受信側体験: アプリ導入済みの友達は `deny://invite/CODE` タップで自動連携。未導入の友達は共有文面の App Store リンクで導入 → メッセージのリンクを再タップで連携（手動コード入力は不要＝happy path）。`InviteDeepLink` は既に `https://host/invite/CODE` 形式に対応済みなので、将来の Universal Link 化の素地はある（`SupabaseRowMapping.swift:343`）。

---

## 3. 確定済みの設計判断（ユーザー合意）

| 論点 | 決定 |
|---|---|
| 共有リンクの性質 | **フレンド招待リンク**（導入済みなら自動連携） |
| 共有ステップのゲート | **強く促すが skip 可**（完了をゲートしない） |
| 共有文面 | **App Store リンク＋招待リンク**。手動コードは控えめ/省略 |
| App Store URL | **公開済み**（製品 URL を後で差し込む。`AppConfiguration` に定数化） |
| ブロック対象の選択 | **フル選択（FamilyActivityPicker）・最低1つ**。1つも選ばなければ完了不可 |
| ブロックの即時性 | **実ブロック・即時開始**（既存 enforcement に乗る） |
| ブロックの mode | **1日の時間制限**（`.timeLimit`、デフォルト 30分/日・毎日。後で設定画面で調整可） |
| ブロックのパスワード | **クイックパスコードを設定**（新規 BlockGroup はシステム仕様で password 必須。これがブロックを"本物"にする要） |
| フロー全体 | **8ページ**、順序「権限→ブロック→招待」、All Set は独立ページにせず溶かす |

---

## 4. Architecture（フロー構造）

`OnboardingView.swift`（`TabView(selection:)` ベース、`.page(indexDisplayMode:.never)`）の末尾を再構成。0〜4は不変。

| # | ページ | 役割 | ゲート |
|---|---|---|---|
| 0 | ScreenTimeSliderPage | 平均スクリーンタイム入力 | — |
| 1 | WastedTimePage | 浪費時間の可視化 | — |
| 2 | FriendMonitorPage | 友達見守りの概念 | — |
| 3 | HowItWorksPage | コア機構の解説（4ステップ carousel） | — |
| 4 | AppleSignInProfilePage | Apple サインイン＋プロフィール | サインイン必須（既存） |
| 5 | **アクセスを許可** | Screen Time（必須）＋通知・カメラ（任意）。※現 FinalPage の権限ロジックを流用、ただし `completeOnboarding()` はここで呼ばない | Screen Time 必須（既存） |
| 6 | **最初のアプリをブロック**（新規） | FamilyActivityPicker でフル選択（≥1）＋クイックパスコード設定 → `upsertBlockGroup` で時間制限ブロックを即開始 | **選択≥1 必須（ハードゲート）** |
| 7 | **友達を招待**（新規・最終） | `createInvite` → App Store リンク＋招待リンクを `ShareLink` で共有 → `completeOnboarding()` | skip 可 |

**付随変更（`OnboardingView.swift` 内）:** `totalPages` 6→8、進捗バーの分数計算、`lastPage`/`profilePage` 等の定数、ページ遷移時の状態リセット。`OnboardingAllSet` アセットはページ7の演出に流用可。

---

## 5. コンポーネント設計

### 5.1 ページ5「アクセスを許可」（既存ロジックの分離）
現 `FinalPage`（`OnboardingView.swift:1059`）の権限要求フロー（Screen Time 必須 → 失敗なら inline エラー＋「Try Again」、通知・カメラは任意で順次要求）を流用。**唯一の変更点**は、ここで `completeOnboarding()` を呼ばないこと（完了はページ7へ移動）。Screen Time 認可はここで成立させ、後続のブロックステップの前提を満たす。

### 5.2 ページ6「最初のアプリをブロック」（新規）
**目的:** 実ブロックを1つ以上開始する。単一目的のページ。

**UI 状態:**
1. 導入コピー（なぜ今ブロックするか）。
2. 「ブロックするアプリを選ぶ」→ `FamilyActivityPicker(selection:)` をシート提示（`BlockingSettingsView.swift:2717` と同作法）。閉じたら選択件数を表示。
3. クイックパスコード設定（4桁想定、単一入力。回復は既存 `BlockPasswordResetState` に委ねる）。
4. 主ボタン「ブロックを開始」: 認可確認（未認可なら `requestScreenTimeAuthorization()`）→ `BlockGroup` を構築 → `upsertBlockGroup(group, password:)`。

**BlockGroup 構築（デフォルト）:**
- `selectionData = try BlockingSelectionCodec.encode(selection)`（`BlockingSelectionCodec.swift:5`）
- `name`: 非空（例「My First Block」）
- `mode: .timeLimit(limitSeconds: 30*60, days: BlockWeekday.everyDay)`
- `isEnabled: true`
- `unblockConfig`: システム既定（締め出しすぎない）
- `friendRequestConfig`: 既定（友達ができてから設定）
- `password`: ユーザー入力のパスコード（必須）

**統合経路（新規メソッド不要）:** `upsertBlockGroup`（`AppModel.swift:691`）の1回呼び出しで、検証 → 永続化（`persistBlockingState`）→ `syncBlockingEnforcement()` → `BlockingEnforcementService.syncMonitoring()` → `applyShields()` まで連鎖し、時間制限ブロックが既存システムと同一挙動で稼働する。別途「開始」呼び出しは不要。

**ゲート:** `selection.applicationTokens.count + categoryTokens.count + webDomainTokens.count ≥ 1` を満たすまで「開始」を無効化。

### 5.3 ページ7「友達を招待」（新規・最終）
**目的:** バイラル共有。skip 可。

- **招待生成:** `model.createInvite()`（`AppModel.swift:1156`）→ `CreatedInvite(code, url: deny://invite/CODE, expiresAt)`。内部で `enableSharingIfNeeded()` 実行。サインインはページ4で済んでいるので前提充足。
- **共有文面:** `InviteFriendsSheet.shareMessage`（`InviteFriendsSheet.swift:168`）を流用しつつ **App Store URL を追加**、手動コードは控えめ/省略。例:
  > 「Denyでスマホ依存を断ち切ってる。入れてみて → {App Store URL}。入れたらこれをタップで連携 → {deny://invite/CODE}」
- **App Store URL:** `AppConfiguration` に `appStoreURL` 定数を追加（公開済みの製品 URL を後で差し込む）。
- **UI:** `ShareLink` でシステム共有シート。主ボタン「友達を招待」を大きく、下に小さく「あとで」。共有 or skip の**どちらでも** `completeOnboarding()`。
- **失敗時:** オフライン等で `createInvite()` 失敗 → エラー＋再試行を出すが、招待は任意なので **skip で完了は可能**（招待生成失敗で完了を塞がない）。

---

## 6. データフロー / 完了ロジック

```
ページ5: requestScreenTimeAuthorization() → hasScreenTimeAuthorization == true（必須）
ページ6: FamilyActivityPicker → FamilyActivitySelection (≥1)
        + パスコード
        → BlockGroup(mode: .timeLimit 30min/everyday, isEnabled: true, password)
        → upsertBlockGroup(...) → 即時 enforcement（時間制限ブロック稼働）
ページ7: createInvite() → 共有（App Store URL + deny://invite/CODE）or skip
        → completeOnboarding()  // hasCompletedOnboarding = true（UserDefaults "HasCompletedOnboarding.v1"）
```

**完了の必要条件:** ①Screen Time 認可済み ＋ ②ブロックグループ ≥1 を開始済み。招待は任意。

---

## 7. エラー処理 / エッジケース

- **権限拒否（ページ5）:** 既存の inline エラー＋「Try Again」を流用。
- **picker 0件（ページ6）:** インラインで「最低1つ選んで」、「開始」を無効化。
- **`upsertBlockGroup` 失敗:** `model.message`（ユーザー向けエラー）を表示してページに留まる。
- **招待生成失敗（ページ7）:** エラー＋再試行。ただし skip で完了は可能。
- **再入:** ブロックは `upsertBlockGroup` 時点で即永続・発火するため、完了前に離脱しても制限は残る（望ましい挙動）。`hasCompletedOnboarding` は最終ページでのみ true。再入時に既存ブロックグループがあればページ6は「すでに保護中」を表示して通過可能にする（軽微・後回し可）。

---

## 8. 再利用マップ（既存資産）

| 目的 | 使う API / ファイル |
|---|---|
| Screen Time 認可要求 | `AppModel.requestScreenTimeAuthorization()` `:1076` |
| 認可状態確認 | `AppModel.hasScreenTimeAuthorization` `:281` |
| 選択のシリアライズ | `BlockingSelectionCodec.encode/decode` |
| ブロック作成＋即時開始 | `AppModel.upsertBlockGroup(_:password:)` `:691` |
| enforcement | `BlockingEnforcementService.syncMonitoring/applyShields` |
| picker 作法 | `BlockingSettingsView.swift:2717` |
| 招待生成 | `AppModel.createInvite()` `:1156` |
| 共有文面 | `InviteFriendsSheet.shareMessage` `:168` |
| ディープリンク受諾（受信側・既存） | `ScreenTimeSharingApp.swift:29` `onOpenURL` → `presentIncomingInvite` → `redeemInvite` |

**変更が想定されるファイル:** `OnboardingView.swift`（フロー再構成・新規2ページ）、`AppConfiguration.swift`（`appStoreURL` 追加）。新規 public メソッドは不要の見込み。

---

## 9. テスト戦略

CLAUDE.md の方針（新機能にテスト）。UI / FamilyActivityPicker / 共有シートはシステム UI で自動化不可のため、純粋ロジックを単体テスト化＋フローは手動検証。

- **(a) 共有文面生成**（純粋関数）: App Store URL と招待 URL の双方を含むことを検証。
- **(b) 選択→BlockGroup 構築ヘルパ**: `mode == .timeLimit(30min, everyday)`、`isEnabled == true`、`name` 非空、`selectionData` 非空を検証。
- **(c) ゲート述語**: 選択トークン合計 ≥1 の判定。
- **回帰:** Core 変更が入る場合は `swift test`（既存 66 件＋新規）。アプリ層のみの変更なら Xcode ビルド＋手動。

---

## 10. 依存 / 未確定

- **App Store URL（公開済み製品 URL）**: ユーザーが後で提供 → `AppConfiguration.appStoreURL` に設定。未設定時はプレースホルダ＋共有時にフォールバック挙動を定義（実装プランで詳細化）。
- **パスコードの確認入力（再入力）有無**: 単一入力を既定とするが、誤入力対策で確認入力を足すかは実装プランで微調整可。

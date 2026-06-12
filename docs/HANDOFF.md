# 引き継ぎ（次の AI セッション向け） — ScreenLog / Deny 改善

最終更新: 2026-06-13 / 作成者: Claude（前セッション）

このファイルは、次の AI が**ゼロコンテキストから作業を継続**できるよう、現状・制約・次の手順をまとめたもの。まず `CLAUDE.md` と下記「運用上の必須制約」を読むこと。

---

## 0. プロジェクト概要

生産性アプリブロッカー「**Deny**」（内部名 `ScreenTimeSharing`）。コアループ: ブロック中アプリで追加時間が欲しいとき、**自撮りの「お願い写真」＋分数を友達に申請 → 友達がフィードで承認 → 一時アンロック**。

- App（SwiftUI）= `ScreenTimeSharing/`、Core（SPM・テスト対象）= `Sources/ScreenTimeSharingCore/`、各種 App Extension（Shield 等）、Widget、push-server（Cloudflare Worker）、CloudKit、Apple Sign In。
- 改善要望の全体調査: **`docs/specs/2026-06-05-improvement-breakdown.md`**（7領域 #1〜#7 を分解。§5.1 に確定済みユーザー判断、§4 にフェーズ案）。**新しい計画を立てる前に必ず読む。**

---

## 1. 運用上の必須制約（最重要・ここで何度も嵌まった）

- **実装は Codex に委譲する**（`CLAUDE.md`: Claude が計画・検証、Codex が実装）。`Skill("codex:rescue")` に `--write --fresh` 付きで委譲。
- **Codex はコミットできない**（サンドボックスが `.git/index.lock` 書き込みを拒否）。→ Codex には「**編集のみ・コミットするな**」と指示し、**Claude（あなた）が差分を検証してコミット**する。メモリ [[codex-commits-blocked]] 参照。
- **Codex は `swift test` も走らせられない**（サンドボックスが module cache 書き込みを拒否）。→ **`swift test` は Claude が実行**して検証する。
- **Codex は1回の実行で約2タスクで停止しがち**（完了レポート無しで出力が途切れる）。→ **小分け委譲**（1〜2タスク/回）し、毎回 `git status`/`git diff` で**実体を確認**（「完了」を鵜呑みにしない）。
- **この環境にフル Xcode が無い**（Command Line Tools のみ）。→ **アプリターゲット（Views/AppModel/Extensions）はコンパイル検証不可**。`swift test` は **`ScreenTimeSharingCore`（SPM）のみ**。検証可能にしたいロジックは **Core に寄せる**。アプリ層は**コードレビュー＋ユーザー側 Xcode ビルド保留**。メモリ [[phase1-verification-gap]] 参照。
- コミット時の `LF will be replaced by CRLF` 警告は無害（無視可）。
- コミットメッセージ末尾に必ず: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`

検証の鉄則: **Codex が「やった」と言っても、差分を `git diff` で精査し、Core は `swift test`、アプリ層は計画との突合で確認してからコミット**する。

---

## 2. ブランチ構成（スタック）

`main`（プロトタイプ）/`product/accountability-locks`（製品本流）の上に、フェーズごとにスタック:

```
product/accountability-locks
  └ feature/phase0-request-button-ux      … Phase 0（完了）
      └ feature/phase1-time-request-and-shield   … Phase 1（完了・origin へ push 済み）
          └ feature/phase2-perf-and-onboarding   … Phase 2（完了・push 済み）
              └ feature/phase3-friends-and-invites   … Phase 3（完了・push 済み・★現在のブランチ）
```

各 PR のベースは未確定（ユーザーが保留）。**PR を作る前にユーザーにベースを確認**すること（phase0/phase1 を順に積むか、accountability-locks へ直接か）。

---

## 3. 進捗状況

### ✅ Phase 0（完了）
Home の申請ボタンを `Ask Friends` 主役化、Feed を受信専用化。`feature/phase0-request-button-ux`。

### ✅ Phase 1 — タイムリクエスト体験 + Shield（完了・push 済み）
ブランチ `feature/phase1-time-request-and-shield`（origin に push 済み）。計画: `docs/plans/2026-06-11-phase1-time-request-and-shield.md`。
- A1 a11y / A2 メッセージ前出し＋分数ヒント / A3 下書き（起動中のみ）/ A4 保留バッジ＋無効時→設定誘導（コア関数は `swift test` 検証）/ A5 初回コーチマーク / B2 カメラ拒否→設定誘導。**実装・コミット済み**。
- `swift test` 63件 PASS（当時）。
- **未完（ユーザー側）**: Xcode ビルド、シミュレータ手動確認、**B1 = Shield→申請フローの実機動作確認**（計画 Task B1 のチェックリスト）。
- 見送り（記録済み）: S4 URLスキーム deep-link。

### ✅ Phase 2 — 完了（origin へ push 済み）
ブランチ `feature/phase2-perf-and-onboarding`（HEAD `48a2c72` = origin と一致）。

#### ✅ Phase 2a = #3 home/stats ロード性能（完了）
計画: **`docs/plans/2026-06-12-phase2a-load-performance.md`**。スコープは spec §D の8項目から「メモ化／ポーリング早期終了／デコードスキップ」の3本に限定（残りは計画内に理由付きで見送り明記）。

- ✅ T1+T2（Core, TDD）: `UsageHistorySignature` + `UsageStatsCache` ＋テスト（`606fed7`）。
- ✅ T3: `AppModel.usageStatsCache` 保持＋ `StatsView` の3 computed をキャッシュ経由に（`2f60c1a`）。
- ✅ T4: `ScreenTimeReportBridgeView` の3本のポーリングに `didChange`＋`quietTicks>=3` の早期終了。データ未到着時は従来どおり60秒（`22f31b5`）。隠し橋渡しポーラーは述語が無いため `model.localSnapshot != nil` を使用。
- ✅ T5: `loadUsageHistory()` に `lastLoadedUsageData` を追加しバイト同一なら decode＋再 publish をスキップ（`4352d50`）。
- ✅ Task C: 差分は計画どおりのファイルのみ・`StatsView` に直接ビルダー呼び出し残存なし・**`swift test` 66件 PASS**。

#### ✅ Phase 2b = #5 オンボーディング（完了）
計画: **`docs/plans/2026-06-12-phase2b-onboarding.md`**（`7e856f3`。見送り項目と spec からの逸脱1点を明記）。確定方針どおり**ゲスト開始不可・サインイン必須維持**（spec §5.1-2）。

- ✅ T1: `HowItWorksPage`（コア機構4ステップ図解）をタグ4に挿入、`totalPages` 6→7（`d7b997d`）。
- ✅ T2: サインインページ内に価値訴求3行（`SignInBenefitRow`×3: フレンド/同期/復元）。spec の「直前に1画面」をページ内追加に変更（理由は計画に明記）（同 `d7b997d`）。
- ✅ T3: 最終ページの完了ボタンを「スクリーンタイム必須（失敗時 inline エラー＋Try Again）→通知→カメラ（共に任意）→完了」の直列フローに。`FinalPermissionRow`×3 で権限を事前説明（`48a2c72`）。
- ✅ Task C: 差分は `OnboardingView.swift`＋計画 docs のみ・`swift test` 66件 PASS（Core 変更なし）。

**見送り（計画に理由付き記録済み）**: C-4-3 アプリ選択統合（L・実機検証必須）/ C-4-4 完了後ガイド / C-4-7 Quick Start カード。

### ✅ Phase 3 — 完了（origin へ push 済み）
ブランチ `feature/phase3-friends-and-invites`（Phase 2 の上に積んだスタック）。

#### ✅ Phase 3a = #4 統合フレンドリスト＋鮮度（完了）
計画: **`docs/plans/2026-06-13-phase3a-friends-board.md`**。確定方針どおりランキングは「申請時間順」維持（`StatsBoardBuilder` 不変更）。

- ✅ T1（Core, TDD）: `FriendFreshness`（緑<5分/黄5-60分/橙>1時間/missing）＋ `FriendBoardBuilder.activityRows`（使用時間降順・データ無しは末尾・名前で安定）＋テスト2件（`a62198a`）。**`swift test` 68件 PASS**。
- ✅ T2: `AppModel` に `friendsLastSyncedAt`/`isSyncingFriends`、`reloadFriends()` で更新（`e4c3cc5`）。
- ✅ T3: `FriendsView` を単一「Friends」セクション＋ Activity/Leaderboard モード切替（`@AppStorage` 永続）＋全行に色分き「Updated Xm ago」＋同期ヘッダ（Sync Now）に再構成（`4690c33`）。
- 見送り（計画に理由付き）: フレンド詳細View（L）/ unfriend・mute・block（ゾーン削除は実機検証必須）/ CloudKit サーバ側フィルタ。

#### ✅ Phase 3b = #1 招待リンク状態・再送・取消（完了）
計画: **`docs/plans/2026-06-13-phase3b-invite-status.md`**。確定方針どおりサーバ側ディレクトリ新設なし（既存チャネル構造の読取＋削除のみ）。

- ✅ T1: `CloudKitUsageSnapshotStore` に `PendingFriendInvite` ＋ `fetchPendingInvites`（承認者ミラー無し＆非オーナー承認参加者無しのチャネル＝保留）＋ `cancelPendingInvite`（チャネルルート削除でリンク失効）（`2edcd69`）。
- ✅ T2: `AppModel.pendingInvites` ＋ reload/cancel ラッパ（`a439ddc`）。
- ✅ T3: Friends に「Pending Invites」セクション（ShareLink 再送/コピー/確認付き取消）。シート閉鎖・pull-to-refresh・初回表示でリロード（`4c8c7ec`）。
- 見送り（計画に理由付き）: 受信済み招待一覧（CloudKit は未承認 share の受信箱をクエリ不可）/ QR 表示。

---

## 4. 次にやること（順番）

1. **ユーザーに確認**: Phase 2/3 の Xcode ビルド＋検証のタイミング、PR 作成の要否とベースブランチ（phase0→1→2→3 を順に積むか、`product/accountability-locks` へ直接か）。
2. spec の主要7領域（#1〜#7）はこれで全フェーズ着手済み。残りは各計画の「見送り」項目（フレンド詳細View、unfriend、オンボーディングのアプリ選択統合、完了後ガイド等）と横断基盤（spec §3: 通知インボックス統合・準リアルタイム同期）。次のスコープはユーザーと相談して決める。

**ユーザー側に残る検証(AI 環境では不可)**: 全 phase ブランチの Xcode ビルド、シミュレータ手動確認（Phase 2b の onboarding 7ページ遷移と権限フロー、Phase 3a の Friends 統合表示）、**Phase 3b の実機 iCloud E2E（招待作成→保留表示→別端末で承認→保留から消滅→取消→リンク失効）**、Phase 1 B1 の実機 Shield フロー確認。

---

## 5. 参照ファイル

- 要件分解（全領域）: `docs/specs/2026-06-05-improvement-breakdown.md`
- 計画: `docs/plans/2026-06-05-phase0-request-button-ux.md` / `2026-06-11-phase1-time-request-and-shield.md` / `2026-06-12-phase2a-load-performance.md` / `2026-06-12-phase2b-onboarding.md` / `2026-06-13-phase3a-friends-board.md` / `2026-06-13-phase3b-invite-status.md`
- 行動規範: `CLAUDE.md`（Claude 計画・Codex 実装、日本語でユーザー対応・コードは英語）
- メモリ（プロジェクト記憶。セッション開始時に MEMORY.md が読み込まれる）: `codex-commits-blocked` / `phase1-verification-gap`

---

## 6. ワークフローのコツ

- 大きな調査は **`Workflow` ツールで並列探索**（前セッションは探索を6並列で実施し、現行コードの verbatim を集めてから exact な計画を書いた → Codex が迷わず実装できた）。`ultracode` が ON なら積極活用。
- 計画は **プレースホルダ禁止・exact な before/after**（`superpowers:writing-plans`）。行番号は概算なので「変更前」スニペットで照合させる。
- 計画を書く前にコードを読む（前セッションでは spec が「未実装」とした #7 のコアが**既に実装済み**だった例があり、盲目実装の無駄を回避できた）。

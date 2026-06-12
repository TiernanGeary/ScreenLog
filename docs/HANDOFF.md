# 引き継ぎ（次の AI セッション向け） — ScreenLog / Deny 改善

最終更新: 2026-06-12 / 作成者: Claude（前セッション）

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
          └ feature/phase2-perf-and-onboarding   … Phase 2（進行中・★現在のブランチ）
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

### 🔄 Phase 2 — 進行中（★現在ここ。ユーザー指示「#3→#5 を連続実装、レビュー点は最小化」）
ブランチ `feature/phase2-perf-and-onboarding`（**未 push**。最後に push が必要）。

#### Phase 2a = #3 home/stats ロード性能
計画: **`docs/plans/2026-06-12-phase2a-load-performance.md`**（コミット済み）。スコープは spec §D の8項目から「メモ化／ポーリング早期終了／デコードスキップ」の3本に限定（残りは計画内に理由付きで見送り明記）。

- ✅ **T1 + T2（Core, TDD）完了・検証済み・コミット済み**（`606fed7`）。`Sources/ScreenTimeSharingCore/UsageStatsCache.swift`（`UsageHistorySignature` + `UsageStatsCache`）＋テスト。**`swift test` 66件 PASS（Claude が実行確認済み）**。
- ⬜ **T3 未実装**: `AppModel` に `let usageStatsCache = UsageStatsCache()` を追加し、`StatsView` の `summary`/`chartBuckets`/`appUsageRows` を `UsageStatsBuilder.*` → `model.usageStatsCache.*` に置換（計画 Task 3 に exact before/after あり）。
- ⬜ **T4 未実装**: `ScreenTimeReportBridgeView.swift` の**3本の `pollForReportSnapshot`** にデータ安定後の早期終了（`didChange`＋`quietTicks>=3`）。データ未到着時は従来どおり60秒（退行回避）。
- ⬜ **T5 未実装**: `AppModel.loadUsageHistory()` に `lastLoadedUsageData` を持たせ、バイト同一なら decode と @Published 再代入をスキップ。
- 注意: T4 の `hasCachedReportData`/`hasCachedTodayReport` 述語名は実体に合わせて確認（計画に注記あり）。

#### Phase 2b = #5 オンボーディング
⬜ **未着手（計画も未作成）**。要件は spec §C（最大ギャップ＝「コア機構を一度も説明していない」）。確定方針: **ゲスト開始不可・サインイン必須維持**（spec §5.1）。`OnboardingView`（既存6ページ）＋ 別枝 `origin/feature/multi-page-onboarding` の `AppPickerPage` 参照。

### ⬜ Phase 3（未着手）
#4 フレンド一覧統合、#1 招待リンク状態表示/再送（spec §E, §F、§5.1 確定方針あり）。

---

## 4. 次にやること（順番）

1. **Phase 2a の残り（T3 → T4 → T5）を Codex に委譲**（小分け、編集のみ・コミット禁止）。各回後に: `git diff` 精査 → `swift test`（66件のまま PASS のはず。アプリ層変更は SPM テストに影響しない）→ 計画と突合 → **Claude がコミット**（計画記載のコミットメッセージ使用）。
2. **Phase 2a Task C（最終確認）** → ユーザーへ簡潔報告。
3. `feature/phase2-perf-and-onboarding` を **push**（`git push -u origin feature/phase2-perf-and-onboarding`）。
4. **Phase 2b（#5）**: `superpowers:writing-plans` 方針で「並列探索（Workflow）→ exact 計画 → Codex 実装 → Claude 検証/コミット」。`OnboardingView.swift` 等を実地調査してから計画を書く。
5. 区切りで PR 要否をユーザーに確認（ベースブランチも）。

**ユーザー側に残る検証（AI 環境では不可）**: 全 phase ブランチの Xcode ビルド、シミュレータ手動確認、Phase 1 B1 の実機 Shield フロー確認。

---

## 5. 参照ファイル

- 要件分解（全領域）: `docs/specs/2026-06-05-improvement-breakdown.md`
- 計画: `docs/plans/2026-06-05-phase0-request-button-ux.md` / `2026-06-11-phase1-time-request-and-shield.md` / `2026-06-12-phase2a-load-performance.md`
- 行動規範: `CLAUDE.md`（Claude 計画・Codex 実装、日本語でユーザー対応・コードは英語）
- メモリ（プロジェクト記憶。セッション開始時に MEMORY.md が読み込まれる）: `codex-commits-blocked` / `phase1-verification-gap`

---

## 6. ワークフローのコツ

- 大きな調査は **`Workflow` ツールで並列探索**（前セッションは探索を6並列で実施し、現行コードの verbatim を集めてから exact な計画を書いた → Codex が迷わず実装できた）。`ultracode` が ON なら積極活用。
- 計画は **プレースホルダ禁止・exact な before/after**（`superpowers:writing-plans`）。行番号は概算なので「変更前」スニペットで照合させる。
- 計画を書く前にコードを読む（前セッションでは spec が「未実装」とした #7 のコアが**既に実装済み**だった例があり、盲目実装の無駄を回避できた）。

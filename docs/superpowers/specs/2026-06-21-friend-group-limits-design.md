# 設計スペック: フレンドグループ共同アプリ制限

> **For agentic workers:** Claude が計画・検証、Codex が実装（CLAUDE.md）。本ドキュメントは設計合意（spec）。step-by-step 実装プランは後続の writing-plans で **サブプロジェクトごとに** 別途作成する。

- **日付:** 2026-06-21
- **ブランチ:** `feature/friend-group-limits`（main `95a7f6a` から分岐）
- **ステータス:** 設計合意済み（ユーザーレビュー待ち）

---

## 1. Goal

友達同士でグループを作り、グループ単位で**同じアプリ群**に制限をかける。2つのモード（① 各メンバーが同じ日次制限 / ② 1つの共有日次プール）を提供し、ブロックの解除は**グループ承認**で行う。狙いは「友達による説明責任（accountability）」をグループに拡張すること。

---

## 2. 確定した決定（ユーザー合意）

| 論点 | 決定 |
|---|---|
| モード | グループは作成時に **`per_member`（各自同じ日次制限）** か **`pool`（共有日次プール）** を選ぶ |
| 共有プール | 1つの共有枠、誰の使用でも消費、**使い切ると翌リセットまで全員ブロック**、サイズは作成者設定 |
| リセット周期 | **日次**。基準タイムゾーンは **オーナーのTZ** |
| 対象アプリ | 作成者が **アプリ名リスト（テキスト）** を定義 → 各メンバーが自端末ピッカーで選択（自己申告・設定済み✓/✗ 表示）。iOSトークンは端末ローカル/不透明で**共有・検証不可** |
| ローカルパスワード | **自動生成**（本人非表示・Keychain管理）。自力解除不可＝承認制を担保 |
| 解除 | **グループ承認で延長**（既存 time-request 流用）。承認に必要な人数は **設定可能（既定1、N に設定可）** |
| プール時の承認延長 | **本人のみ一時解除**（プールには加算しない） |
| 参加 | **グループ招待リンク**（既存招待を多人数 redeem に拡張）。参加後にアプリを各自設定 |
| 権限 | 作成者＝owner（config編集・メンバー削除・グループ削除）。メンバーは leave 可。**owner は退出不可（delete のみ・譲渡なし）** |
| ビルド順 | **SP1 → SP2 → SP4 → SP3** |

---

## 3. iOS / バックエンド制約（実コードで確認済み）

- **FamilyActivitySelection トークンは端末ローカル/不透明**。他者へ転送も、何のアプリかの読み戻しも不可（`BlockingSelectionCodec` はローカル専用）。→ 各メンバーがピッカーで選び、同一性はアプリ側で検証不能。
- **ブロックはローカル**：`BlockGroup` + `AppModel.upsertBlockGroup(_:password:)`（~L691）→ `BlockingEnforcementService` が DeviceActivity モニタ登録。`.timeLimit` は日次しきい値超過後にシールド発火（~L106-134）。新規はパスワード必須。
- **使用量は日次バッチ**：`daily_snapshots`（per owner/day、`selected_app_seconds`）。1h+ stale 想定。リアルタイムではない。
- **遠隔ブロックの仕組みは皆無**。push-server は `/register`・`/notify`・`/invite/<code>`・`/privacy`・`/support` のみ。
- 安定ID＝Apple Sign In の Supabase auth UUID＝`profiles.id`。
- 既存招待：`create/peek/redeem_friend_invite`（`SupabaseSnapshotStore:215-266`）、`deny://invite/CODE`＋push-server ランディング。
- 既存 time-request：`BlockFriendRequest.selectedFriendIDs`（`BlockingModels:583`）、`time_requests.recipient_ids:[UUID]`、`respond_to_time_request`/`collect_time_request`、push一斉 `sendPushNotification(toProfileIDs:)`。`AccountabilityModels` の `LockMode.group`＝N承認概念。

---

## 4. 共有データモデル（全SPの土台）

### Supabase テーブル
```
groups(id uuid pk, owner_id uuid→profiles, name text,
       mode text['per_member'|'pool'], owner_time_zone text, created_at, updated_at)
group_members(group_id uuid, user_id uuid, role text['owner'|'member'],
       joined_at, configured_at timestamptz null, left_at timestamptz null)  PK(group_id,user_id)
group_invites(code text pk, group_id uuid, created_by uuid, created_at, expires_at)  -- 多人数redeem
group_config(group_id uuid pk, app_names text[],
       per_member_limit_seconds int null, pool_seconds int null,
       reset text default 'daily', approvals_required int default 1, updated_at)
group_usage(group_id uuid, user_id uuid, day text, selected_app_seconds int, updated_at)  PK(group_id,user_id,day)
-- 既存 time_requests に group_id uuid null を追加（グループ申請スコープ）
```
- RLS：`group_members` 在籍で各テーブル SELECT。`group_config`/メンバー削除は owner のみ。`group_usage` は自分の行を upsert・グループ分を SELECT。招待 peek は未認証可、redeem は要認証。プール使用量＝`SUM(selected_app_seconds)`（group_id, owner-TZ day）。

### Supabase RPC（命名固定）
- `create_group(p_name, p_mode, p_app_names, p_limit_seconds, p_approvals_required, p_owner_time_zone) -> {group_id, code}`
- `create_group_invite(p_group_id) -> {code, expires_at}`（owner）
- `peek_group_invite(p_code) -> {group_id, group_name, owner_display_name, mode}`（未認証可）
- `redeem_group_invite(p_code) -> {group_id, group_name}`（冪等・多人数）
- `get_my_groups()` / `get_group(p_group_id) -> {group, members[], config}`
- `update_group_config(p_group_id, p_app_names, p_limit_seconds, p_approvals_required)`（owner、`updated_at` 更新）
- `set_member_configured(p_group_id, p_configured)`
- `leave_group(p_group_id)`（メンバー） / `remove_group_member(p_group_id, p_user_id)`（owner） / `delete_group(p_group_id)`（owner）
- `report_group_usage(p_group_id, p_day, p_selected_app_seconds) -> {used, remaining, exhausted}`（pool）
- `get_group_pool_state(p_group_id, p_day) -> {pool_seconds, used_seconds, remaining_seconds, exhausted}`
- `send_group_time_request(p_group_id, p_seconds, p_message, p_photo_path) -> {request_id}`
- `respond_group_time_request(p_request_id, p_approve)`（承認は `approvals_required` 人で成立）

### Core モデル（`Sources/ScreenTimeSharingCore`・テスト対象）
- `FriendGroup{ id, ownerID, name, mode: GroupMode, ownerTimeZone, createdAt, updatedAt }`
- `enum GroupMode { case perMember, pool }`、`enum GroupRole { case owner, member }`
- `GroupMember{ groupID, userID, displayName, role, joinedAt, configuredAt: Date? }`
- `GroupBlockConfig{ groupID, appNames:[String], perMemberLimitSeconds:Int?, poolSeconds:Int?, approvalsRequired:Int, reset:.daily, updatedAt }`
- `GroupPoolState{ poolSeconds, usedSeconds, remainingSeconds, exhausted:Bool }`
- 純粋ロジック（テスト）：`GroupPool.aggregate(memberSeconds:)`/`remaining`/`exhausted`、`GroupBlockConfig.validate()`（mode↔params整合・非空・正値・approvals≥1）、アプリ名リスト正規化、メンバー設定状況サマリ、owner-TZ 日付境界。

---

## 5. サブプロジェクト詳細

### SP1：社会レイヤ（グループ＋メンバー＋招待）
- **Backend**：§4 の groups/group_members/group_invites＋create/invite/peek/redeem(多人数)/get_my_groups/get_group/leave/remove/delete RPC。
- **Core**：`FriendGroup`,`GroupMember`,`GroupMode`,`GroupRole`、メンバーサマリ・招待コード整形（純粋）。
- **App**：`GroupsView`（一覧＋作成）、`CreateGroupSheet`（名前/モード/アプリ名リスト/制限値/承認人数→`create_group`→招待リンクを ShareLink）、`deny://group-invite/CODE` で Join（`InviteDeepLink`＋`ScreenTimeSharingApp.onOpenURL` 拡張、手動コードも）、`GroupDetailView`（メンバー＋設定済み✓/✗、owner：config編集/メンバー削除/グループ削除/招待再共有、member：leave）。AppModel に create/fetch/redeem/leave/remove/delete/presentIncomingGroupInvite。`SupabaseSnapshotStore`＋`SupabaseRowMapping` に RPC ラッパ＋行マッピング。
- **push-server**：`/invite` ランディングをグループ招待にも対応（type or `/group-invite/<code>`、App Store フォールバック同一）。
- **データフロー**：作成→招待リンク共有→友達タップ→アプリ起動→peek→受諾→redeem→`group_members` 追加。
- **エッジ**：コード期限切れ／join中グループ削除／既在籍(冪等)／owner は leave 不可。
- **テスト**：Core メンバーサマリ＋招待整形（純粋）。RPC/UI は結合・手動。

### SP2：各自同じ制限モード（`per_member`）
- 参加後、グループのアプリ名リストを提示→**FamilyActivityPicker で各自選択**→`BlockGroup(mode:.timeLimit(perMemberLimitSeconds, everyday), isEnabled:true, name:"<group>", selectionData, password:自動生成)` を `upsertBlockGroup`→成功で `set_member_configured(true)`。
- **自動生成パスワード**：ランダム生成し **Keychain にアプリ管理**（本人非表示）。SP4 の承認解除でアプリが内部利用。
- **設定変更の伝播**：owner が config 更新→`updated_at` 進む→各メンバー前面化時に検知→「設定が変わりました、再適用」。アプリ名変更→ピッカー再選択、制限値だけ→既存 BlockGroup を更新（既存パスワード）。
- **設定済み✓/✗**：`group_members.configured_at` を `GroupDetailView` に表示、未設定者を促す。
- **エッジ**：0件選択（ゲート）、leave→ローカル BlockGroup 削除、未設定→pending。
- **テスト**：`GroupBlockConfig`→BlockGroup パラメータ生成、config 検証（Core）。実機強制は手動。

### SP4：グループ承認で延長（解除）
- ブロック中の「グループに延長申請」→ `send_group_time_request(group_id, seconds, message, selfie?)`（`time_requests` に group_id＋recipient_ids=他メンバー）→push一斉。
- メンバーは既存リクエストUIで承認/拒否→`respond_group_time_request`。**`approvals_required` 人**の承認で成立（既定1）。
- **承認成立時**：申請者に一時解除＝既存 `BlockUnblockSession` をローカル group BlockGroup へ N分（アプリが保管パスワードで適用）。
- **プール時**：承認延長は **本人のみ一時解除**（`group_usage`/プールには加算しない）。
- **エッジ**：申請期限切れ、必要人数に届かず（リセットまでブロック継続）、申請者 leave。
- **テスト**：申請/承認の状態遷移（既存流用）、承認カウント＝approvals_required（Core 判定）。

### SP3：共有プール（準リアルタイム・最難関）
- `pool` モード。各メンバーはアプリをローカル選択し、**backstop** として「プール総量と同じローカル日次上限」の BlockGroup を張る（オフラインでも1人がプール全量を超えない保険）。加えてプール会計に参加：
  - **使用量レポート**：`ScreenLogActivityMonitorExtension` に細かいしきい値イベント（例：選択アプリ60–120秒毎）を登録→発火で `report_group_usage(group_id, owner-TZ-day, 累計秒)`。前面化時にも送信。
  - **集計**：`report_group_usage` が自分の `group_usage` を upsert→グループの used/remaining/exhausted（SUM）を返す。`get_group_pool_state` で参照。
  - **枯渇シグナル**：used≥pool 検知で **バックエンド起点**（Supabase Edge Function / webhook）から **silent push（content-available）** を全メンバーへ→各端末が起きて即シールド。前面化ポーリングでも補完。
  - **ローカル強制**：exhausted→listed apps をシールド。reset（owner-TZ 翌日）/承認延長→解除。
  - **オーバーラン正直開示**：オフライン・push 遅延・レポート間隔で多少の超過は不可避。backstop が最悪値を「1人＝プール全量まで」に限定。
- **push-server**：pool-exhausted の silent broadcast を追加（トリガはバックエンド起点が堅い）。
- **テスト**：プール集計・残量・枯渇・owner-TZ リセット境界・backstop を Core で厳密に。分散部は結合/シミュレーション＋手動。

---

## 6. 横断事項
- **セキュリティ/RLS**：在籍ベース。RPC は必要に応じ SECURITY DEFINER。招待 peek は未認証可・redeem は要認証。
- **タイムゾーン**：日次リセット/プール集計は **owner のTZ**（`groups.owner_time_zone`）基準。各メンバーのローカル日付とのズレはこの基準で吸収。
- **オフライン/オーバーラン**：SP3 の backstop で緩和、残差は仕様として明示。
- **認証前提**：グループ作成/参加は Apple サインイン必須。

## 7. ビルド順（確定）
**SP1（社会レイヤ）→ SP2（各自同じ制限）→ SP4（承認解除）→ SP3（共有プール）**。各SPは個別に spec詳細化不要（本spec内）＋ **writing-plans で個別の実装プラン**を起こし、Codex 実装→検証→コミット。SP1〜SP2＋SP4 で「グループで各自同じ制限＋承認解除」という完結価値が立ち、SP3 はその上の増分。

## 8. テスト戦略
- Core 純粋ロジック（プール集計・config検証・承認カウント・owner-TZ境界・メンバーサマリ・アプリ名正規化）は `swift test`。
- 各 BlockGroup 生成パラメータ・state 遷移も Core で単体化。
- FamilyActivityPicker / 実シールド / push / Supabase RPC は結合・手動（実機）。
- 既存 66+ テストの回帰維持。

## 9. Out of Scope / 後続
- 個別アプリの**技術的同一性検証**（iOS 不可）。
- 真のリアルタイム強制（準リアルタイム＋backstop で代替）。
- オーナー譲渡（今回は退出不可・delete のみ）。

## 10. 依存 / 未確定（実装プラン段で詳細化）
- Supabase スキーマ/RLS/RPC は**サーバ側のマイグレーション**が必要（このリポに SQL 置き場があるか、別管理かを実装前に確認）。
- silent push のトリガ方式（Supabase Edge Function vs push-server webhook）は SP3 実装プランで確定。
- DeviceActivity しきい値の粒度（レポート頻度 vs バッテリ）の実機チューニングは SP3 で。

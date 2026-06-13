# Phase 3b: 招待リンクの状態表示・再送・取消（#1）実装計画

> **For agentic workers:** Codex が実装（CLAUDE.md: Claude が計画・検証、Codex が実装）。本フェーズは**全タスクがアプリ層**（CloudKit ストア＋AppModel＋FriendsView）のため、この環境では `swift test` は回帰確認のみ（Core 変更なし）。検証は**差分と本計画の exact コードの突合＋ユーザー側 Xcode ビルド＋実機 iCloud 確認**。進捗はチェックボックスで管理。

**Goal:** 招待リンクを「作って送ったら消える」単発フローから、**未承認の招待が一覧で見え、再送（Share/Copy）と取消ができる**フローにする（spec §F-4-1, F-4-2）。

**Architecture:** 既存のペアワイズ・チャネル設計を活用する。招待ごとに `channel-<profileID>-<UUID>` ルートレコードが作られ（`prepareProfileShare`）、承認者は `participant-profile-*` ミラーをチャネルに書き戻す（`channelRootIDsByFriendID` が読む）。**「保留招待」＝自分のチャネルルートのうち、(a) 承認者ミラーが無く (b) share に非オーナー承認参加者もいないもの**。再送は既存 share URL の再提示（`ShareLink`/コピー）、取消はチャネルルート削除（share も連動して失効）。

**Tech Stack:** Swift / SwiftUI / CloudKit。

**Base branch:** `feature/phase3-friends-and-invites`（Phase 3a の上。すでにこのブランチ上にいる）
**確定済み方針（spec §5.1-1）:** サーバ側ディレクトリは**新設しない**。CloudKit 共有リンク方式の枠内で磨く。メール/ユーザー名検索は対象外。
**関連spec:** `docs/specs/2026-06-05-improvement-breakdown.md`（§F）

---

## スコープと「今回見送り」

| 採用 | 項目（spec） | タスク |
|---|---|---|
| ✅ | F-4-1 招待状態の可視化（**送信済み・未承認**の一覧） | T1/T2/T3 |
| ✅ | F-4-2 保留招待の再送・取消 | T1/T2/T3 |

**今回見送り（理由付き）:**
- **F-4-1 の「受信済み招待」一覧**: CloudKit は未承認 share の「受信箱」をクエリできない（リンクを開いた瞬間に accept フローへ入る設計）。承認済みは既にフレンド一覧に出るため、クライアント側で表示できる受信状態が存在しない。
- **F-4-3 QR コード表示**: `ShareLink`＋コピーで主要動線は満たす。QR は CoreImage 依存の純増分で、招待ボタンの発見性は Phase 0 以降の Friends ツールバー＋Settings で既に2タップ以内。
- **F-4-4**: 方針確定により対象外（検索/連絡先サジェストはサーバ側ディレクトリ前提）。

**注意（実機検証必須の理由）:** 保留判定・取消は CloudKit 実レコードに対する操作で、シミュレータ/このマシンでは動作確認不可。コードレビューと Xcode ビルドの後、**実機で「招待作成→保留に出る→別端末で承認→保留から消える→取消でリンク失効」**の確認がユーザー側に残る。

---

## ファイル変更マップ

| ファイル | 役割 | 変更（タスク） |
|---|---|---|
| `ScreenTimeSharing/Services/CloudKitUsageSnapshotStore.swift` | CloudKit 入出力 | `PendingFriendInvite` ＋ `fetchPendingInvites` ＋ `cancelPendingInvite`（T1） |
| `ScreenTimeSharing/AppModel.swift` | 中央状態 | `pendingInvites` ＋ reload/cancel ラッパ（T2） |
| `ScreenTimeSharing/Views/FriendsView.swift` | Friends 画面 | Pending Invites セクション＋行 UI（T3） |

Core 変更なし（`swift test` は 68件のまま PASS の回帰確認のみ）。

---

## Task 1: ストア — 保留招待の取得と取消

**Files:**
- Modify: `ScreenTimeSharing/Services/CloudKitUsageSnapshotStore.swift`

- [ ] **Step 1: `PendingFriendInvite` 型を追加**

`CloudKitUsageSnapshotStoreError` enum の閉じ括弧の直後（`@MainActor` の直前、L43-45 付近）に挿入:

```swift
/// A sent invite channel that no friend has accepted yet.
struct PendingFriendInvite: Identifiable, Equatable {
    let id: String          // channel UUID
    let url: URL?
    let createdAt: Date?
}
```

- [ ] **Step 2: `fetchPendingInvites` / `cancelPendingInvite` を追加**

`shareMetadata(for:)` 関数の閉じ括弧の直後（`fetchFriendSummaries(now:)` の直前、L746 付近)に挿入:

```swift
    /// Lists invite channels this user created that no friend has accepted yet.
    /// A channel counts as accepted when an accepter's participant mirror points
    /// at it, or its share already has a non-owner accepted participant.
    func fetchPendingInvites(profile: UserProfile) async throws -> [PendingFriendInvite] {
        guard let container else {
            return []
        }

        let database = container.privateCloudDatabase
        let channelRoots = try await ownChannelRecords(database: database, profileID: profile.id)
        guard !channelRoots.isEmpty else {
            return []
        }

        let acceptedByFriend = try await channelRootIDsByFriendID(database: database, profileID: profile.id)
        let acceptedRootIDs = Set(acceptedByFriend.values)

        var invites: [PendingFriendInvite] = []
        for root in channelRoots {
            guard !acceptedRootIDs.contains(root.recordID),
                  let channelUUID = channelUUID(from: root, profileID: profile.id) else {
                continue
            }

            let shareID = CKRecord.ID(
                recordName: "channel-share-\(profile.id)-\(channelUUID)",
                zoneID: privateZoneID
            )
            guard let share = try await existingProfileShare(shareID: shareID, database: database) else {
                continue
            }

            let hasAcceptedParticipant = share.participants.contains { participant in
                participant.role != .owner && participant.acceptanceStatus == .accepted
            }
            if hasAcceptedParticipant {
                continue
            }

            invites.append(
                PendingFriendInvite(
                    id: channelUUID,
                    url: share.url,
                    createdAt: root.creationDate
                )
            )
        }

        return invites.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    /// Cancels a pending invite by deleting its channel root, which also tears
    /// down the associated share so the old link stops working.
    func cancelPendingInvite(channelUUID: String, profile: UserProfile) async throws {
        guard let container else {
            throw CloudKitUsageSnapshotStoreError.unavailableInSimulator
        }

        let database = container.privateCloudDatabase
        let rootID = CKRecord.ID(
            recordName: channelRootRecordName(profileID: profile.id, channelUUID: channelUUID),
            zoneID: privateZoneID
        )

        do {
            _ = try await database.modifyRecords(
                saving: [],
                deleting: [rootID],
                savePolicy: .changedKeys,
                atomically: false
            )
        } catch {
            throw CloudKitUsageSnapshotStoreError.cloudKitSaveFailed(
                context: "Cancelling the invite",
                reason: cloudKitFailureMessage(for: error)
            )
        }
    }
```

> 既存 private ヘルパへの依存（同一クラス内なのでアクセス可）: `ownChannelRecords`（L1120）/ `channelRootIDsByFriendID`（L1154）/ `channelUUID(from:profileID:)`（L1092）/ `existingProfileShare`（L941）/ `channelRootRecordName`（L1084）/ `privateZoneID`（L813）/ `cloudKitFailureMessage`（L1058）。share の recordName 形式 `channel-share-<id>-<uuid>` は `prepareProfileShare`（L291-294）の生成形式に一致。

- [ ] **Step 3: コミット（Claude が実行）**

```bash
git add ScreenTimeSharing/Services/CloudKitUsageSnapshotStore.swift
git commit -m "Add pending-invite listing and cancellation to the CloudKit store (Phase 3b)

Each invite already creates a pairwise channel root, and accepters write a
participant mirror back into it. Derive 'pending' as channel roots with no
mirror and no accepted share participant, exposing url + createdAt for resend
UI; cancel deletes the channel root so the share link stops working.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 2: `AppModel` — 保留招待の状態公開

**Files:**
- Modify: `ScreenTimeSharing/AppModel.swift`

- [ ] **Step 1: @Published フィールドを追加**

変更前（Phase 3a 適用後の L238-240 付近）:

```swift
    @Published var friendsLastSyncedAt: Date?
    @Published var isSyncingFriends = false
```

変更後:

```swift
    @Published var friendsLastSyncedAt: Date?
    @Published var isSyncingFriends = false
    @Published var pendingInvites: [PendingFriendInvite] = []
```

- [ ] **Step 2: reload / cancel ラッパを追加**

`reloadFriends()` 関数の閉じ括弧の直後に挿入:

```swift
    func reloadPendingInvites() async {
        do {
            pendingInvites = try await snapshotStore.fetchPendingInvites(profile: profile)
        } catch {
            // Keep the previous list; the pending section is advisory and
            // reloadFriends already surfaces connectivity errors.
        }
    }

    func cancelPendingInvite(_ invite: PendingFriendInvite) async {
        do {
            try await snapshotStore.cancelPendingInvite(channelUUID: invite.id, profile: profile)
            pendingInvites.removeAll { $0.id == invite.id }
        } catch {
            message = "Could not cancel invite: \(error.localizedDescription)"
        }
    }
```

- [ ] **Step 3: コミット（Claude が実行）**

```bash
git add ScreenTimeSharing/AppModel.swift
git commit -m "Expose pending friend invites on AppModel (Phase 3b)

Publish the store's pending-invite list with a quiet reload (errors already
surface via reloadFriends) and a cancel wrapper that removes the row
optimistically after the channel root is deleted.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 3: `FriendsView` — Pending Invites セクション

**Files:**
- Modify: `ScreenTimeSharing/Views/FriendsView.swift`

- [ ] **Step 1: セクションを追加し、リロードを配線**

変更前（Phase 3a 適用後の body 内、`AppSection("Friends") { ... }` の閉じ括弧から `.refreshable` まで）:

```swift
                }
            }
            .refreshable {
                AppHaptics.selectionChanged()
                await refreshFriends()
            }
```

変更後（保留招待が空ならセクション自体を出さない）:

```swift
                }

                if !model.pendingInvites.isEmpty {
                    AppSection("Pending Invites") {
                        AppCard {
                            ForEach(Array(model.pendingInvites.enumerated()), id: \.element.id) { index, invite in
                                PendingInviteRow(invite: invite) {
                                    Task { await model.cancelPendingInvite(invite) }
                                }
                                .appCardRow(verticalPadding: 8)

                                if index < model.pendingInvites.count - 1 {
                                    AppCardDivider()
                                }
                            }
                        }
                    }
                }
            }
            .task {
                await model.reloadPendingInvites()
            }
            .refreshable {
                AppHaptics.selectionChanged()
                await refreshFriends()
            }
```

- [ ] **Step 2: シート閉鎖時に保留リストを更新（新規招待の反映）**

変更前:

```swift
            .sheet(isPresented: $isShowingShareSheet) {
                CloudShareSheet(store: model.snapshotStore, profile: model.profile)
            }
```

変更後:

```swift
            .sheet(isPresented: $isShowingShareSheet, onDismiss: {
                Task { await model.reloadPendingInvites() }
            }) {
                CloudShareSheet(store: model.snapshotStore, profile: model.profile)
            }
```

- [ ] **Step 3: `refreshFriends()` に保留リロードを追加**

変更前:

```swift
    private func refreshFriends() async {
        await model.reloadFriends()
        await model.syncFriendRequests()
    }
```

変更後:

```swift
    private func refreshFriends() async {
        await model.reloadFriends()
        await model.syncFriendRequests()
        await model.reloadPendingInvites()
    }
```

- [ ] **Step 4: `PendingInviteRow` を追加**

`FriendsView` 構造体の閉じ括弧の直後（`private enum FriendBoardMode` の直前）に挿入:

```swift
private struct PendingInviteRow: View {
    let invite: PendingFriendInvite
    let onCancel: () -> Void

    @State private var didCopyLink = false
    @State private var isConfirmingCancel = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "link")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: 34, height: 34)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text("Invite link")
                    .font(.subheadline.weight(.semibold))

                Text(createdLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let url = invite.url {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Resend invite link")

                Button {
                    AppHaptics.buttonTap()
                    UIPasteboard.general.url = url
                    didCopyLink = true
                } label: {
                    Image(systemName: didCopyLink ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Copy invite link")
            }

            Button(role: .destructive) {
                AppHaptics.buttonTap()
                isConfirmingCancel = true
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Cancel invite")
        }
        .confirmationDialog(
            "Cancel this invite? The link will stop working.",
            isPresented: $isConfirmingCancel,
            titleVisibility: .visible
        ) {
            Button("Cancel Invite", role: .destructive, action: onCancel)
            Button("Keep", role: .cancel) {}
        }
    }

    private var createdLabel: String {
        guard let createdAt = invite.createdAt else {
            return "Waiting for a friend to accept"
        }
        return "Created " + createdAt.formatted(.relative(presentation: .named))
    }
}
```

> `UIPasteboard` は FriendsView の既存 `#if canImport(UIKit) import UIKit` 配下。`ShareLink` は iOS 16+（アプリは iOS 17+ API を既用）。取消は破壊的操作のため `confirmationDialog` で確認を挟む。

- [ ] **Step 5: 検証（残参照と整合）**

Run: `grep -n "PendingInviteRow\|pendingInvites\|reloadPendingInvites" ScreenTimeSharing/Views/FriendsView.swift`
Expected: セクション内 ForEach＋Row 定義、`.task`/`onDismiss`/`refreshFriends` の3箇所でリロード。

- [ ] **Step 6: コミット（Claude が実行）**

```bash
git add ScreenTimeSharing/Views/FriendsView.swift
git commit -m "Show pending invites with resend and cancel on Friends (Phase 3b)

Invites used to vanish after the share sheet closed, leaving no way to see
who hasn't accepted, resend a link, or revoke one. List unaccepted invite
channels under the friends board with ShareLink/copy for resending and a
confirmed cancel that revokes the link.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task C: 最終確認

- [ ] **Step 1: 差分レビュー**

Run: `git diff 4690c33 --stat`
Expected: `CloudKitUsageSnapshotStore.swift` / `AppModel.swift` / `FriendsView.swift`（+ docs）のみ。

- [ ] **Step 2: コアテスト回帰**

Run: `swift test`
Expected: 68件 PASS のまま（Core 変更なし）。

- [ ] **Step 3: 受け入れ基準（spec §F-5 のうち本スコープ分）**

- [ ] 送信済み・未承認の招待が「Pending Invites」として承認済みフレンドと区別して表示される。
- [ ] 未承認の招待を再送（Share/Copy）・取消（確認付き、リンク失効）できる。
- [ ] 受信済み招待の一覧は技術的制約により対象外と明記済み（リンクは開いた時点で accept フローに入る）。

- [ ] **Step 4: push ＋ ユーザーへ報告**（Xcode ビルド＋実機 iCloud 確認はユーザー側）

---

## Self-Review（計画著者による点検）

- **Spec coverage:** F-4-1（送信済み状態）= T1〜T3、F-4-2（再送/取消）= T1〜T3。受信状態・QR・検索は理由付きで見送り。§5.1-1（ディレクトリ新設なし）に整合 — 既存チャネル構造の読み取りと削除のみで新レコード型ゼロ。
- **Placeholder scan:** なし。全ステップ完全コード。
- **型/シンボル整合:** `PendingFriendInvite`（T1）→ AppModel（T2）→ `PendingInviteRow`（T3）が同名・同フィールド。T1 の依存 private ヘルパは行番号付きで実在確認済み。`modifyRecords(saving:deleting:savePolicy:atomically:)` は同ファイル既存使用（L219 等）と同形。
- **検証可能性:** 全タスクがアプリ層＋CloudKit のため、この環境では差分突合のみ。**実機での E2E（作成→保留表示→承認→消滅→取消→失効）がユーザー側に必須**であることを冒頭と Task C に明記。
- **リスク:** (1) 取消はチャネルルート削除＝破壊的だが、対象は**未承認チャネルのみ**（承認済みはミラー/参加者判定で保留リストから除外されるため UI から到達不可）。(2) `fetchPendingInvites` は招待数ぶん share フェッチを行うが、チャネルは招待ごと作成で件数は小さい（クエリ上限200）。(3) 過去に share sheet を開いて送らなかった「孤児チャネル」も保留として可視化される — これは仕様どおり（取消でき、リンクも有効なため）。
- **スコープ:** Codex には T1 / T2+T3 の2回に分けて委譲。

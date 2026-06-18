# Phase 2b: オンボーディング（#5）実装計画

> **For agentic workers:** Codex が実装（CLAUDE.md: Claude が計画・検証、Codex が実装）。本フェーズは**全タスクがアプリ層（`OnboardingView.swift` のみ）**のため、この環境では `swift test` での直接検証は不可（Core 変更なし＝66件 PASS の回帰確認のみ）。検証は**差分と本計画の exact before/after の突合＋ユーザー側 Xcode ビルド**。進捗はチェックボックスで管理。

**Goal:** オンボーディング完了直後のユーザーが「自撮りで友達に時間をお願いし、承認されるとアンロックされる」というコア機構を説明でき、権限（スクリーンタイム必須／通知・カメラ任意）が最終ページで論理的順序に要求され、未認可のまま完了できない状態にする。

**Architecture:** 既存 `OnboardingView` の TabView に「使い方」ページを1枚挿入（`totalPages` 6→7。profilePage/lastPage は計算値なので自動追従）。サインインページは**ページ追加ではなく既存ページ内に価値訴求の3行を追加**。最終ページの完了ボタンを「スクリーンタイム認可→失敗なら inline エラー＋リトライ／成功なら通知→カメラを順に要求→完了」の直列フローに変更。

**Tech Stack:** SwiftUI / FamilyControls（既存 `requestScreenTimeAuthorization`）/ UserNotifications / AVFoundation。

**Base branch:** `feature/phase2-perf-and-onboarding`（Phase 2a 完了済み。すでにこのブランチ上にいる）
**確定済み方針（spec §5.1-2）:** **ゲスト開始は不可・サインイン必須維持**。直前の価値訴求で離脱を抑える。
**関連spec:** `docs/specs/2026-06-05-improvement-breakdown.md`（§C）

---

## スコープと「今回見送り」

spec §C-4 は7項目。spec §4 の Phase 2 提案（「使い方ページ＋権限協調＋（任意）サインイン」）に合わせ、3本に絞る:

| 採用 | 項目（spec） | タスク |
|---|---|---|
| ✅ | C-4-1 「使い方」ページ追加（M） | Task 1 |
| ✅ | C-4-2 サインイン前の価値訴求（S） | Task 2 |
| ✅ | C-4-5 権限の協調（M）＋ C-4-6 認可失敗ハンドリング（S） | Task 3 |

**今回見送り（理由付き・後続候補）:**
- **C-4-3 アプリ選択のオンボーディング統合（L）**: `multi-page-onboarding` 枝の `AppPickerPage` はダミー9アプリのモックで、実運用には `FamilyActivityPicker` 連携＋最終ページでの `BlockGroup` 生成が必要。Effort L かつ FamilyControls は実機検証必須でこの環境では確認不可。
- **C-4-4 完了後ガイド（M）**: `RootView` へのボトムシート追加。オンボーディング本体と独立して出せる増分なので Phase 3 候補。
- **C-4-7 Quick Start カード（M）**: Home 面の変更。Phase 1 A5 のコーチマーク（Ask Friends 誘導）と役割が重なるため、効果を見てから判断。

**spec からの意図的な逸脱（1点）:** C-4-2 は「サインインページの**直前に1画面**」とあるが、本計画は**既存サインインページ内に価値訴求3行を追加**する。理由: (a) ページ総数を増やさず離脱面を増やさない、(b) 「なぜ必要か」はサインインボタンを目にした瞬間に並んでいる方が説得的、(c) 変更が1ページ内に閉じレビュー点が減る。目的（離脱抑制のための価値説明）は同等に満たす。

---

## ファイル変更マップ

| ファイル | 役割 | 変更（タスク） |
|---|---|---|
| `ScreenTimeSharing/Views/OnboardingView.swift` | オンボーディング全体 | 使い方ページ挿入（T1）/ サインイン価値訴求（T2）/ 最終ページ権限フロー（T3） |

他ファイルへの変更なし。Core 変更なし（`swift test` は回帰確認のみ）。

---

## Task 1: 「使い方」ページ追加（コア機構の説明）

FriendMonitorPage（タグ3）の直後に `HowItWorksPage` を挿入。自撮り→分数→友達が承認/拒否→一時アンロック、の4ステップを縦に図解。

**Files:**
- Modify: `ScreenTimeSharing/Views/OnboardingView.swift`

- [ ] **Step 1: `totalPages` を 7 に変更**

変更前（L29）:

```swift
    private let totalPages = 6
```

変更後:

```swift
    private let totalPages = 7
```

> `lastPage = totalPages - 1`（=6）と `profilePage = lastPage - 1`（=5）は計算値なので他の変更は不要。

- [ ] **Step 2: TabView にページを挿入**

変更前（L63-64、FriendMonitorPage の行とその次の行）:

```swift
                        FriendMonitorPage(isActive: currentPage == 3).tag(3)
                        AppleSignInProfilePage(
```

変更後:

```swift
                        FriendMonitorPage(isActive: currentPage == 3).tag(3)
                        HowItWorksPage(isActive: currentPage == 4).tag(4)
                        AppleSignInProfilePage(
```

- [ ] **Step 3: `HowItWorksPage` を追加**

`FriendMonitorPage` 構造体の閉じ括弧の直後（`// MARK: - Profile setup` コメントの直前）に挿入:

```swift
// MARK: - How it works (core request loop)

private struct HowItWorksPage: View {
    let isActive: Bool

    @State private var entered = false

    private let steps: [(symbol: String, title: String, detail: String)] = [
        ("lock.fill", "Your apps get blocked", "Pick the apps that waste your time and Deny locks you out."),
        ("camera.fill", "Ask with a selfie", "Want extra time? Snap a photo and choose how many minutes."),
        ("person.2.fill", "A friend decides", "They see your photo and approve or deny your request."),
        ("lock.open.fill", "Unlock on approval", "Approved minutes unlock the apps — then they lock again.")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 48)

                Text("How Deny works")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .opacity(entered ? 1 : 0)
                    .offset(y: entered ? 0 : 14)
                    .animation(.easeOut(duration: 0.5).delay(0.1), value: entered)

                VStack(spacing: 14) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: step.symbol)
                                .font(.title3)
                                .foregroundStyle(.tint)
                                .frame(width: 44, height: 44)
                                .background(.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.title)
                                    .font(.headline)
                                Text(step.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
                        .opacity(entered ? 1 : 0)
                        .offset(y: entered ? 0 : 14)
                        .animation(.easeOut(duration: 0.5).delay(0.2 + Double(index) * 0.12), value: entered)
                    }
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
        }
        .onChange(of: isActive, initial: true) { _, nowActive in
            entered = false
            guard nowActive else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                entered = true
            }
        }
    }
}
```

- [ ] **Step 4: 検証（残参照と整合）**

Run: `grep -n "totalPages\|\.tag(" ScreenTimeSharing/Views/OnboardingView.swift`
Expected: `totalPages = 7`、固定タグは 0/1/2/3/4 の5つ、`.tag(profilePage)` と `.tag(lastPage)` が各1つ。

- [ ] **Step 5: コミット（Claude が実行）**

```bash
git add ScreenTimeSharing/Views/OnboardingView.swift
git commit -m "Add how-it-works onboarding page for the core request loop (Phase 2b)

Onboarding never explained the app's core mechanic: selfie + minutes ->
friend approves -> temporary unlock. Insert a four-step explainer page after
the friend-monitor concept so users finish onboarding able to describe the
loop in their own words (spec C-4-1).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 2: サインイン価値訴求（必須維持・離脱抑制）

サインインページの説明1文を、「なぜアカウントが必要か」（フレンド/同期/復元）の3行リストに置き換える。

**Files:**
- Modify: `ScreenTimeSharing/Views/OnboardingView.swift`

- [ ] **Step 1: `signInContent` の説明文を価値訴求リストに置換**

変更前（`AppleSignInProfilePage.signInContent` 内、L772-776）:

```swift
            Text("Your Apple ID keeps your account safe and lets you recover it on a new device.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
```

変更後:

```swift
            Text("Deny is built around your friends, so it needs an account.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)

            VStack(spacing: 10) {
                SignInBenefitRow(
                    icon: "person.2.fill",
                    text: "Friend requests and approvals are tied to your account"
                )
                SignInBenefitRow(
                    icon: "icloud.fill",
                    text: "Your data stays in sync through iCloud"
                )
                SignInBenefitRow(
                    icon: "arrow.counterclockwise",
                    text: "Recover everything when you switch devices"
                )
            }
            .padding(.horizontal, 8)
```

- [ ] **Step 2: `SignInBenefitRow` を追加**

`AppleSignInProfilePage` 構造体の閉じ括弧の直後（`// MARK: - Final page` コメントの直前）に挿入:

```swift
private struct SignInBenefitRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }
}
```

- [ ] **Step 3: コミット（Claude が実行）**

```bash
git add ScreenTimeSharing/Views/OnboardingView.swift
git commit -m "Explain why Apple Sign In is required before asking (Phase 2b)

Sign-in stays mandatory (decided spec 5.1-2), but the page gave one generic
sentence, which reads as friction. List the concrete reasons an account is
needed (friend requests, sync, device recovery) at the moment the user sees
the sign-in button, to reduce drop-off (spec C-4-2).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

> spec は「直前に1画面」だが本計画はページ内追加（冒頭「意図的な逸脱」参照）。

---

## Task 3: 最終ページの権限協調＋認可失敗ハンドリング

完了ボタンを「スクリーンタイム（必須・失敗時 inline エラー＋リトライ）→ 通知（任意）→ カメラ（任意）→ 完了」の直列フローに。FinalPage に権限説明3行とエラー表示を追加し、起動後の不意打ち権限ダイアログを無くす。

**Files:**
- Modify: `ScreenTimeSharing/Views/OnboardingView.swift`

- [ ] **Step 1: import を追加**

変更前（L1-6）:

```swift
import AuthenticationServices
import PhotosUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
```

変更後:

```swift
import AuthenticationServices
import AVFoundation
import PhotosUI
import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif
```

- [ ] **Step 2: 失敗状態の @State を追加**

変更前（L14-16）:

```swift
    @State private var isAuthorizing = false
    @State private var isSigningIn = false
    @State private var signInError: String?
```

変更後:

```swift
    @State private var isAuthorizing = false
    @State private var screenTimeAuthorizationFailed = false
    @State private var isSigningIn = false
    @State private var signInError: String?
```

- [ ] **Step 3: 完了ボタンのフローを直列権限要求に変更**

変更前（`primaryButton` 内、L195-204）:

```swift
            } else {
                Haptics.success()
                Task {
                    isAuthorizing = true
                    await model.requestScreenTimeAuthorization()
                    isAuthorizing = false
                    model.completeOnboarding()
                    model.requestScreenTimeReportRefresh()
                }
            }
```

変更後（スクリーンタイム必須・通知/カメラは拒否してもそのまま完了＝スキップ可）:

```swift
            } else {
                Haptics.success()
                Task {
                    isAuthorizing = true
                    await model.requestScreenTimeAuthorization()

                    guard model.hasScreenTimeAuthorization else {
                        isAuthorizing = false
                        screenTimeAuthorizationFailed = true
                        return
                    }

                    screenTimeAuthorizationFailed = false
                    _ = try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound, .badge])
                    _ = await AVCaptureDevice.requestAccess(for: .video)
                    isAuthorizing = false
                    model.completeOnboarding()
                    model.requestScreenTimeReportRefresh()
                }
            }
```

> 通知/カメラは既に決定済み（granted/denied）の場合、システムダイアログを出さず即 return するため再オンボーディングでも安全。

- [ ] **Step 4: 失敗時のボタンタイトル**

変更前（`primaryTitle` 内、L46）:

```swift
        case lastPage: return "Let's Get Started!"
```

変更後:

```swift
        case lastPage: return screenTimeAuthorizationFailed ? "Try Again" : "Let's Get Started!"
```

- [ ] **Step 5: FinalPage 呼び出しにエラーフラグを渡す**

変更前（L79）:

```swift
                        FinalPage(isActive: currentPage == lastPage).tag(lastPage)
```

変更後:

```swift
                        FinalPage(
                            isActive: currentPage == lastPage,
                            showsAuthorizationError: screenTimeAuthorizationFailed
                        )
                        .tag(lastPage)
```

- [ ] **Step 6: FinalPage に権限説明3行とエラー表示を追加**

変更前（`FinalPage` 構造体の冒頭と本文の該当部分）:

```swift
private struct FinalPage: View {
    let isActive: Bool

    @State private var entered = false
```

変更後:

```swift
private struct FinalPage: View {
    let isActive: Bool
    let showsAuthorizationError: Bool

    @State private var entered = false
```

変更前（FinalPage 本文の説明テキスト部分）:

```swift
                    Text("Tap below and grant Screen Time access to start sharing with friends.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .opacity(entered ? 1 : 0)
                        .offset(y: entered ? 0 : 14)
                        .animation(.easeOut(duration: 0.5).delay(0.3), value: entered)
```

変更後（説明1文＋権限3行＋エラー表示に置換）:

```swift
                    Text("Grant access below to finish setting up.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .opacity(entered ? 1 : 0)
                        .offset(y: entered ? 0 : 14)
                        .animation(.easeOut(duration: 0.5).delay(0.3), value: entered)

                    VStack(spacing: 10) {
                        FinalPermissionRow(
                            icon: "hourglass",
                            title: "Screen Time — Required",
                            detail: "Powers your usage stats and app blocking."
                        )
                        FinalPermissionRow(
                            icon: "bell.badge.fill",
                            title: "Notifications — Optional",
                            detail: "Know right away when friends request or approve time."
                        )
                        FinalPermissionRow(
                            icon: "camera.fill",
                            title: "Camera — Optional",
                            detail: "Time requests include a selfie so friends know it's really you."
                        )
                    }
                    .padding(.horizontal, 24)
                    .opacity(entered ? 1 : 0)
                    .offset(y: entered ? 0 : 14)
                    .animation(.easeOut(duration: 0.5).delay(0.45), value: entered)

                    if showsAuthorizationError {
                        Text("Screen Time access is required to continue. Tap Try Again to re-request it.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
```

- [ ] **Step 7: `FinalPermissionRow` を追加**

`FinalPage` 構造体の閉じ括弧の直後（ファイル末尾）に挿入:

```swift
private struct FinalPermissionRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }
}
```

- [ ] **Step 8: コミット（Claude が実行）**

```bash
git add ScreenTimeSharing/Views/OnboardingView.swift
git commit -m "Coordinate permission requests on the onboarding final page (Phase 2b)

Finishing onboarding fire-and-forgot Screen Time authorization and completed
regardless, while notification/camera prompts ambushed users later at first
use. Gate completion on Screen Time approval with an inline retry, then
request notifications and camera in sequence (both deniable) so every prompt
arrives explained and in order (spec C-4-5, C-4-6).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task C: 最終確認

- [ ] **Step 1: 差分レビュー**

Run: `git diff 4352d50 --stat`
Expected: `ScreenTimeSharing/Views/OnboardingView.swift`（＋本計画 docs）のみ。

- [ ] **Step 2: コアテスト回帰**

Run: `swift test`
Expected: 66件 PASS のまま（Core 変更なし）。

- [ ] **Step 3: 受け入れ基準（spec §C-5 のうち本スコープ分）**

- [ ] お願い写真フロー（コア機構）がプロフィール設定の**前に**説明される（HowItWorksPage はタグ4、profilePage はタグ5）。
- [ ] サインインは必須のまま、必要性（フレンド/同期/復元）がボタンと同一画面で説明される。
- [ ] スクリーンタイム/通知/カメラが最終ページで説明付きで順に要求され、スクリーンタイム未認可では完了できない（Try Again）。
- [ ] 通知/カメラは拒否（=スキップ）しても完了できる。
- [ ] アプリ選択は見送り（完了後ガイドも見送り）と明記済み。

- [ ] **Step 4: push ＋ ユーザーへ報告**（Xcode ビルド・シミュレータ確認はユーザー側）

---

## Self-Review（計画著者による点検）

- **Spec coverage:** C-4-1 = T1、C-4-2 = T2（逸脱1点を明記）、C-4-5 + C-4-6 = T3。C-4-3/4/7 は理由付きで見送り明記。§5.1-2（サインイン必須）に整合。
- **Placeholder scan:** 「適切に〜」等なし。全ステップ exact before/after。
- **型/シンボル整合:** `HowItWorksPage`/`SignInBenefitRow`/`FinalPermissionRow` は本計画内で定義→参照が一致。既存依存: `model.hasScreenTimeAuthorization`（AppModel.swift:352, public computed）、`model.requestScreenTimeAuthorization()`（:1069）、`model.completeOnboarding()`（:410）、`model.requestScreenTimeReportRefresh()`、`Haptics.success()`（既存使用箇所と同じ）。`UNUserNotificationCenter.requestAuthorization` async / `AVCaptureDevice.requestAccess(for:)` async は iOS 15+（本アプリは `.onChange(of:initial:)` 使用 = iOS 17+）。
- **検証可能性:** Core 変更なしのため `swift test` は回帰確認のみ。アプリ層は差分突合＋ユーザー側 Xcode ビルド（メモリ [[phase1-verification-gap]] のとおり）。
- **リスク:** (1) ページ挿入は固定タグ 0-3 の後ろ＝計算値タグ（profilePage/lastPage）が自動追従するため index ずれなし。`primaryTitle` の `case 2`（WastedTimePage）も影響なし。(2) 権限の直列要求は決定済み権限では即 return するため再実行安全。(3) `screenTimeAuthorizationFailed` は成功時に必ず false へ戻すためエラー表示が残留しない。
- **スコープ:** 1ファイル・3タスク。Codex には T1+T2 / T3 の2回に分けて委譲（約2タスク/回の停止傾向に対応）。

# ScreenLog Friend-Group Feature — Adversarial Code Review

Branch: `feature/friend-group-limits` (PR #8). Scope: `git diff main..HEAD` (~4,700 LOC).
Method: 8-dimension multi-agent review → each finding adversarially verified against the real code → synthesized. 24 agents. 15 findings raised, **13 survived verification** (1 critical, 5 high, 6 medium, 1 low).

> Context: the distributed / OS-dependent behavior (pool enforcement, DeviceActivity extension, silent push, storage RLS) is NOT device-testable in this environment, so this review is the primary quality gate for that logic. The bugs cluster exactly there — mostly **silent under-blocking** (fail-open).

## Merge gate

### Must-fix before merge (blocking)
- **C1** — pool override cleared on transient network error → member unshielded while pool still exhausted (fails open on the headline feature). `AppModel.applyPoolState`.
- **H1** — DeviceActivity extension's own shield path ignores `poolExhaustionOverrides` → force-shield dropped whenever any unblock window ends. `ScreenLogActivityMonitorExtension/ExtensionBlockingSupport.swift`.
- **H2** — `myGroups` never loaded at launch / on remote-change → pool enforcement + exhaustion push dead until the Groups tab is opened. `AppModel.load()/handleRemoteChange()`.
- **H3** — kicked member silently rejoins via the still-valid invite code (`redeem` resets `left_at`, no kick/leave distinction). `0001_group_social_layer.sql`. (auth bypass)
- **H4** — group-request selfie uploaded to a random-UUID path the read-RLS can't match → approvers never see the photo (accountability lost). `AppModel.uploadGroupRequestPhoto`.
- **H5** — `deleteGroup` (owner path) doesn't tear down the owner's local block / Keychain / override → owner permanently blocked with no escape (password never shown). `AppModel.deleteGroup`.

### Strongly recommended (cheap; fix before merge)
- **M1** — ex-member still authorized to approve a pending group request (recipient_ids frozen at send). `respond_group_time_request` (0002). Add `is_group_member` re-check.
- **M2** — collecting an approved *group* request routes through the *friend* `collect_time_request` RPC → inconsistent server state. `AppModel.collectFriendRequest`. Branch on `socialGroupID`.
- **M4** — SECURITY DEFINER functions don't pin `search_path` (guaranteed Supabase lint failure). All RPCs in 0001/0002/0003. Add `set search_path = public, pg_temp`.

### Follow-up / acceptable
- **M3** — unvalidated `owner_time_zone` can brick a group's pool accounting (self-inflicted, swallowed by `try?`, backstop still enforces). Validate in `create_group` + defensive `group_owner_day`.
- **M5** — `deleteBlockGroup` doesn't drop the matching `poolExhaustionOverride` → stale force-block on same-day leave/rejoin (fail-safe, self-heals ≤24h).
- **M6** — three stacked `.sheet` modifiers in `RootView` → a group-invite link silently no-ops if another sheet is open.
- **L1** — "Update apps" reopens the picker empty (existing selection not pre-loaded).

## Notes on confidence
- **H4** rests on the author's own in-code comment + the deliberate friend-flow path convention; the literal storage-RLS policy lives in the Supabase dashboard (not the repo), so it is strong-but-not-repo-verifiable. Confirm against the actual `request-photos` read policy.
- C1 / H1 / H2 share the pool-enforcement path and should be fixed and reasoned through together.

_Full per-finding triggers and fixes were produced by the review workflow run `wf_36982015-0d5`._

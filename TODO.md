# Family To-Do - Master Action Plan

## Rules of Engagement
1. Strictly Sequential: implement EXACTLY ONE task at a time.
2. No Scope Creep: do not modify code outside the current task scope.
3. Verify & Commit: after each task, run regression checks, commit, then mark `[x]`.
4. CloudKit Safety First: if sync behavior is uncertain, stop and validate before continuing.

## Current Repo Snapshot (2026-03-25)

- Implemented through `P2.8`: Phase 1 integrity/cloud fixes, Shopping Bundles, and contextual onboarding are live in the codebase.
- Production households now start empty; sample/demo seeding is restricted to explicit UI-test launch arguments.
- Household leave/delete flows are local-first with pending remote cleanup replay and stale CloudKit recovery guards.
- Retro Dark, Retro Light, and Paper theme support has been rolled out broadly; new UI is expected to wire theme fonts from day one.
- Smart notifications are live outside the original master-plan sequence: optional due-time reminders, `Default reminder time`, and a non-spammy digest that only fires when tasks are due.
- Multi-user sync is partially hardened, but still not considered fully closed until real-device owner/participant behavior is consistent and predictable.
- Remote-update UI has partially shipped (`Tasks`/`Shopping` inline feedback + shopping banner), but it still needs a dedicated polish pass after sync reliability is acceptable.
- Immediate roadmap focus has changed: sync reliability, update UX cleanup, notification-permission timing, onboarding refresh, and invite flow polish now take precedence over previously planned polish-only work.

## Immediate 2026-03-25 Priorities (Highest Priority)

- [ ] **I1.0 Multi-Device Sync Stabilization** ([Details](TODO_DETAILS.md#i10))
Description: Finish hardening owner/participant sync so `Tasks`, `Shopping`, and `Ideas` update reliably in both directions on physical devices without pull-to-refresh rescue behavior.
Acceptance Criteria: Real two-device testing confirms `owner -> participant` and `participant -> owner` are both reliable for create/edit/assign/complete/bought/unbought flows; visible screens refresh dependent data correctly; owner-side latency is no longer dramatically worse than participant-side behavior.
Regression Risk: Partial hydrations, delayed owner-private propagation, stale member/category context, and duplicate push-driven UI updates.

- [ ] **I1.1 Remote Update UX Cleanup** ([Details](TODO_DETAILS.md#i11))
Description: Rework how remote sync feedback is shown in the app so it stays informative without breaking headers or bottom-tab labels.
Acceptance Criteria: `Tasks`, `Shopping`, and `Ideas` use one consistent lightweight on-screen sync affordance; shopping off-screen additions can still surface a top banner; bottom-tab labels remain visually stable on narrow iPhones and never split awkwardly.
Regression Risk: Sync looks invisible after changes, headers become too subtle, or navigation labels still wrap/truncate under theme typography.

- [ ] **I1.2 Notification Permission Gating by Household Size** ([Details](TODO_DETAILS.md#i12))
Description: Stop prompting for notification permission too early; request it only when notifications can provide real shared-household value.
Acceptance Criteria: Solo households are never asked during early `Add Item` flows; notification permission is requested only after the household becomes multi-member or at another clear shared-value moment; prompt timing feels intentional instead of premature.
Regression Risk: Missing the best permission moment, delaying useful reminders too long, or showing the prompt multiple times around membership changes.

- [ ] **I1.3 Welcome Carousel Refresh** ([Details](TODO_DETAILS.md#i13))
Description: Refresh the opening carousel using the recommendations already captured in `onboarding-flow-claude-analysis.md`.
Acceptance Criteria: Carousel content, visual hierarchy, and adaptive layout follow the new analysis; onboarding better explains real app value before auth; no legacy layout problems such as fixed screen-height assumptions remain.
Regression Risk: Carousel churn delays launch work, introduces theme/layout regressions, or weakens the polished first impression we already have.

- [ ] **I1.4 Invite Screen Remodel** ([Details](TODO_DETAILS.md#i14))
Description: Redesign the invite flow screen so creating and sharing a household invite feels clear, modern, and trustworthy.
Acceptance Criteria: Invite screen hierarchy, actions, and copy are easier to scan; invite-code / QR / sharing actions are obvious; the flow matches the actual code-based invite model already used by the app.
Regression Risk: Share flow confusion, mismatched copy vs implementation, or accidental regressions in the current invite/token mechanics.

- [ ] **I1.5 Invite Guidance / "How to Invite" UX** ([Details](TODO_DETAILS.md#i15))
Description: Add clear in-app explanation so a household owner understands how to invite another person and what the other person needs to do.
Acceptance Criteria: Users can discover how to invite someone without guessing; the app explains code/QR sharing at the right moment; invite guidance does not feel like dense documentation.
Regression Risk: Over-explaining with too much text, or placing help too deep so users still miss it.

- [ ] **I1.6 Payments Rollout Readiness** ([Details](TODO_DETAILS.md#i16))
Description: Once sync, invite, and onboarding flows are stable, finish the minimum architecture and product readiness needed to turn on paid access.
Acceptance Criteria: Household-level premium model, entitlement resolution, and payment integration plan are all ready enough that app monetization can be introduced without reopening core sync/design decisions.
Regression Risk: Introducing monetization before collaboration flows are trustworthy, or leaking user-level payment assumptions into a household-first product model.

- [ ] **I1.7 Member-Driven Invites** ([Details](TODO_DETAILS.md#i17))
Description: Allow every active household member, not only the owner, to invite additional people into the household.
Acceptance Criteria: Any active member can open the invite flow, generate or access a valid invite, and onboard another person without owner intervention; ownership-sensitive actions remain protected where still required.
Regression Risk: Accidentally widening permissions too far, confusing owner/member responsibilities, or breaking current invite-token validity assumptions.

- [ ] **I1.8 Per-User Recommended Task Limit** ([Details](TODO_DETAILS.md#i18))
Description: Ensure the recommended/WIP task limit is enforced per assignee, not against all household tasks combined.
Acceptance Criteria: Recommendation and guard logic counts only tasks assigned to the relevant user when deciding whether another task can move into the active lane; one member hitting the limit never blocks unrelated members.
Regression Risk: Regressions in existing WIP validation, incorrect counting for unassigned tasks, or inconsistent UI guidance vs store enforcement.

- [ ] **I1.9 Shared Household Metadata Editing** ([Details](TODO_DETAILS.md#i19))
Description: Allow every active household member to change the household name and icon, not only the owner.
Acceptance Criteria: Any active member can rename the household and change its icon; updates sync correctly to all devices; owner-only restrictions remain only where product truly needs them.
Regression Risk: Reusing owner-only update paths incorrectly, creating metadata write conflicts, or exposing stale household info after remote updates.

## Pulled-Forward Watchlist From Phase 3

- [ ] **P3.3 Evaluate Zone-Scoped Subscriptions** ([Details](TODO_DETAILS.md#p33))
Why it may matter earlier: if phase-2 sync hardening still leaves owner/participant notification blind spots, this becomes a sync-relevant investigation instead of a distant polish item.

- [ ] **P3.1 Versioned SwiftData Schema Framework** ([Details](TODO_DETAILS.md#p31))
Why it may matter earlier: if we continue changing local persistence or add payments/premium state soon, explicit schema versioning becomes more useful before launch, not after.

## MVP 1.0 Readiness Track (Highest Priority)

### Architecture Assessment Before MVP Testing

- **Multiplayer sync foundation is good enough for physical-device testing**: Tasks, Shopping, and Ideas already use cache-first loading, background CloudKit replay, tombstones, and `updatedAt`-based last-writer-wins merge.
- **Push infrastructure is only partially ready**: remote notifications refresh the app and show generic shared-change banners, but they do not yet send targeted household event copy such as `Task assigned to you`, `Member joined`, or `Poke from <Name>`.
- **Shopping anti-spam is partially covered**: shared remote updates are aggregated today, but the logic is still generic and not yet explicitly productized around shopping-only batching rules.
- **Live shopping presence is a good architectural fit, but needs a dedicated household-presence write path**: `Household` is already cache + CloudKit synced, but the current metadata update flow is owner-only and cannot be reused as-is for any member starting shopping.
- **English-only launch is aligned with current direction**: the app is mostly hardcoded in English and does not have active localization plumbing, but a few remaining non-English strings still need cleanup before release.
- **Monetization schema is NOT ready yet**: `Household` does not currently expose `isPremium` or `subscriptionTier` in the domain model, SwiftData cache, CloudKit mapping, or schema.

### MVP 1.0 Stabilization Tasks

- [ ] **M1.0 Live Shopping Mode / Last-Minute Alert** ([Details](TODO_DETAILS.md#m10))
Description: Add a shared household shopping-presence state that lets one member announce “I’m at the store” so other members can quickly add last-minute items, with real-time UI state in Shopping and targeted partner notifications.
Acceptance Criteria: `Household` gains nullable `activeShopperId` through the full persistence chain; Shopping shows the correct top banner state for idle / current shopper / other-member shopper; starting shopping updates local UI immediately and syncs through CloudKit; finishing shopping or clearing the shopping list resets the state; active shopper mode can keep the screen awake; other members receive a clear “at the store” notification without shopping-change spam.
Regression Risk: Reusing owner-only household-edit paths will block non-owner members; stale presence may get stuck if reset paths are incomplete; overly generic push handling may notify the wrong user or fail to distinguish shopping presence from normal shared edits.

- [ ] **M1.1 Physical Multiplayer Soak Testing**
Description: Run real-device, two-user household testing for simultaneous edits across Tasks, Shopping, and Ideas to validate current cache-first + CloudKit replay behavior under realistic household use.
Acceptance Criteria: Two physical devices signed into different accounts can join the same household and reliably observe partner changes after create/edit/delete/promote/poke actions; simultaneous edits converge without ghost records, silent data loss, or permanently stuck pending mutations; leave/delete/invite flows remain stable during and after sync churn.
Regression Risk: Race conditions may surface only under real-device timing, especially around stale snapshots, repeated writes, app backgrounding, or reconnect-after-offline flows.

- [ ] **M1.2 Targeted Household Event Notifications**
Description: Replace the current generic shared-change notification experience with explicit household event notifications for `user invited`, `member joined household`, `task assigned to me`, and `poke reminders`, while preserving self-noise suppression.
Acceptance Criteria: Remote partner actions generate specific, human-readable notifications instead of generic `shared update` copy; invite/join/assignment/poke events can be differentiated in both lock-screen and in-app behavior; self-triggered changes never notify the actor; owner/member flows work correctly across private/shared CloudKit database boundaries.
Regression Risk: Duplicate notifications, wrong-recipient delivery, or missing notifications due to incomplete coverage of private-vs-shared database events.

- [ ] **M1.3 Shopping Notification Batching Policy**
Description: Formalize shopping-list notification behavior so partner shopping changes are informative but never spammy, especially during rapid add/buy bursts.
Acceptance Criteria: Shopping notifications are batched or rate-limited with a clearly defined aggregation window and copy strategy; multiple item changes in a short session never produce a burst of separate notifications; non-shopping notifications (assignment, poke, household join) remain more immediate when appropriate.
Regression Risk: Over-batching may hide meaningful partner activity, while under-batching will make shared shopping feel noisy and annoying.

- [ ] **M1.4 English-Only Release Audit**
Description: Audit the codebase for remaining non-English or inconsistent strings and normalize all user-facing copy to English for the v1.0 MVP launch.
Acceptance Criteria: All visible UI strings, recovery messages, diagnostics surfaced to users, invite/share labels, and household/member flows are in English; no localization framework work is introduced yet; layouts remain stable in all existing themes after the copy sweep.
Regression Risk: Hidden fallback/system messages or rarely hit diagnostics may remain untranslated and only appear during edge-case failures in production.

- [ ] **M1.5 Household-Level Premium Schema Foundation**
Description: Add monetization-ready premium state to `Household` rather than to `User`, so Premium can be inherited by all members of a household owned by a paying owner.
Acceptance Criteria: `Household` gains a durable premium field in the full chain (domain model, SwiftData cache, CloudKit mapping, schema); preferred shape is `subscriptionTier` rather than a single boolean to keep room for future plans; existing households migrate safely with a backward-compatible default such as `free`; no paywall UI is required yet.
Regression Risk: Schema/mapping drift or migration mistakes could break household fetch/save paths before monetization is even turned on.

- [ ] **M1.6 Premium Inheritance Rules (Household Scope)**
Description: Define and implement the app-side rules for how Premium is resolved from current household metadata so all invited members inherit the owner-paid benefits inside that household.
Acceptance Criteria: Runtime feature gating reads premium state from the active household, not only the signed-in user; leaving or switching households updates premium access immediately; the model is compatible with future RevenueCat integration without rewriting the household-level entitlement contract.
Regression Risk: Mixed household/user entitlement logic can create inconsistent access, especially when a user belongs to multiple households in the future.

- [ ] **M1.7 RevenueCat Preparation Layer**
Description: Prepare the architecture for future RevenueCat wiring without shipping billing UI yet by identifying the integration seam between remote entitlement state and household-level premium persistence.
Acceptance Criteria: A clear integration point exists where future RevenueCat owner entitlements can map into `Household.subscriptionTier`; no billing SDK is required in this task; the decision is documented well enough that monetization can start without reworking household sync primitives.
Regression Risk: If this seam is not defined early, later billing work may leak user-level assumptions into the household data model and cause expensive refactors.

## Bugfixes & Polish (High Priority)

- [x] **Fix Shopping List Input Padding**
Description: When typing a new item in the Shopping list, the `TextField` padding/alignment doesn't match the saved items. It lacks the empty circle placeholder, causing the text to shift left and break the vertical alignment.
Acceptance Criteria: The `TextField` row must have the exact same leading spacing/layout (e.g., an invisible circle or matching padding) as the saved items so the text perfectly aligns vertically.

- [x] **Optimize Tasks "Clear All" Performance**
Description: In Tasks -> Completed, tapping "Clear All" deletes tasks very slowly (one by one with individual animations).
Acceptance Criteria: Mass deletion must be instant. Optimize the deletion loop (e.g., remove per-item animation, use a single batch delete, or wrap the state update in a single `withAnimation` block).

- [x] **Remove redundant "(+)" in Idea Categories**
Description: In `More -> Idea Categories`, the "New category" button has a built-in plus icon, but the text also says `(+) New category`.
Acceptance Criteria: Change the text string from `(+) New category` to just `New category`.

- [x] **Fix Invite Token wipe on Dev Deploy**
Description: Every time we deploy to the dev environment, the Invite Token gets deleted/wiped. This was supposed to be fixed but is still breaking.
Acceptance Criteria: Investigate the token storage/generation or deployment scripts and ensure the Invite Token persists across deployments.

## Phase 1: Data Integrity & CloudKit (High Priority)

- [x] **P1.1 Replace Silent SwiftData Saves** ([Details](TODO_DETAILS.md#p11))
Description: Replace `try? modelContext.save()` with a shared `saveContextOrSetError(...)` pattern in all stores.
Acceptance Criteria: No silent save calls remain in target stores; failures are logged and surfaced via store error state.
Regression Risk: Local writes may fail visibly; verify create/edit/delete still works for Tasks, Shopping, Backlog.

- [x] **P1.2 Replay Pending Sync Mutations** ([Details](TODO_DETAILS.md#p12))
Description: Add `flushPendingSync()` in stores to replay `pendingUpload` and `pendingDelete` after load/reconnect.
Acceptance Criteria: Offline-created/edited/deleted records sync successfully after reconnect/app restart.
Regression Risk: Duplicate operations or resurrection of deleted records; test offline -> restart -> reconnect flows.

- [x] **P1.3 Add Conflict Policy in Merge (LWW)** ([Details](TODO_DETAILS.md#p13))
Description: Update merge logic to compare `updatedAt` instead of unconditional local overwrite.
Acceptance Criteria: Newer cloud changes are not overwritten by stale local pending data.
Regression Risk: Unexpected task/item state flips on multi-device edits; test concurrent edits on two devices.

- [x] **P1.4 Align Cache Delete Semantics** ([Details](TODO_DETAILS.md#p14))
Description: Ensure cache loads filter tombstones consistently (`pendingDelete`) across stores, including Shopping.
Acceptance Criteria: Deleted items do not reappear from cache during offline or cold start.
Regression Risk: Missing records due to over-filtering; verify restore and recent-item behaviors.

- [x] **P1.5 Remove N+1 Cache Sync Queries** ([Details](TODO_DETAILS.md#p15))
Description: Refactor `syncToCache` to single/batched fetch + in-memory merge (Task/Shopping/Backlog).
Acceptance Criteria: Sync path no longer runs per-record fetch loops.
Regression Risk: Partial cache updates; verify large sync snapshots apply correctly.

- [x] **P1.6 Add CloudKit Query Pagination** ([Details](TODO_DETAILS.md#p16))
Description: Add paginated query helpers (`resultsLimit` + cursor loop) and apply to key fetch paths.
Acceptance Criteria: Full dataset is returned beyond single-page limits for Tasks/Shopping/Backlog/Members and invite lookup queries.
Regression Risk: Missing pages or duplicates; test with seeded large datasets.

- [x] **P1.7 Move Member Color Migration Off Hot Path** ([Details](TODO_DETAILS.md#p17))
Description: Remove write-side migration from every `fetchMembers()` and run one-time migration bootstrap.
Acceptance Criteria: Member fetch no longer performs migration writes on normal path.
Regression Risk: Color defaults/regression in old records; test existing households on upgrade.

- [x] **P1.8 Harden Invite Security** ([Details](TODO_DETAILS.md#p18))
Description: Increase invite code entropy (length 8), enforce usage/attempt controls, update role constraints for InviteToken.
Acceptance Criteria: Invite create/redeem/revoke still works; security exposure reduced.
Regression Risk: Invite flow breakage; test link/QR/code redemption on two accounts.

- [x] **P1.9 Complete Push E2E Bridge** ([Details](TODO_DETAILS.md#p19))
Description: Add `didReceiveRemoteNotification` forwarding in AppDelegateBridge and close CloudKitSubscriptionManager handling loop.
Acceptance Criteria: Remote notifications trigger app refresh/banner pipeline.
Regression Risk: Notification spam or self-notify regressions; test foreground/background behavior.

- [x] **P1.10 Targeted Bulk CloudKit Operations** ([Details](TODO_DETAILS.md#p110))
Description: Add batched `CKModifyRecordsOperation` for high-volume write paths (seeding/reorder/bulk updates).
Acceptance Criteria: Bulk operations use fewer round trips and maintain correctness.
Regression Risk: Partial-save edge cases; test failure handling and rollback expectations.

## Phase 2: Core Features & UX (Medium Priority)

- [x] **P2.1 Engaging Empty States** ([Details](TODO_DETAILS.md#p21))
Description: Implement two-tier FTUX empty states (tutorial + standard) for Shopping, Tasks Active, and Ideas, plus standard Completed-empty handling in Tasks.
Acceptance Criteria: `@AppStorage` flags control tutorial visibility, tutorial CTA buttons persist "seen" state, and standard `ContentUnavailableView` copy/icons render for returning users.
Regression Risk: Empty-state branching may hide real data or show wrong copy; test first-run vs returning-user flows and tab switches.

- [x] **P2.2 Conversational Task Filter Chips** ([Details](TODO_DETAILS.md#p22))
Description: Add conversational assignee chips (`All tasks`, `My tasks`, `[Name]'s tasks`) with ID-based filter state and integration with Active/Completed tabs.
Acceptance Criteria: Chips filter both task tabs correctly, `My tasks` appears only when current member is resolvable, and no duplicate current-user chip is shown.
Regression Risk: Filter desync during member/session changes; test toggle cycles, member list updates, and filtered empty states.

- [x] **P2.3 Poke Data Model & Mapping** ([Details](TODO_DETAILS.md#p23))
Description: Add `lastPokedAt` through the full persistence chain (domain model, SwiftData cache, CloudKit mapping, schema, validator).
Acceptance Criteria: `lastPokedAt` round-trips `Task -> CachedTask -> CloudKit -> Task`, including nil-safe behavior when the field is absent.
Regression Risk: Schema drift or mapping decode failures; validate via CI schema gate and model round-trip tests.

- [x] **P2.4 Poke Logic & Cooldown UX** ([Details](TODO_DETAILS.md#p24))
Description: Implement poke store logic (`canPoke`, `pokeTask`) and leading swipe UX with once-per-day cooldown and anti-multitap guards.
Acceptance Criteria: Poke action is visible only for tasks assigned to other members, same-day repeat poke is blocked, and successful poke persists locally and through sync.
Regression Risk: Duplicate poke mutations or false cooldown lockouts; test self-assigned/unassigned tasks, rapid taps, and day-boundary behavior.

- [x] **P2.5 Gentle Rewards Expansion** ([Details](TODO_DETAILS.md#p25))
Description: Expand `CelebrationManager` with deterministic decision tiers (milestone > surprise > fallback), weekly surprise cap, and Tasks completion integration.
Acceptance Criteria: Completion celebrations use tier priority, weekly surprise limit is enforced, and UI triggers respect `celebrationsEnabled`.
Regression Risk: Celebration spam or missing feedback on completion; test milestone (5/10), surprise eligibility window, and disabled-celebrations mode.

- [ ] **P2.6 Round-Robin Recurring Task Rotation** ([Details](TODO_DETAILS.md#p26))
Description: Parked on `feature/recurring-tasks`; not part of the active roadmap while post-P2.7 / UI polish work continues on `feature/next-features`.
Acceptance Criteria: Resume only from the parked branch if/when recurring work is restarted.
Regression Risk: Branch drift between parked recurring work and active P2.7 changes; re-evaluate before reviving.

- [x] **P2.7 Shopping Bundles End-to-End** ([Details](TODO_DETAILS.md#p27))
Description: Implement ShoppingBundle domain/cache/store/cloud plus polished UX: header bundles icon, long-press quick add, management screens, and feedback toast.
Acceptance Criteria: Bundle CRUD works with `itemsJSON` persistence, bundles are accessible from Shopping header, long-press on `+ Add Item` opens native bundle picker, and selecting bundle shows confirmation (`Added <Bundle> (<N> items)`).
Regression Risk: Serialization mismatch, duplicate inserts, or hidden affordances; test repeated quick-add, discoverability, and local/cloud parity.

- [x] **P2.8 Contextual Onboarding (TipKit)** ([Details](TODO_DETAILS.md#p28))
Description: Implement native TipKit onboarding with contextual, sequential guidance for Shopping and Ideas, plus Tasks first-run guidance via improved empty state and swipe-actions learning.
Acceptance Criteria: `Tips.configure()` starts safely with immediate display frequency, TipKit progress resets only on real user/household context changes, Shopping runs `first add -> recently purchased -> bundles -> quick add`, Ideas runs `create category -> add idea -> assign -> promote`, and Tasks routes empty-state users to Ideas while preserving the swipe tip for non-empty active lists.
Regression Risk: Overlapping popovers, stale tip state across users/households, or tips blocking primary actions; validate sequencing, dismissal, and empty-state routing.

- [ ] **P2.9 Push Message Enrichment via Activity Log** ([Details](TODO_DETAILS.md#p29))
Description: Enrich push/in-app updates from ActivityLog with personalized copy and non-invasive in-app banner behavior.
Acceptance Criteria: System pushes are explicit and personalized (`<Name> completed...` / `<Name> bought...`), in-app top banner appears for remote partner actions and auto-dismisses in ~3s, and self-noise + dedup rules remain enforced.
Regression Risk: Duplicate/stale notifications or intrusive in-app UX; test lock-screen copy, foreground banners, and two-device sync storms.

- [ ] **P2.10 Activity Log End-to-End** ([Details](TODO_DETAILS.md#p210))
Description: Implement ActivityLog model/cache/store/view with timeline-style UI, clear navigation placement, and store-level action logging.
Acceptance Criteria: Logs are recorded with required actor fields, More tab shows `Activity Log` above technical settings, timeline rows include actor avatar/initials + readable action + relative time, and empty state is friendly.
Regression Risk: Missing attribution, noisy duplicates, or unreadable feed layout; test multi-user ordering, relative-time rendering, and empty/logged states.

## Phase 3: Polish & Future (Low Priority)

- [ ] **P3.1 Versioned SwiftData Schema Framework** ([Details](TODO_DETAILS.md#p31))
Description: Introduce `VersionedSchema` + migration plan scaffolding.
Acceptance Criteria: App boots with explicit schema versioning path.
Regression Risk: Migration boot regressions; test upgrade from existing local stores.

- [ ] **P3.2 Evaluate Relationship/Cascade Migration** ([Details](TODO_DETAILS.md#p32))
Description: Assess and optionally introduce relationship-based cascade delete strategy.
Acceptance Criteria: Decision documented and, if implemented, orphan records are eliminated safely.
Regression Risk: Data loss from aggressive cascades; test household/category deletion paths.

- [ ] **P3.3 Evaluate Zone-Scoped Subscriptions** ([Details](TODO_DETAILS.md#p33))
Description: Reassess DB-wide subscription vs zone-specific subscriptions for future multi-household support.
Acceptance Criteria: Technical decision captured with rollout constraints.
Regression Risk: Notification blind spots if switched incorrectly.

- [ ] **P3.4 Sharing Role UX Enhancements** ([Details](TODO_DETAILS.md#p34))
Description: Add concrete household role UX: visible role badges and owner-only management actions for role change/transfer/remove.
Acceptance Criteria: Member rows show role chips (`Owner`, `Member`, `Read-only`), owner gets action sheet (`Change Role`, `Transfer Ownership`, `Remove from Household`), and destructive actions require explicit red confirmation alerts.
Regression Risk: Permission leaks or accidental destructive actions; test owner/member guardrails and confirmation flows.

- [ ] **P3.5 Guest Data Protection Hardening** ([Details](TODO_DETAILS.md#p35))
Description: Evaluate and apply stronger on-device data protection for guest/local storage mode.
Acceptance Criteria: Protection policy documented and enabled where feasible.
Regression Risk: Startup/access regressions on locked device states.

- [ ] **P3.6 Remaining UX Polish** ([Details](TODO_DETAILS.md#p36))
Description: Close remaining UX quality gaps across empty states, haptics, and dark-mode readability.
Acceptance Criteria: Every empty tab has polished icon + encouraging copy, key actions emit consistent haptics (success/light/rigid), and tags/categories keep readable contrast in dark mode and custom themes.
Regression Risk: Theme-specific regressions and inconsistent tactile feedback; run cross-tab, cross-theme smoke validation.

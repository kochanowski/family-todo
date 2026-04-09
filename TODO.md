# Family To-Do - Master Action Plan

## Rules of Engagement
1. Strictly Sequential: implement EXACTLY ONE task at a time.
2. No Scope Creep: do not modify code outside the current task scope.
3. Verify & Commit: after each task, run regression checks, commit, then mark `[x]`.
4. CloudKit Safety First: if sync behavior is uncertain, stop and validate before continuing.

## Current Repo Snapshot (2026-03-25)


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


## Phase 3: Polish & Future (Low Priority)

- [ ] **P3.5 Guest Data Protection Hardening** ([Details](TODO_DETAILS.md#p35))
Description: Evaluate and apply stronger on-device data protection for guest/local storage mode.
Acceptance Criteria: Protection policy documented and enabled where feasible.
Regression Risk: Startup/access regressions on locked device states.

- [ ] **P3.6 Remaining UX Polish** ([Details](TODO_DETAILS.md#p36))
Description: Close remaining UX quality gaps across empty states, haptics, and dark-mode readability.
Acceptance Criteria: Every empty tab has polished icon + encouraging copy, key actions emit consistent haptics (success/light/rigid), and tags/categories keep readable contrast in dark mode and custom themes.
Regression Risk: Theme-specific regressions and inconsistent tactile feedback; run cross-tab, cross-theme smoke validation.

- [ ] **P3.7 Post-MVP Household Sync Hardening** ([Details](TODO_DETAILS.md#p37))
Description: Preserve the current MVP-stable sync behavior, then finish the remaining owner/participant CloudKit work: owner trigger audit, delta-only hot paths, and startup/join reliability diagnostics.
Acceptance Criteria: Remaining sync work is implemented only after MVP, with owner/participant trigger paths, delta fallbacks, and startup recovery explicitly validated on two real devices / Apple IDs.
Regression Risk: Over-tuning sync after MVP could reintroduce latency, missed updates, or household bootstrap regressions; any follow-up must be staged and measured on-device.

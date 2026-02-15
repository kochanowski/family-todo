# ROADMAP

Last updated: 2026-02-15

## Release Goal (P0 + P1)
Ship stable MVP with:
- backlog-first tasks execution,
- strict WIP enforcement,
- complete household/member management basics,
- recurring chores generating backlog tasks,
- reliable bottom chrome behavior on iPhone.

## Now (P0 stabilization)
1. Session consistency and sign out reliability across all tabs.
2. Backlog-first task flow hardening:
   - assignee-required `NEXT`
   - atomic promotion
   - inline blocked-action UX
3. End-to-end household join/invite polish and error handling.
4. On-device validation for tab bar glass transition and hit-testing.

## Next (P1 completion)
1. Recurring chores polish:
   - richer recurrence presets UX
   - regression tests for schedule generation windows.
2. Backlog/Tasks UX refinement:
   - quick assignee chips
   - better recurring provenance in task detail.
3. CI/test expansion:
   - promotion atomicity tests
   - recurring metadata tests
   - task flow smoke tests.

## Deferred (Later backlog)
1. Quick Search across Shopping/Tasks/Backlog.
2. Weekly Home Pulse dashboard.
3. WidgetKit surfaces.
4. Siri / App Intents.
5. Smart suggestions and digest enhancements.

# ROADMAP

Last updated: 2026-02-15

## Now
- Stabilize floating chrome UX on real iPhone:
  - liquid glass visibility while scrolling,
  - no overlap with `+ Add item` and bottom list rows.
- Keep CI fast on PR: build + lint only.
- Keep nightly/manual full regression tests active.

## Next
- Add focused UI smoke tests for:
  - Shopping rapid entry,
  - Task add/complete flow,
  - Backlog category add/delete safeguards.
- Add a manual CI lane for cloud-sharing validation with `HPCloudKitEnabled=YES`.

## Later
- Revisit advanced sync conflict handling once multi-device edits are frequent.
- Reintroduce richer metrics and product docs only after MVP behavior is stable on device.

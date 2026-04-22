# Contributing

This repo uses `HousePulse` as the product name and `FamilyTodo` as the Xcode project name.

## Local Checks

Run the standard local verification after changes:

```bash
pre-commit run --all-files
```

Additional optional checks:

```bash
docker run --rm -v "$PWD":"$PWD" -w "$PWD" ghcr.io/realm/swiftlint:latest lint --quiet *
gh run list --limit 5
```

## Pre-commit

`pre-commit` is the default local gate. In this repo it currently runs:

- YAML and merge-conflict sanity checks
- trailing whitespace and EOF normalization
- SwiftLint via [`scripts/ci/run-swiftlint.sh`](scripts/ci/run-swiftlint.sh)
- SwiftFormat
- `xcodebuild` tests when `xcodebuild` is available

If SwiftFormat rewrites files, run `pre-commit run --all-files` again until clean.

## Branch Workflow

Repository-specific working rule from `AGENTS.md`:

1. implement the change
2. run `pre-commit run --all-files`
3. commit
4. push for non-docs-only changes
5. monitor GitHub Actions until green

Docs-only changes are the exception: commit them, but do not push unless requested.

## CI / GitHub Actions

Main operational workflows live in `.github/workflows/`.

- `ios-ci.yml`: main iOS build pipeline
- `cloudkit-schema.yml`: schema validation and promote flow
- `nightly.yml`: nightly regression run

Useful commands:

```bash
gh run list --limit 5
gh run view <run_id> --json status,conclusion,jobs
gh run view <run_id> --log-failed
```

## Docs Policy

- Keep active docs in English.
- Treat `AGENTS.md`, `STATUS.md`, `TODO.md`, and `TODO_DETAILS.md` as repo entrypoints.
- Put active reference material under `docs/active/`, `docs/setup/`, and `docs/adr/`.
- Put exploratory or historical material under `docs/archive/`.
- Avoid adding new standalone markdown files to the repo root unless they are true entrypoints.

## Scripts Policy

- Keep active CI and operational scripts under `scripts/ci/` and `scripts/cloudkit/`.
- Keep one-off Xcode project surgery helpers under `scripts/xcode/legacy/`.
- If you add or rename a script, update [`scripts/README.md`](scripts/README.md).
- If a config file or workflow calls a script, update that reference in the same change.

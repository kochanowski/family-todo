# Scripts

This directory contains helper scripts that are not part of the app runtime.

## Active Scripts

- `scripts/ci/run-swiftlint.sh`
  - When to use: local linting through `pre-commit`
  - Used by CI or pre-commit: pre-commit
  - Status: `active`

- `scripts/cloudkit/validate_schema.sh`
  - When to use: validate the CloudKit schema contract JSON before apply/promote
  - Used by CI or pre-commit: GitHub Actions schema gate and local manual runs
  - Status: `active`

- `scripts/cloudkit/apply_schema.sh`
  - When to use: apply the schema contract to CloudKit Development
  - Used by CI or pre-commit: GitHub Actions schema gate
  - Status: `active`

- `scripts/cloudkit/promote_schema.sh`
  - When to use: verify and promote schema behavior for Production, including system-managed types
  - Used by CI or pre-commit: GitHub Actions schema gate
  - Status: `active`

## Legacy Xcode Helpers

These scripts modify `FamilyTodo.xcodeproj/project.pbxproj` directly. They are manual, one-off
helpers kept only for history and emergency project surgery. They are not part of CI.

- `scripts/xcode/legacy/add-uitest-target.sh`
  - When to use: manual addition of a UI test target to the Xcode project
  - Used by CI or pre-commit: no
  - Status: `legacy`

- `scripts/xcode/legacy/add_areas_files.py`
  - When to use: manual addition of area-related files to the Xcode project
  - Used by CI or pre-commit: no
  - Status: `legacy`

- `scripts/xcode/legacy/add_files_to_xcode.rb`
  - When to use: manual insertion of new Swift files and groups into the project file
  - Used by CI or pre-commit: no
  - Status: `legacy`

- `scripts/xcode/legacy/add_household_files.py`
  - When to use: manual addition of household onboarding files to the project
  - Used by CI or pre-commit: no
  - Status: `legacy`

- `scripts/xcode/legacy/add_mvp_files.py`
  - When to use: manual addition of early MVP files to the project
  - Used by CI or pre-commit: no
  - Status: `legacy`

- `scripts/xcode/legacy/add_notification_file.py`
  - When to use: manual addition of `NotificationService.swift` to the project
  - Used by CI or pre-commit: no
  - Status: `legacy`

- `scripts/xcode/legacy/add_recurring_files.py`
  - When to use: manual addition of recurring-task files to the project
  - Used by CI or pre-commit: no
  - Status: `legacy`

- `scripts/xcode/legacy/add_xcode_files.py`
  - When to use: manual addition of authentication/session files to the project
  - Used by CI or pre-commit: no
  - Status: `legacy`

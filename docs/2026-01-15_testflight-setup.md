# TestFlight Build & iPhone Testing Guide

**Date:** 2026-01-15 11:40 UTC

## Summary
This guide explains where CI builds end up and how to test the app on a physical iPhone without using a local Mac/Xcode setup.

## Where the build goes
- CI runs in GitHub Actions using `.github/workflows/ios-ci.yml`.
- The `deploy-testflight` job uploads the IPA to TestFlight **only** on pushes to `main` and only when required secrets are configured.
- Every successful `deploy-testflight` run also uploads the IPA as a GitHub Actions artifact named `FamilyTodo-IPA`.

## Prerequisites
1. Apple Developer Program membership ($99/year).
2. App Store Connect app created (bundle identifier must match the provisioning profile).
3. GitHub repository secrets configured for TestFlight deployment:
   - `BUILD_CERTIFICATE_BASE64`
   - `P12_PASSWORD`
   - `KEYCHAIN_PASSWORD`
   - `PROVISIONING_PROFILE_BASE64`
   - `PROVISIONING_PROFILE_NAME`
   - `APPLE_TEAM_ID`
   - `APP_STORE_CONNECT_API_KEY_ID`
   - `APP_STORE_CONNECT_API_ISSUER_ID`
   - `APP_STORE_CONNECT_API_KEY_BASE64`

## How to publish a TestFlight build
1. Push to `main`.
2. Wait for GitHub Actions `iOS CI` to finish successfully.
3. In App Store Connect → TestFlight, confirm the build appears (first upload may need manual processing time).
4. Add internal testers and send invites.

## How to test on iPhone (no Mac)
1. Install **TestFlight** from the App Store on your iPhone.
2. Accept the TestFlight invite sent from App Store Connect.
3. Install the build from the TestFlight app and run it.

## Validation checklist
- GitHub Actions run is green (all jobs pass).
- TestFlight shows the latest build and it finishes processing.
- Build installs and launches on device.

## Risks & notes
- Provisioning profile must match the bundle identifier in the project.
- Certificates and profiles can expire; rotate them if uploads fail.
- Without a Mac, TestFlight is the only practical way to install on iPhone.

## Modified files
- `/home/wkochanowski/code/family-todo/FamilyTodo.xcodeproj/project.pbxproj`
- `/home/wkochanowski/code/docs/2026-01-15_testflight-setup.md`

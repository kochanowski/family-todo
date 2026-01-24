# TestFlight Step-by-Step (from zero to first install)

This guide assumes:
- You already have an active Apple Developer Program membership.
- You have nothing else set up yet (no App Store Connect app, no Bundle ID, no certs).
- The repo name can stay the same, but the app/scheme is now `HousePulse`.

If you want automation later, see:
- `docs/2026-01-15_testflight-setup.md`
- `docs/2026-01-17_fastlane-setup.md`
- `docs/2026-01-10_github-actions-setup.md`

## 0) Prerequisites

- macOS with Xcode installed.
- Two-factor auth enabled for your Apple ID (required by Apple).
- A real device to test (optional but recommended; simulator is not enough for many real-world behaviors).

## 1) Create the app in App Store Connect

1. Go to App Store Connect: https://appstoreconnect.apple.com
2. Go to "Apps" -> "+" -> "New App".
3. Fill in:
   - Platform: iOS
   - Name: HousePulse
   - Primary language: (choose)
   - Bundle ID: create/select later (you can create it now in Developer portal; see next step)
   - SKU: any unique string you control (e.g. `housepulse-ios-001`)
   - User Access: Full Access (you)
4. Create the app entry.

Notes:
- The "name" is what users see in TestFlight. You can change it later.
- The bundle identifier must match what you will set in Xcode.

## 2) Create a Bundle ID (App Identifier) in the Developer portal

1. Go to Apple Developer portal: https://developer.apple.com/account
2. Go to "Certificates, Identifiers & Profiles".
3. Identifiers -> "+" -> App IDs -> App.
4. Set:
   - Description: HousePulse
   - Bundle ID: choose a reverse-DNS identifier you own, e.g. `com.yourcompany.housepulse`
5. Enable capabilities you need (you can change later). For this project you will likely need:
   - iCloud (CloudKit)
   - Sign in with Apple (if used)
   - Push Notifications (if you will use notifications)
6. Save.

## 3) Configure Xcode project signing + bundle identifier

1. Open the project:
   - `open FamilyTodo.xcodeproj`
2. In Xcode:
   - Select the app target: `HousePulse`
   - Go to "Signing & Capabilities"
3. Set:
   - Team: your Apple Developer team
   - Bundle Identifier: the same as in step 2 (e.g. `com.yourcompany.housepulse`)
   - Enable "Automatically manage signing" (recommended for first TestFlight build)
4. Ensure "Version" and "Build" are set (General tab):
   - Version: e.g. `0.1.0`
   - Build: `1` (must increase each upload)

CloudKit:
- If you enable iCloud/CloudKit capability, Xcode may prompt you to create/select an iCloud container.
- Use a container like `iCloud.com.yourcompany.housepulse` and ensure it matches your bundle id strategy.

## 4) Create the first Archive

1. Select the scheme: `HousePulse`
2. Select "Any iOS Device (arm64)" (not a simulator).
3. Product -> Archive
4. Xcode will build an Archive and open the Organizer.

If Archive is disabled:
- Make sure you selected a device target (not a simulator).
- Confirm the scheme is an app scheme (HousePulse) and build configuration is Release for Archive.

## 5) Upload to TestFlight

In Organizer:
1. Select the newest archive.
2. Click "Distribute App".
3. Choose "App Store Connect".
4. Choose "Upload".
5. Follow prompts (Xcode will handle signing if "Automatically manage signing" is enabled).
6. Upload.

Then in App Store Connect:
1. Go to the HousePulse app -> TestFlight tab.
2. Wait for "Processing" to finish (can take 5-30 minutes).
3. If Apple asks for export compliance / encryption:
   - For most apps using standard Apple crypto only, you typically answer "No" for custom encryption.
   - If you are unsure, answer carefully and consider Apple docs.

## 6) Enable Internal Testing and install from TestFlight

1. In App Store Connect -> HousePulse -> TestFlight:
   - Create an "Internal Testing" group (or use the default).
2. Add testers:
   - Add your Apple ID email and any teammates (must have access or be invited).
3. Assign the build to the group.
4. On your iPhone:
   - Install the "TestFlight" app from the App Store.
   - Accept the invite / open the TestFlight link.
   - Install HousePulse from TestFlight.

## 7) Common blockers (quick fixes)

- "Bundle identifier is not available":
  - Change bundle id to something unique you own.

- "No signing certificate found":
  - Ensure you selected the correct Team and "Automatically manage signing" is enabled.
  - Xcode should create the needed certificates/profiles automatically.

- Upload rejected because build number already used:
  - Increment Build number in Xcode (General tab) and archive again.

- App uses CloudKit but crashes / cannot access containers:
  - Verify iCloud container exists and is enabled for the target.
  - Verify the CloudKit environment (Development vs Production) and that schema is configured.
  - See `docs/2026-01-10_cloudkit-setup-guide.md`.

## 8) Optional: automate uploads (Fastlane + GitHub Actions)

Once the manual flow works end-to-end, automation is worth doing.

High-level:
1. Create an App Store Connect API key (Users and Access -> Keys).
2. Store secrets in GitHub (repo settings -> Secrets).
3. Enable TestFlight deploy job in `.github/workflows/ios-ci.yml` (it is currently disabled/commented in this repo).
4. Use Fastlane lanes from `fastlane/Fastfile`.

Detailed references:
- `docs/2026-01-17_fastlane-setup.md`
- `docs/2026-01-10_github-actions-setup.md`


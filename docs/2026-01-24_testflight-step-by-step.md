# TestFlight Step-by-Step (from zero to first install)

This guide assumes:
- You already have an active Apple Developer Program membership.
- You have nothing else set up yet (no App Store Connect app, no Bundle ID, no certs).
- The repo name can stay the same, but the app/scheme is now `HousePulse`.

If you want automation later, see:
- `docs/2026-01-15_testflight-setup.md`
- `docs/2026-01-17_fastlane-setup.md`
- `docs/2026-01-10_github-actions-setup.md`

## 0) Prerequisites (no Mac / GitHub Actions only)

- You do NOT need a Mac/Xcode.
- Two-factor auth enabled for your Apple ID (required by Apple).
- A real iPhone to test on (TestFlight runs on device, not simulator).
- Admin access to this GitHub repo (to add Actions secrets).

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

## 3) Configure signing and uploads for GitHub Actions

Because you do not have Xcode, signing must be done in CI (GitHub Actions).

You need to create:
1) App Store Connect API key (for uploading builds to TestFlight)
2) An Apple Distribution certificate + App Store provisioning profile (for code signing)

### 3.1 Create App Store Connect API key (upload auth)

1. App Store Connect -> Users and Access -> Keys -> App Store Connect API
2. Generate API key
3. Save:
   - Issuer ID
   - Key ID
   - Download `.p8` (only once)

### 3.2 Create an Apple Distribution certificate WITHOUT a Mac

You can generate the private key and CSR on any machine (Linux/Windows via WSL is fine).

1. Generate a private key + CSR:
   ```bash
   openssl genrsa -out housepulse_dist.key 2048
   openssl req -new -key housepulse_dist.key -out housepulse_dist.csr -subj "/CN=HousePulse Distribution"
   ```
2. Apple Developer portal -> Certificates -> "+" -> Apple Distribution
3. Upload the CSR (`housepulse_dist.csr`)
4. Download the certificate as `.cer` (e.g. `distribution.cer`)
5. Convert `.cer` + private key -> `.p12`:
   ```bash
   openssl x509 -in distribution.cer -inform DER -out distribution.pem -outform PEM
   openssl pkcs12 -export \
     -inkey housepulse_dist.key \
     -in distribution.pem \
     -out housepulse_distribution.p12 \
     -passout pass:YOUR_P12_PASSWORD
   ```

### 3.3 Create an App Store provisioning profile

1. Apple Developer portal -> Profiles -> "+" -> App Store
2. Select your App ID (Bundle ID from step 2)
3. Select the Apple Distribution certificate you created in 3.2
4. Name the profile (remember the exact name; you will store it in GitHub secrets)
5. Generate and download `.mobileprovision`

## 4) Add GitHub Actions secrets (required)

GitHub repo -> Settings -> Secrets and variables -> Actions -> New repository secret:

App config:
- `APP_IDENTIFIER`: your bundle id, e.g. `com.yourcompany.housepulse`
- `TEAM_ID`: Apple Developer Team ID (Developer portal -> Membership)
- `PROVISIONING_PROFILE_NAME`: EXACT profile name from step 3.3

App Store Connect API key (upload auth):
- `APP_STORE_CONNECT_API_KEY_ID`: Key ID
- `APP_STORE_CONNECT_API_ISSUER_ID`: Issuer ID
- `APP_STORE_CONNECT_API_KEY_CONTENT`: base64 of the `.p8` file content

Signing (code signing in CI):
- `BUILD_CERTIFICATE_BASE64`: base64 of `housepulse_distribution.p12`
- `P12_PASSWORD`: the password you used when exporting the `.p12`
- `KEYCHAIN_PASSWORD`: any random password (used only on CI runner)
- `PROVISIONING_PROFILE_BASE64`: base64 of your `.mobileprovision`

Base64 helpers:
```bash
# macOS
base64 -i file.p8 | pbcopy

# Linux
base64 -w 0 file.p8
```

## 5) Trigger the TestFlight upload from GitHub Actions

This repo includes a `deploy-testflight` job in `.github/workflows/ios-ci.yml`.

1. Push to `main`.
2. Go to GitHub -> Actions -> workflow "iOS CI".
3. Ensure `deploy-testflight` runs and succeeds.
4. Go to App Store Connect -> TestFlight and wait for processing to finish.

CloudKit:
- If you enable iCloud/CloudKit capability, Xcode may prompt you to create/select an iCloud container.
- Use a container like `iCloud.com.yourcompany.housepulse` and ensure it matches your bundle id strategy.

## 6) Install from TestFlight on iPhone

1. App Store Connect -> HousePulse -> TestFlight:
   - Create an "Internal Testing" group (or use the default)
2. Add yourself as an internal tester and assign the new build to the group.
3. On iPhone:
   - Install the "TestFlight" app
   - Accept the invite
   - Install HousePulse

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

## Notes about this repo's CI implementation

- Upload is done via Fastlane lane `beta` in `fastlane/Fastfile`.
- Signing is done via a Distribution `.p12` + App Store `.mobileprovision` injected via GitHub Actions secrets.
- The workflow always runs build/tests; TestFlight upload runs only on pushes to `main`.

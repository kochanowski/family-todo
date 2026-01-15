# GitHub Actions Setup Guide

**Date:** 2026-01-10
**Project:** Family To-Do App
**Purpose:** Configure GitHub Actions CI/CD pipeline for iOS

---

## What is GitHub Actions?

**GitHub Actions** is GitHub's built-in CI/CD platform that:
- 🤖 **Automatically builds** your app on every commit
- ✅ **Runs tests** to catch bugs early
- 🚀 **Deploys to TestFlight** (optional) for beta testing
- 💰 **FREE tier**: 2000 minutes/month on macOS runners

**Why use it for Family To-Do App:**
- No macOS needed on your Manjaro machine
- Builds run in the cloud
- Catch issues before they reach production
- Automate TestFlight releases

---

## Pipeline Overview

The pipeline in `.github/workflows/ios-ci.yml` has **4 jobs**:

1. **build-and-test**: Builds app and runs unit tests
2. **swiftlint**: Checks code quality (optional)
3. **deploy-testflight**: Uploads to TestFlight (only on `main` branch)
4. **notify-failure**: Sends notification if build fails

**Trigger conditions:**
- Runs on every `push` to `main` or `develop` branches
- Runs on every `pull_request` to `main` or `develop`
- Can be manually triggered via GitHub UI

---

## Setup Steps

### Step 1: Update Project Settings in Workflow

Edit `.github/workflows/ios-ci.yml` and update these variables:

```yaml
env:
  XCODE_VERSION: '15.2'          # Match your Xcode version
  IOS_SCHEME: 'FamilyTodo'       # Your Xcode scheme name
  IOS_PROJECT: 'FamilyTodo.xcodeproj'  # Your project file
  IOS_DESTINATION: 'platform=iOS Simulator,name=iPhone 15,OS=17.2'
```

**How to find your scheme:**
1. Open Xcode
2. Click on scheme dropdown (top left, near Play button)
3. Copy the exact name

### Step 2: Update ExportOptions.plist

Edit `ExportOptions.plist` and replace placeholders:

```xml
<key>teamID</key>
<string>YOUR_TEAM_ID</string>  <!-- Replace with your Apple Team ID -->

<key>provisioningProfiles</key>
<dict>
    <key>com.yourname.familytodo</key>  <!-- Replace with your Bundle ID -->
    <string>YOUR_PROVISIONING_PROFILE_NAME</string>  <!-- Replace with profile name -->
</dict>
```

**How to find your Team ID:**
1. Go to [Apple Developer Portal](https://developer.apple.com/account)
2. Click **"Membership"**
3. Copy **"Team ID"** (e.g., `ABC123DEF4`)

---

## Step 3: Setup GitHub Secrets (for TestFlight deployment)

⚠️ **Required only if you want automatic TestFlight uploads**

GitHub Actions needs access to your Apple certificates and API keys. These are stored as **encrypted secrets**.

### 3.1 Export Apple Certificate (.p12)

On macOS (or via Xcode):

```bash
# 1. Open Keychain Access
# 2. Find your "Apple Distribution" certificate
# 3. Right-click → Export "Apple Distribution: Your Name"
# 4. Save as: Certificates.p12
# 5. Set a password (you'll need it later)

# 6. Convert to base64
base64 -i Certificates.p12 | pbcopy
# This copies base64 string to clipboard
```

Go to GitHub: **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

- **Name:** `BUILD_CERTIFICATE_BASE64`
- **Value:** Paste the base64 string

### 3.2 Certificate Password

Add another secret:
- **Name:** `P12_PASSWORD`
- **Value:** The password you set for the .p12 file

### 3.3 Keychain Password

Add another secret:
- **Name:** `KEYCHAIN_PASSWORD`
- **Value:** Any strong password (e.g., `MyStrongPassword123!`)

### 3.4 Export Provisioning Profile

On macOS:

```bash
# 1. Download your provisioning profile from Apple Developer Portal
# 2. It's usually named like: FamilyTodo_AppStore.mobileprovision

# 3. Convert to base64
base64 -i ~/Downloads/FamilyTodo_AppStore.mobileprovision | pbcopy
```

Add secret:
- **Name:** `PROVISIONING_PROFILE_BASE64`
- **Value:** Paste the base64 string

### 3.5 Apple Team ID

Add secret:
- **Name:** `APPLE_TEAM_ID`
- **Value:** Your Team ID (e.g., `ABC123DEF4`)

### 3.6 Provisioning Profile Name

Add secret:
- **Name:** `PROVISIONING_PROFILE_NAME`
- **Value:** Exact name of provisioning profile (e.g., `FamilyTodo AppStore`)

### 3.7 App Store Connect API Key

**Why:** Allows GitHub Actions to upload to TestFlight without 2FA prompts.

**Setup:**
1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Click **"Users and Access"**
3. Click **"Keys"** tab
4. Click **"Generate API Key"** (or request access from Account Holder)
5. Download the `.p8` file

**Convert to base64:**
```bash
base64 -i AuthKey_ABCD1234.p8 | pbcopy
```

Add secrets:
- **Name:** `APP_STORE_CONNECT_API_KEY_BASE64`
- **Value:** Paste base64 string

- **Name:** `APP_STORE_CONNECT_API_KEY_ID`
- **Value:** Key ID (e.g., `ABCD1234`)

- **Name:** `APP_STORE_CONNECT_API_ISSUER_ID`
- **Value:** Issuer ID (UUID format, found on same page)

---

## Step 4: Setup SwiftLint (Code Quality)

**SwiftLint** checks your Swift code for style issues.

Create `.swiftlint.yml` in project root:

```yaml
# SwiftLint Configuration
disabled_rules:
  - trailing_whitespace
  - line_length

opt_in_rules:
  - empty_count
  - force_unwrapping

excluded:
  - Pods
  - .build
  - .swiftpm

line_length:
  warning: 120
  error: 200

identifier_name:
  min_length:
    warning: 2
  max_length:
    warning: 60
```

**Install locally (optional):**
```bash
brew install swiftlint
```

---

## Step 5: Test the Pipeline

### 5.1 Push Code to GitHub

```bash
git add .
git commit -m "Add GitHub Actions CI/CD pipeline"
git push origin main
```

### 5.2 View Pipeline Status

1. Go to your GitHub repository
2. Click **"Actions"** tab
3. You should see a workflow run in progress

### 5.3 Check Build Logs

Click on the workflow run to see detailed logs for each job.

---

## Understanding the Workflow

### Job 1: build-and-test

**What it does:**
1. Checks out your code
2. Selects correct Xcode version
3. Resolves Swift Package dependencies
4. Builds the app (without code signing)
5. Runs unit tests on iOS Simulator
6. Uploads test results as artifacts

**When it runs:** On every push and PR

**Cost:** ~5-10 minutes of macOS runner time

### Job 2: swiftlint

**What it does:**
1. Installs SwiftLint
2. Checks Swift code for style violations
3. Reports issues in GitHub Actions log

**When it runs:** On every push and PR

**Cost:** ~1-2 minutes

### Job 3: deploy-testflight

**What it does:**
1. Imports Apple certificates and provisioning profiles
2. Increments build number automatically
3. Builds and archives app (with code signing)
4. Exports IPA
5. Uploads to TestFlight via App Store Connect API
6. Cleans up sensitive files

**When it runs:** Only on pushes to `main` branch (not PRs)

**Cost:** ~10-15 minutes

### Job 4: notify-failure

**What it does:**
- Runs if any job fails
- Prints error message
- Can be extended to send Slack/Discord notifications

---

## Monthly Usage Estimate

GitHub Free tier: **2000 minutes/month** on macOS runners

**Estimated usage for Family To-Do MVP:**
- 10 commits/week
- Each commit triggers: build-and-test (8 min) + swiftlint (2 min) = 10 min
- 1 TestFlight deploy/week: 15 min

**Monthly total:**
- Commits: 40 × 10 min = 400 min
- TestFlight: 4 × 15 min = 60 min
- **Total: ~460 minutes/month** ✅ Well within free tier

---

## Customizing the Pipeline

### Disable TestFlight Deployment

If you don't want automatic TestFlight uploads, comment out the job:

```yaml
# deploy-testflight:
#   name: Deploy to TestFlight
#   ... (entire job)
```

### Run on Different Branches

Change trigger in workflow:

```yaml
on:
  push:
    branches: [ main, feature/my-branch ]  # Add your branches
```

### Add Slack Notifications

In `notify-failure` job, add:

```yaml
- name: Send Slack notification
  uses: 8398a7/action-slack@v3
  with:
    status: ${{ job.status }}
    webhook_url: ${{ secrets.SLACK_WEBHOOK_URL }}
```

Then add `SLACK_WEBHOOK_URL` secret in GitHub.

---

## Troubleshooting

### Issue: "No such project: FamilyTodo.xcodeproj"
**Solution:** Update `IOS_PROJECT` in workflow to match your actual project file name

### Issue: "Scheme 'FamilyTodo' not found"
**Solution:**
1. Open Xcode
2. Click scheme dropdown
3. Select **"Manage Schemes"**
4. Check **"Shared"** for your scheme
5. Commit the `xcscheme` file

### Issue: "Code signing failed"
**Solution:**
- Verify all secrets are correctly set in GitHub
- Check that base64 strings don't have line breaks
- Ensure provisioning profile matches Bundle ID

### Issue: "Runner out of disk space"
**Solution:** Add cleanup step before build:
```yaml
- name: Clean Xcode cache
  run: |
    rm -rf ~/Library/Developer/Xcode/DerivedData/*
```

### Issue: "Xcode version not found"
**Solution:** Check available Xcode versions on GitHub runners:
- [GitHub macOS runners documentation](https://github.com/actions/runner-images/blob/main/images/macos/macos-14-Readme.md)

---

## Local Development Workflow

Since you're on Manjaro (no Xcode):

1. **Write Swift code** in VS Code or any editor
2. **Push to GitHub**
3. **GitHub Actions builds** and tests automatically
4. **View results** in Actions tab
5. **If tests pass** → code is good
6. **If tests fail** → check logs, fix, push again

**Optional:** Buy a used Mac Mini M1 (~$400) for faster local iteration.

---

## Next Steps

Once pipeline is working:
1. ✅ Add unit tests to your Swift code
2. ✅ Set up branch protection rules (require CI to pass before merge)
3. ✅ Configure TestFlight for beta testing
4. ✅ Add UI tests (optional)
5. ✅ Set up code coverage reports

---

## Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [GitHub Actions for iOS](https://docs.github.com/en/actions/deployment/deploying-xcode-applications/installing-an-apple-certificate-on-macos-runners-for-xcode-development)
- [fastlane](https://fastlane.tools/) - Alternative to GitHub Actions (more features)
- [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi)

---

**Last Updated:** 2026-01-10
**Author:** Claude Code Assistant

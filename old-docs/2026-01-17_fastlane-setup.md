# Fastlane Setup Guide

## Overview

This project uses Fastlane for automated builds and TestFlight deployment.

## Prerequisites

1. Apple Developer account (active)
2. App created in App Store Connect
3. GitHub repository secrets configured

## Setup Steps

### 1. Create App Store Connect API Key

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Navigate to **Users and Access** → **Keys** → **App Store Connect API**
3. Click **Generate API Key**
4. Name: `FamilyTodo CI`
5. Access: `App Manager` (or `Admin`)
6. Download the `.p8` file (you can only download once!)
7. Note the **Key ID** and **Issuer ID**

### 2. Configure GitHub Secrets

Go to your GitHub repo → **Settings** → **Secrets and variables** → **Actions**

Add these secrets:

| Secret Name | Value |
|-------------|-------|
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID from step 1 (e.g., `ABC123XYZ`) |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer ID from App Store Connect |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | Base64 encoded `.p8` file content* |
| `APP_IDENTIFIER` | Your bundle ID (e.g., `com.yourname.FamilyTodo`) |
| `TEAM_ID` | Your Apple Developer Team ID |

*To encode the `.p8` file:
```bash
base64 -i AuthKey_ABC123XYZ.p8 | pbcopy
```

### 3. Local Development (Optional)

Install Fastlane locally:
```bash
bundle install
```

Run lanes:
```bash
# Build only (no signing)
bundle exec fastlane build

# Run tests
bundle exec fastlane test
```

## GitHub Actions Workflow

The CI pipeline runs automatically:

| Trigger | Jobs |
|---------|------|
| Push to `main`/`develop` | Build, Test, SwiftLint |
| Push to `main` only | + Deploy to TestFlight |
| Pull Request | Build, Test, SwiftLint |

## Fastlane Lanes

| Lane | Description |
|------|-------------|
| `build` | Build for simulator (no signing) |
| `test` | Run unit tests |
| `beta` | Build and upload to TestFlight |
| `release` | Build and upload to App Store |

## Troubleshooting

### "Invalid API key"
- Verify Key ID and Issuer ID are correct
- Check that `.p8` content is properly base64 encoded
- Ensure API key has sufficient permissions

### "No signing identity found"
- For TestFlight: Fastlane handles signing automatically with API key
- For local builds: Use `bundle exec fastlane build` (skips signing)

### "Bundle identifier mismatch"
- Verify `APP_IDENTIFIER` secret matches your Xcode project
- Check App Store Connect app bundle ID

## Security Notes

- Never commit `.p8` files to git
- API keys don't expire (unlike certificates)
- Rotate keys if compromised

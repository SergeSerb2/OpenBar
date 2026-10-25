---
summary: "OpenBar CI release pipeline: signing identity, secrets, dry runs, signed tags, and Sparkle."
read_when:
  - Preparing or verifying an OpenBar release
  - Updating release infrastructure, signing, or notarization
---

# Release process (OpenBar)

[Release](https://github.com/SergeSerb2/OpenBar/blob/main/.github/workflows/release.yml) owns publication. Push an
existing SSH-signed, annotated `vX.Y.Z` (or `vX.Y.Z-beta.N`) tag to run the pipeline, or dispatch it from protected
`main` with that existing tag and `dry_run=false`. It never creates, moves, or overwrites a version tag. Nothing is
signed, notarized, or published from a local machine.

## Signing identity

The Developer ID identity has one source of truth: `.github/release.json`.

```json
"team_id": "78A5P57U23",
"signing_identity": "Developer ID Application: Serge Serbinenko (78A5P57U23)"
```

- The packaging and release scripts read these values through `Scripts/release_identity.sh`. The CI keychain setup
  (`.github/scripts/setup-signing.sh`) and verifier (`.github/scripts/verify-macos.py`) read the JSON directly.
- Swift cannot read the JSON at runtime, so `AppGroupSupport.defaultTeamID` in
  `Sources/OpenBarCore/AppGroupSupport.swift` repeats `team_id`. It is the fallback when the app cannot read the Team ID
  from its own signature. `python3 .github/scripts/release.py identity` fails when the two differ. `make check` and the
  release validate job both run it.
- To change the identity, edit both JSON values and the Swift constant, then run the identity check.
- For local builds, `APP_IDENTITY` (a full identity name or SHA-1 hash) and `APP_TEAM_ID` override the JSON values.

## One-time setup

### 1. Developer ID Application certificate

Sign in as the team's Account Holder; Developer ID certificates need that role.

1. In Xcode, open **Settings → Accounts**, select the team, choose **Manage Certificates…**, click **+**, and choose
   **Developer ID Application**. Xcode creates the private key in the login keychain and registers the certificate.
   Alternative: create a certificate signing request with **Keychain Access → Certificate Assistant → Request a
   Certificate From a Certificate Authority** (saved to disk), then upload it at
   [Certificates](https://developer.apple.com/account/resources/certificates/add) → **Developer ID Application**
   (G2 Sub-CA) and open the downloaded `.cer`.
2. In Keychain Access, open **login → My Certificates**, select
   `Developer ID Application: <Name> (<TEAM_ID>)` together with its private key, and choose **Export…**. Save it as
   `.p12` with a strong, new password. Keep the file outside the repository.
3. Confirm the identity name and Team ID that the release must use. The commands prompt for the export password:

   ```sh
   openssl pkcs12 -in DeveloperID.p12 -clcerts -nokeys | openssl x509 -noout -subject
   ```

   Add `-legacy` to the first command if OpenSSL 3 reports an unsupported algorithm. `CN` is the identity name and
   `OU` is the Team ID. If either differs from `.github/release.json`, update the JSON
   and `AppGroupSupport.defaultTeamID` before the first release.

### 2. App Store Connect API key for notarytool

1. In [App Store Connect](https://appstoreconnect.apple.com/access/integrations/api), open **Users and Access →
   Integrations → App Store Connect API → Team Keys**. Request access first if the page asks for it.
2. Generate a key named, for example, `OpenBar notarization`, with the **Developer** role.
3. Download `AuthKey_<KEY_ID>.p8`. Apple allows only one download. Note the **Key ID** of the key and the
   **Issuer ID** shown above the key list.

`Scripts/sign-and-notarize.sh` passes the key, Key ID, and Issuer ID to `xcrun notarytool submit --wait`, so it needs a
team key (individual keys have no issuer).

### 3. Repository secrets

| Secret | Value |
| --- | --- |
| `MACOS_SIGNING_P12` | Base64 of the exported Developer ID Application `.p12` |
| `MACOS_SIGNING_P12_PASSWORD` | The `.p12` export password |
| `ASC_KEY_ID` | App Store Connect API Key ID |
| `ASC_ISSUER_ID` | App Store Connect Issuer ID |
| `ASC_PRIVATE_KEY_P8` | Full contents of `AuthKey_<KEY_ID>.p8` |
| `SPARKLE_PRIVATE_KEY` | Sparkle EdDSA private key matching `sparkle_public_key` (already set) |

Set them without putting values on the command line or in shell history. `gh secret set` reads piped input, and it
prompts with hidden input when nothing is piped:

```sh
base64 -i DeveloperID.p12 | gh secret set MACOS_SIGNING_P12 --repo SergeSerb2/OpenBar
gh secret set MACOS_SIGNING_P12_PASSWORD --repo SergeSerb2/OpenBar
gh secret set ASC_KEY_ID --repo SergeSerb2/OpenBar
gh secret set ASC_ISSUER_ID --repo SergeSerb2/OpenBar
gh secret set ASC_PRIVATE_KEY_P8 --repo SergeSerb2/OpenBar < AuthKey_<KEY_ID>.p8
gh secret list --repo SergeSerb2/OpenBar
```

The release job imports the `.p12` into an ephemeral keychain, fails unless it holds the identity named by
`signing_identity`, and deletes the keychain when the job ends. No other secrets are used: there is no Homebrew tap, npm package, or
notification hook.

### 4. Protect `main`

The validate job refuses to run unless `main` is a protected branch. Add a branch protection rule for `main` that
blocks force pushes and deletions. Do not require pull requests for `main` unless the publish job can bypass the rule:
it commits `appcast.xml` to `main` with the workflow's `GITHUB_TOKEN`. Check the result with
`gh api repos/SergeSerb2/OpenBar/branches/main --jq .protected`.

## Prepare a release

Only release when explicitly requested.

1. Set `MARKETING_VERSION` in `version.env`. Set `BUILD_NUMBER` higher than every `sparkle:version` in `appcast.xml`.
2. Make the first `## ` heading in `CHANGELOG.md` the release section, with a nonempty body:

   ```md
   ## 1.0.0 — 2026-10-25
   ```

   The separator is an em dash (`—`) or `-` with one space on each side. The date is ISO `YYYY-MM-DD` and must not be
   later than the current UTC date. `## 1.0.0 — Unreleased` is accepted by dry runs only. Exactly one section may
   carry the version. `.github/scripts/release.py` (`notes()`) enforces these rules.
3. Merge to `main` and wait for green **push** CI on that exact commit.

## Rehearse without publishing

```sh
gh workflow run release.yml --ref main -f dry_run=true
gh run list --workflow release.yml --limit 1   # note the run ID
gh run watch <run-id>
```

A dispatch defaults to a dry run of the exact protected `main` head. It requires green push CI for that commit, builds
every shipping artifact, signs and notarizes the app, verifies metadata, the Team ID, entitlements, architectures,
deployment targets, and matching dSYM UUIDs, launches the app, and signs and verifies a candidate Sparkle feed entry. It
keeps the complete checksummed payload as an Actions artifact. It creates no tag, GitHub Release, or feed update.

## Publish

Create the signed annotated tag on the release commit with the SSH key listed in `.github/release-allowed-signers`.
Use the private key file, or its `.pub` when the key is loaded in `ssh-agent`:

```sh
git -c gpg.format=ssh -c user.signingkey=<path-to-release-tag-key> tag -s v1.0.0 -m "OpenBar 1.0.0"
git -c gpg.format=ssh -c gpg.ssh.allowedSignersFile=.github/release-allowed-signers verify-tag v1.0.0
git push origin v1.0.0
```

The tag push starts the release. The pipeline verifies that the tag resolves to a commit on protected `main`, checks the
tag signature and version, and refuses any existing GitHub Release, including drafts. App packaging stays in
`Scripts/sign-and-notarize.sh`; the CI job supplies the ephemeral Developer ID keychain and App Store Connect
credentials.

All platform builds finish before publication. The publisher verifies the uploaded draft bytes against the retained
payload, publishes the GitHub Release with the changelog notes and checksums, and updates `main/appcast.xml`. Installed
clients keep the feed URL and public key they shipped with.

Prereleases (`alpha.N`, `beta.N`, or `rc.N`) are marked as GitHub prereleases and use the opt-in Sparkle `beta`
channel. They do not replace the latest stable release.

## Verify and recover

The release is complete only after the release assets and the live appcast agree:

```sh
Scripts/check-release-assets.sh v1.0.0   # exact asset inventory + downloaded app's Developer ID signature
Scripts/verify_appcast.sh 1.0.0          # feed length + EdDSA signature, codesign, Gatekeeper, staple
```

Both helpers are self-contained (no signing credentials, no Keychain access). The pipeline keeps a failed draft as a
version reservation and never overwrites assets. If the feed handoff fails after publication, repair it from the
retained, verified payload; do not rerun packaging or recreate the tag. After a successful release, open the next
`Unreleased` changelog section and bump `version.env`.

When installing a ZIP manually, use `ditto -x -k` or Finder to keep the signed bundle intact and avoid AppleDouble
files.

The app and dSYM are universal arm64/x86_64. The release also contains both architectures of the macOS CLI, the Linux
glibc CLI, the Linux musl CLI, and the Linux desktop app. All macOS release jobs use Apple Silicon `xcode-27` runners and
Xcode 27 while keeping the macOS 14 deployment target. The x86_64 CLI is cross-built and executed under Rosetta. Signed
app verification launches both architectures.

## App groups

Release builds carry only the `<TEAM_ID>.com.serbinenko.openbar` app group (the widget also gets the App Sandbox). On
macOS, Team-ID-prefixed app groups need no registration or provisioning profile, and macOS 15 and later grant container
access without a prompt when the prefix matches the signing Team ID. The app migrates widget data once from the legacy
`group.com.serbinenko.openbar` container (see `AppGroupSupport.migrateLegacyDataIfNeeded`).

## iCloud sync (CloudKit)

iCloud Sync (CloudKit) is deferred for 1.0. Its entitlements are restricted, so they need a provisioning profile, and
the app reports "iCloud Sync is not available in this build of OpenBar." To re-enable it:

1. In the developer portal, enable **iCloud** (CloudKit) on the App ID `com.serbinenko.openbar` and create the container
   `iCloud.com.serbinenko.openbar`. Enable **Push Notifications** too if sync should react to remote changes.
2. Create a **Developer ID** provisioning profile for that App ID and commit it as
   `Scripts/profiles/OpenBar-DeveloperID.provisionprofile`. Gatekeeper validates it at every launch.
3. In `Scripts/package_app.sh`, for identity-signed release builds of `com.serbinenko.openbar` whose team is
   `team_id`, add `com.apple.application-identifier` (`<TEAM_ID>.com.serbinenko.openbar`),
   `com.apple.developer.team-identifier`, `com.apple.developer.icloud-services` (`CloudKit`),
   `com.apple.developer.icloud-container-identifiers`, and `com.apple.developer.icloud-container-environment`
   (`Production`), plus `com.apple.developer.aps-environment` (`production`) for push. Copy the profile to
   `Contents/embedded.provisionprofile` before signing the app. The commit "Ship 1.0 without CloudKit or a
   provisioning profile" removed the earlier version of this block:
   `git log -p --grep 'Ship 1.0 without CloudKit' -- Scripts/package_app.sh`.
4. Update `.github/scripts/verify-macos.py` and `Scripts/test_package_signing.sh` to expect those entitlements and the
   profile, and verify the profile authorizes every entitlement in the final signed app.
5. Deploy the schema before shipping. Developer ID builds reach only the Production environment, so an undeployed
   schema makes every save fail with "unknown record type":

   ```sh
   CLOUDKIT_MANAGEMENT_TOKEN=… Scripts/cloudkit/deploy_schema.sh development   # validate
   CLOUDKIT_MANAGEMENT_TOKEN=… Scripts/cloudkit/deploy_schema.sh production
   ```

   Create the token in the CloudKit Console (icloud.developer.apple.com → account → Tokens). Any new record type or
   field in `Sources/OpenBar*/Sync/` must also be added to `Scripts/cloudkit/schema.ckdb`.

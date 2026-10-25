---
summary: "Sparkle integration details for OpenBar: updater config, keys, and release flow."
read_when:
  - Touching Sparkle settings, feed URL, or keys
  - Generating or troubleshooting the Sparkle appcast
  - Validating update toggles or updater UI
---

# Sparkle integration

- Framework: Sparkle 2.9.6 via SwiftPM.
- Updater: `SPUStandardUpdaterController` owned by `AppDelegate` in `OpenbarApp.swift`.
- Feed: `SUFeedURL` is `https://raw.githubusercontent.com/SergeSerb2/OpenBar/main/appcast.xml`, set by
  `Scripts/package_app.sh` for identity-signed release builds. Ad-hoc and debug builds ship an empty feed URL with
  automatic checks off.
- Key: `SUPublicEDKey` is `1A7c8WQSsxQEasJupaax383NSHR3KewGkAGubaqn7YY=`, the same value as `sparkle_public_key` in
  `.github/release.json`. The Ed25519 private key is the `SPARKLE_PRIVATE_KEY` repository secret, with an offline
  backup kept by the maintainer. Never print it. Installed apps accept only updates signed with this key, so losing or
  replacing it strands every existing install.
- UI: auto-check toggle (About) enables auto-downloads; menu shows “Check for Updates…” when no update is staged, or “Update ready, restart now?” once an update is downloaded. These actions and About → Check for Updates open Sparkle's update UI, including its install confirmation for a staged update.
- LSUIElement: works; updater window will show when checking. App is non-sandboxed.
- Channels: stable vs beta are served from the same appcast. Prerelease items contain a `<sparkle:channel>beta</sparkle:channel>` element; About → Update Channel controls `allowedChannels`.

## Release flow

The [CI release workflow](https://github.com/SergeSerb2/OpenBar/blob/main/.github/workflows/release.yml) builds and notarizes the app, signs the archive with `sign_update` from a checksum-pinned Sparkle release, verifies that signature and that the private key matches both `SUPublicEDKey` and `release.json`, publishes the verified assets, and updates `appcast.xml` on main. See [the release process](RELEASING.md) for secrets, signed tags, and no-publish dry runs. Prerelease versions such as `X.Y.Z-beta.N` stay on the opt-in beta channel. After a release, `Scripts/verify_appcast.sh X.Y.Z` re-checks the live entry's length and EdDSA signature.

## Notes
- Release notes are the version's `CHANGELOG.md` section, embedded in the appcast item `description` as escaped
  preformatted text (`<pre>`), so the update dialog shows the Markdown source as plain text.
- If you change the feed host or key, update Info.plist (`SUFeedURL`, `SUPublicEDKey`) and bump the app.
- Auto-check toggle is persisted via Sparkle; manual “Check for Updates…” remains in About.
- Sparkle retains installation control after a background download. The install-on-quit delegate records update readiness and returns `false`; returning `true` stalls Sparkle's update session and causes manual checks to do nothing. Dismissing a downloaded or staged installation keeps the update-ready menu action available.
- OpenBar disables Sparkle in Homebrew and unsigned builds; those installs should be updated via `brew` or reinstalling from Releases. OpenBar 1.0 publishes no Homebrew cask, so every Releases install updates through Sparkle. If a cask exists later, Homebrew installs check their receipt's owning cask version daily (official or SergeSerb2/tap, when automatic checks are on) and offer a one-click `brew upgrade` from the menu and About.
- Homebrew detection follows the Caskroom artifact symlink to the installed app, including apps moved into `/Applications`; separate app copies remain eligible for Sparkle.

---
name: release-openbar
description: "OpenBar release: version bump, changelog, signed tag, CI dry run and publication, post-release checks."
---

# OpenBar Release

Publication belongs to `.github/workflows/release.yml`. Never sign, notarize, upload, or edit `appcast.xml` locally.
`docs/RELEASING.md` is the full reference; this is the checklist.

## Rules

- Release only when the maintainer asks. Never print, echo, or invent secret values.
- Never run anything that creates or modifies keychains locally (`.github/scripts/setup-signing.sh` is CI-only).
- The signing identity and Team ID live in `.github/release.json` (`team_id`, `signing_identity`).
  `AppGroupSupport.defaultTeamID` must match; `python3 .github/scripts/release.py identity` checks it.

## Prepare

1. `version.env`: set `MARKETING_VERSION` and a `BUILD_NUMBER` above every `sparkle:version` in `appcast.xml`.
2. `CHANGELOG.md`: the first `## ` heading must be `## X.Y.Z — YYYY-MM-DD` (em dash or `-`; date not in the future
   in UTC) with a nonempty body. `## X.Y.Z — Unreleased` is accepted only by dry runs.
3. Merge to `main` and wait for green **push** CI on that exact commit.

## Rehearse

```bash
gh workflow run release.yml --ref main -f dry_run=true
gh run watch "$(gh run list --workflow release.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
```

A dry run signs, notarizes, verifies, and smokes the app and keeps the payload as an Actions artifact. It publishes nothing.

## Publish

Create the SSH-signed annotated tag with the key listed in `.github/release-allowed-signers` (the private key file,
or its `.pub` when the key is loaded in `ssh-agent`), then push it:

```bash
git -c gpg.format=ssh -c user.signingkey=<path-to-release-tag-key> tag -s vX.Y.Z -m "OpenBar X.Y.Z"
git -c gpg.format=ssh -c gpg.ssh.allowedSignersFile=.github/release-allowed-signers verify-tag vX.Y.Z
git push origin vX.Y.Z
```

The tag push starts the release. Watch it to completion; a failed run keeps its draft as a version reservation, so fix
forward with a new version instead of deleting tags or drafts.

## Verify

```bash
gh release view vX.Y.Z --json tagName,isDraft,isPrerelease,url
Scripts/check-release-assets.sh vX.Y.Z
Scripts/verify_appcast.sh X.Y.Z
```

`check-release-assets.sh` checks the exact asset inventory and the downloaded app's Developer ID signature.
`verify_appcast.sh` checks the live feed entry's length and EdDSA signature, then codesign, Gatekeeper, and the staple.

## Closeout

1. Open the next `## X.Y.(Z+1) — Unreleased` changelog section and bump `version.env` (new `BUILD_NUMBER`).
2. Commit with a short imperative subject and push through the normal PR flow.

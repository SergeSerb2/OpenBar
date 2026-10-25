#!/usr/bin/env bash
# Verify a published GitHub Release: the exact asset inventory, then the downloaded app's signature.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TAG=${1:-$(git -C "$SCRIPT_DIR/.." describe --tags --abbrev=0)}
source "$SCRIPT_DIR/release_artifacts.sh"
source "$SCRIPT_DIR/release_identity.sh"
REPOSITORY=$(openbar_release_config_value repository)
BUNDLE_ID=$(openbar_release_config_value bundle_id)

# The publisher uploads every payload in .github/release.json with its .sha256 sidecar,
# plus the feed, the notes, and SHA256SUMS. Anything else (or less) is a broken release.
ASSETS=$(gh release view "$TAG" --repo "$REPOSITORY" --json assets --jq '.assets[].name')
python3 -c '
import json, sys
config = json.load(open(sys.argv[1]))
payloads = [name.format(version=sys.argv[2]) for name in config["assets"]]
expected = set(payloads + [name + ".sha256" for name in payloads] + ["appcast.xml", "RELEASE-NOTES.md", "SHA256SUMS"])
actual = set(sys.stdin.read().split())
if actual != expected:
    sys.exit(f"Release asset inventory mismatch. Missing: {sorted(expected - actual)}. Unexpected: {sorted(actual - expected)}.")
' "$OPENBAR_RELEASE_CONFIG" "${TAG#v}" <<<"$ASSETS"

# Asset presence alone cannot detect a damaged or incorrectly signed release.
ARCHIVE=$(openbar_app_zip_name "${TAG#v}" "${ARCHES:-arm64 x86_64}")
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/openbar-release-assets.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT
curl --fail --location --silent --show-error --connect-timeout 15 --max-time 300 \
  "https://github.com/$REPOSITORY/releases/download/$TAG/$ARCHIVE" \
  --output "$TEMP_DIR/$ARCHIVE"
ditto -x -k --norsrc "$TEMP_DIR/$ARCHIVE" "$TEMP_DIR"
if [[ ! -d "$TEMP_DIR/OpenBar.app" || -L "$TEMP_DIR/OpenBar.app" ]]; then
  echo "Release archive must contain a real OpenBar.app directory." >&2
  exit 1
fi
REQUIREMENT="=anchor apple generic and identifier \"$BUNDLE_ID\""
REQUIREMENT+=" and certificate leaf[subject.OU] = \"${OPENBAR_RELEASE_TEAM_ID}\""
REQUIREMENT+=' and certificate 1[field.1.2.840.113635.100.6.2.6] exists'
REQUIREMENT+=' and certificate leaf[field.1.2.840.113635.100.6.1.13] exists'
codesign --verify --deep --strict --all-architectures --verbose=2 \
  --test-requirement "$REQUIREMENT" "$TEMP_DIR/OpenBar.app"
echo "Release $TAG downloaded app signature verified (all architectures)."

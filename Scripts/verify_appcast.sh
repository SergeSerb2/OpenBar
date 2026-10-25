#!/usr/bin/env bash
# Verify a published Sparkle feed entry end to end: enclosure length, EdDSA signature against the
# shipped public key, then the downloaded app's Developer ID signature, Gatekeeper, and staple.
# Usage: Scripts/verify_appcast.sh [version] [feed-url]   (defaults: version.env and the live feed)
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/version.env"
source "$ROOT/Scripts/release_identity.sh"
VERSION=${1:-$MARKETING_VERSION}
REPOSITORY=$(openbar_release_config_value repository)
BUNDLE_ID=$(openbar_release_config_value bundle_id)
PUBLIC_KEY=$(openbar_release_config_value sparkle_public_key)
FEED_URL=${2:-https://raw.githubusercontent.com/$REPOSITORY/main/appcast.xml}
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/openbar-verify-appcast.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT

curl --fail --location --silent --show-error --connect-timeout 15 --max-time 60 "$FEED_URL" \
  --output "$TEMP_DIR/appcast.xml"
ENTRY=$(python3 - "$TEMP_DIR/appcast.xml" "$VERSION" <<'PY'
import sys
import xml.etree.ElementTree as ET
sparkle = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
items = [item for item in ET.parse(sys.argv[1]).getroot().iter('item')
         if item.findtext(sparkle + 'shortVersionString') == sys.argv[2]]
if len(items) != 1:
    sys.exit(f'Expected one appcast item for {sys.argv[2]}, found {len(items)}.')
enclosure = items[0].find('enclosure')
print(enclosure.get('url'), enclosure.get('length'), enclosure.get(sparkle + 'edSignature'))
PY
)
read -r URL LENGTH SIGNATURE <<<"$ENTRY"

curl --fail --location --silent --show-error --connect-timeout 15 --max-time 300 "$URL" \
  --output "$TEMP_DIR/archive.zip"
ACTUAL_LENGTH=$(stat -f %z "$TEMP_DIR/archive.zip")
if [[ "$ACTUAL_LENGTH" != "$LENGTH" ]]; then
  echo "Enclosure length mismatch: feed says $LENGTH, download is $ACTUAL_LENGTH bytes." >&2
  exit 1
fi

ditto -x -k --norsrc "$TEMP_DIR/archive.zip" "$TEMP_DIR/extracted"
APP="$TEMP_DIR/extracted/OpenBar.app"
APP_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")
APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
if [[ "$APP_KEY" != "$PUBLIC_KEY" || "$APP_VERSION" != "$VERSION" ]]; then
  echo "Downloaded app has SUPublicEDKey $APP_KEY and version $APP_VERSION; expected $PUBLIC_KEY and $VERSION." >&2
  exit 1
fi

# Sparkle signs the archive bytes with Ed25519; verify with the key the app ships.
OPENBAR_PUBLIC_KEY="$APP_KEY" OPENBAR_SIGNATURE="$SIGNATURE" OPENBAR_ARCHIVE="$TEMP_DIR/archive.zip" swift - <<'SWIFT'
import CryptoKit
import Foundation
let environment = ProcessInfo.processInfo.environment
let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: environment["OPENBAR_PUBLIC_KEY"]!)!)
let signature = Data(base64Encoded: environment["OPENBAR_SIGNATURE"]!) ?? Data()
let archive = try Data(contentsOf: URL(fileURLWithPath: environment["OPENBAR_ARCHIVE"]!))
guard key.isValidSignature(signature, for: archive) else {
    FileHandle.standardError.write(Data("Sparkle EdDSA signature does not match the archive.\n".utf8))
    exit(1)
}
SWIFT

REQUIREMENT="=anchor apple generic and identifier \"$BUNDLE_ID\""
REQUIREMENT+=" and certificate leaf[subject.OU] = \"${OPENBAR_RELEASE_TEAM_ID}\""
codesign --verify --deep --strict --all-architectures --verbose=2 --test-requirement "$REQUIREMENT" "$APP"
spctl --assess --type execute --verbose=2 "$APP"
xcrun stapler validate "$APP"
echo "Appcast entry $VERSION verified: length, EdDSA signature, Developer ID signature, Gatekeeper, and staple."

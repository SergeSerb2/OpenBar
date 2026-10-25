#!/usr/bin/env python3
"""Exercise the release checker without network, signing, or Keychain access."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
CONFIG = json.loads((ROOT / ".github/release.json").read_text())
TEAM_ID = CONFIG["team_id"]
PAYLOADS = [name.format(version="0.0.1") for name in CONFIG["assets"]]
ASSETS = PAYLOADS + [name + ".sha256" for name in PAYLOADS] + ["appcast.xml", "RELEASE-NOTES.md", "SHA256SUMS"]


class ReleaseAssetTests(unittest.TestCase):
    def run_check(self, failure="", arches="arm64 x86_64", assets=ASSETS):
        with tempfile.TemporaryDirectory(prefix="openbar-release-assets-") as directory:
            root = Path(directory)
            log = root / "calls"
            stub = root / "tool"
            stub.write_text("""#!/bin/bash
set -eu
tool=$(basename "$0")
printf '%s' "$tool" >> "$CHECK_LOG"
printf ' <%s>' "$@" >> "$CHECK_LOG"
printf '\\n' >> "$CHECK_LOG"
[[ "$tool" != "$FAIL_TOOL" ]] || exit 42
case "$tool" in
  gh)
    printf '%s\\n' $ASSET_NAMES
    ;;
  curl)
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == --output ]]; then touch "$2"; break; fi
      shift
    done
    ;;
  ditto)
    if [[ "$FAIL_TOOL" == symlink-app ]]; then
      ln -s "$EXISTING_APP" "${!#}/OpenBar.app"
    elif [[ "$FAIL_TOOL" != missing-app ]]; then
      mkdir -p "${!#}/OpenBar.app"
    fi
    ;;
  codesign)
    [[ "$*" == '--verify --deep --strict --all-architectures --verbose=2 '* ]] || exit 1
    [[ -d "${!#}" ]] || exit 1
    if [[ "$FAIL_TOOL" == wrong-signer && "$*" == *"certificate leaf[subject.OU] = \\"$TEAM_ID\\""* ]]; then
      exit 42
    fi
    ;;
esac
""")
            stub.chmod(0o755)
            for name in ("gh", "curl", "ditto", "codesign"):
                (root / name).symlink_to(stub)
            scratch = root / "scratch"
            scratch.mkdir()
            existing_app = root / "Existing.app"
            existing_app.mkdir()
            result = subprocess.run(
                [str(ROOT / "Scripts/check-release-assets.sh"), "v0.0.1"],
                env={
                    "PATH": f"{root}:/usr/bin:/bin",
                    "ASSET_NAMES": " ".join(assets),
                    "TMPDIR": str(scratch),
                    "CHECK_LOG": str(log),
                    "FAIL_TOOL": failure,
                    "ARCHES": arches,
                    "EXISTING_APP": str(existing_app),
                    "TEAM_ID": TEAM_ID,
                },
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(list(scratch.iterdir()), [], "temporary download was not cleaned up")
            return result, log.read_text()

    def test_valid_universal_archive_is_verified(self):
        result, calls = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("gh <release> <view> <v0.0.1> <--repo> <SergeSerb2/OpenBar>", calls)
        self.assertIn("/v0.0.1/OpenBar-macos-universal-0.0.1.zip", calls)
        self.assertIn("ditto <-x> <-k> <--norsrc>", calls)
        self.assertIn("codesign <--verify> <--deep> <--strict> <--all-architectures>", calls)
        self.assertIn('<--test-requirement> <=anchor apple generic and identifier "com.serbinenko.openbar"', calls)
        self.assertIn(f'certificate leaf[subject.OU] = "{TEAM_ID}"', calls)
        self.assertIn("certificate 1[field.1.2.840.113635.100.6.2.6] exists", calls)
        self.assertIn("certificate leaf[field.1.2.840.113635.100.6.1.13] exists", calls)

    def test_single_architecture_uses_matching_release_asset(self):
        result, calls = self.run_check(arches="arm64")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("OpenBar-macos-arm64-0.0.1.zip", calls)

    def test_invalid_signature_is_rejected(self):
        result, calls = self.run_check("codesign")
        self.assertEqual(result.returncode, 42, calls)

    def test_wrong_signer_is_rejected(self):
        result, calls = self.run_check("wrong-signer")
        self.assertEqual(result.returncode, 42, calls)

    def test_failed_asset_inventory_stops_before_download(self):
        result, calls = self.run_check("gh")
        self.assertEqual(result.returncode, 42)
        self.assertNotIn("curl", calls)

    def test_failed_download_stops_before_extraction(self):
        result, calls = self.run_check("curl")
        self.assertEqual(result.returncode, 42)
        self.assertNotIn("ditto", calls)

    def test_failed_extraction_stops_before_verification(self):
        result, calls = self.run_check("ditto")
        self.assertEqual(result.returncode, 42)
        self.assertNotIn("codesign", calls)

    def test_missing_app_is_rejected(self):
        result, _ = self.run_check("missing-app")
        self.assertNotEqual(result.returncode, 0)

    def test_app_symlink_is_rejected_before_verification(self):
        result, calls = self.run_check("symlink-app")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("codesign", calls)


if __name__ == "__main__":
    unittest.main()

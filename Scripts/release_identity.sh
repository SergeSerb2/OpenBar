#!/usr/bin/env bash
# Release signing identity. Source this file; do not run it.
#
# The single source of truth is `.github/release.json` (`team_id`, `signing_identity`).
# `AppGroupSupport.defaultTeamID` mirrors `team_id`, and `.github/scripts/release.py` fails the
# release when they differ. APP_TEAM_ID and APP_IDENTITY remain per-invocation overrides.

OPENBAR_RELEASE_CONFIG="${OPENBAR_RELEASE_CONFIG:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.github/release.json}"

openbar_release_config_value() {
  python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$OPENBAR_RELEASE_CONFIG" "$1"
}

# shellcheck disable=SC2034 # Read by the scripts that source this file.
OPENBAR_RELEASE_TEAM_ID=$(openbar_release_config_value team_id)
# shellcheck disable=SC2034
OPENBAR_RELEASE_SIGNING_IDENTITY=$(openbar_release_config_value signing_identity)

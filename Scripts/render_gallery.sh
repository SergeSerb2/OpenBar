#!/usr/bin/env bash
# Render real OpenBar views with synthetic data to PNGs (docs/design/README.md, "Render gallery").
#
#   ./Scripts/render_gallery.sh [output-dir] [sections]
#
# sections: comma-separated subset of tokens,menubar,menu,settings,widgets (default: all).
# Runs inside the scrubbed test environment: Keychain access suppressed, no network, no status items,
# no OpenBar.app launch. Opens nothing; inspect <output-dir>/index.html or the PNGs yourself.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
OUT_DIR="${1:-${ROOT_DIR}/.build/render-gallery}"
SECTIONS="${2:-}"
mkdir -p "${OUT_DIR}"
OUT_DIR="$(cd "${OUT_DIR}" && pwd)"

source "${ROOT_DIR}/Scripts/test_environment.sh"
unset MAKEFLAGS MFLAGS MAKEOVERRIDES

export OPENBAR_RENDER_GALLERY_DIR="${OUT_DIR}"
if [[ -n "${SECTIONS}" ]]; then
  export OPENBAR_RENDER_GALLERY_ONLY="${SECTIONS}"
fi

swift test --filter DesignRenderGallery
echo "Render gallery: ${OUT_DIR}/index.html"

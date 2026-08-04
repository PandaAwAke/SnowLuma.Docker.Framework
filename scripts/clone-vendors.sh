#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENDOR_DIR="${FRAMEWORK_DIR}/vendor"

SNOWLUMA_REPO="${SNOWLUMA_REPO:-https://github.com/SnowLuma/SnowLuma}"
NOVNC_REPO="${NOVNC_REPO:-https://github.com/novnc/noVNC.git}"
WEBSOCKIFY_REPO="${WEBSOCKIFY_REPO:-https://github.com/novnc/websockify.git}"
CLONE_DEPTH="${CLONE_DEPTH:-1}"
FORCE="${FORCE:-0}"

clone_repo() {
  local repo="$1"
  local dest="$2"

  if [ -e "${dest}" ]; then
    if [ "${FORCE}" = "1" ] || [ "${FORCE}" = "true" ]; then
      rm -rf "${dest}"
    else
      echo "Skip ${dest}: already exists. Set FORCE=1 to replace it."
      return 0
    fi
  fi

  git clone --depth "${CLONE_DEPTH}" "${repo}" "${dest}"
}

mkdir -p "${VENDOR_DIR}"

clone_repo "${SNOWLUMA_REPO}" "${VENDOR_DIR}/SnowLuma"
clone_repo "${NOVNC_REPO}" "${VENDOR_DIR}/noVNC"
clone_repo "${WEBSOCKIFY_REPO}" "${VENDOR_DIR}/websockify"

echo "Vendored repositories are ready under ${VENDOR_DIR}"

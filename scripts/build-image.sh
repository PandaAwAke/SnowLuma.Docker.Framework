#!/usr/bin/env bash
# Local helper: build the SnowLuma Docker image for one or more platforms.
#
# Examples:
#   ./scripts/build-image.sh                          # load host-native platform locally
#   SNOWLUMA_TAG=v1.6.35 ./scripts/build-image.sh     # auto-download release to temp dir
#   PUSH=1 PLATFORM=linux/arm64 SNOWLUMA_TAG=v1.6.35 ./scripts/build-image.sh
#
# Tooling: requires Docker buildx and (when SNOWLUMA_TAG is set) the gh CLI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMAGE="${IMAGE:-snowluma-docker-framework:latest}"
PUSH="${PUSH:-0}"
SNOWLUMA_REPO="${SNOWLUMA_REPO:-SnowLuma/SnowLuma}"
SNOWLUMA_TAG="${SNOWLUMA_TAG:-}"
VENDORED_SNOWLUMA_DIR="${FRAMEWORK_DIR}/vendor/SnowLuma"
BUILD_CONTEXT="${FRAMEWORK_DIR}"
TEMP_CONTEXT=""
DOWNLOAD_DIR=""
RELEASE_ARTIFACT=""

cleanup() {
  if [ -n "${TEMP_CONTEXT}" ] && [ -d "${TEMP_CONTEXT}" ]; then
    rm -rf "${TEMP_CONTEXT}"
  fi
  if [ -n "${DOWNLOAD_DIR}" ] && [ -d "${DOWNLOAD_DIR}" ]; then
    rm -rf "${DOWNLOAD_DIR}"
  fi
}

trap cleanup EXIT

default_platform_for_host() {
  case "$(uname -m)" in
    arm64|aarch64) echo "linux/arm64" ;;
    x86_64|amd64) echo "linux/amd64" ;;
    *) echo "linux/amd64" ;;
  esac
}

if [ "${PUSH}" = "1" ] || [ "${PUSH}" = "true" ]; then
  PLATFORM="${PLATFORM:-$(default_platform_for_host)}"
  OUTPUT="${OUTPUT:---push}"
else
  PLATFORM="${PLATFORM:-$(default_platform_for_host)}"
  OUTPUT="${OUTPUT:---load}"
fi

# This local helper only supports single-platform builds — multi-arch
# manifest creation is what CI is for. Users wanting multi-arch should
# push a SnowLuma tag and let .github/workflows/docker-image.yml handle it.
case "${PLATFORM}" in
  *,*) echo "PLATFORM must be a single value (linux/amd64 or linux/arm64); use CI for multi-arch." >&2; exit 1 ;;
esac

case "${PLATFORM}" in
  linux/amd64) asset_arch="linux-x64" ;;
  linux/arm64) asset_arch="linux-arm64" ;;
  *) echo "Unsupported PLATFORM: ${PLATFORM}" >&2; exit 1 ;;
esac

if [ -n "${SNOWLUMA_TAG}" ]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "gh CLI not found. Install from https://cli.github.com/ then re-run." >&2
    exit 1
  fi
  asset="SnowLuma-${SNOWLUMA_TAG}-${asset_arch}-lite.tar.gz"
  DOWNLOAD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/snowluma-release.XXXXXX")"
  RELEASE_ARTIFACT="${DOWNLOAD_DIR}/${asset}"
  echo "Fetching ${asset} from ${SNOWLUMA_REPO}@${SNOWLUMA_TAG}"
  gh release download "${SNOWLUMA_TAG}" \
    --repo "${SNOWLUMA_REPO}" \
    --pattern "${asset}" \
    --output "${RELEASE_ARTIFACT}" \
    --clobber
fi

if [ ! -d "${FRAMEWORK_DIR}/vendor/noVNC" ] || [ ! -d "${FRAMEWORK_DIR}/vendor/websockify" ]; then
  echo "Missing vendored noVNC/websockify under ${FRAMEWORK_DIR}/vendor." >&2
  exit 1
fi

if [ -n "${RELEASE_ARTIFACT}" ] && [ -f "${RELEASE_ARTIFACT}" ]; then
  TEMP_CONTEXT="$(mktemp -d "${TMPDIR:-/tmp}/snowluma-docker-context.XXXXXX")"
  mkdir -p "${TEMP_CONTEXT}/vendor" "${TEMP_CONTEXT}/scripts"
  cp "${FRAMEWORK_DIR}/Dockerfile" "${FRAMEWORK_DIR}/start.sh" "${FRAMEWORK_DIR}/supervisord.conf" "${TEMP_CONTEXT}/"
  cp "${FRAMEWORK_DIR}/scripts/prepare-vendor-snowluma.sh" "${TEMP_CONTEXT}/scripts/"
  cp -a "${FRAMEWORK_DIR}/vendor/noVNC" "${TEMP_CONTEXT}/vendor/noVNC"
  cp -a "${FRAMEWORK_DIR}/vendor/websockify" "${TEMP_CONTEXT}/vendor/websockify"
  if [ -d "${FRAMEWORK_DIR}/vendor/qq" ]; then
    cp -a "${FRAMEWORK_DIR}/vendor/qq" "${TEMP_CONTEXT}/vendor/qq"
  fi
  mkdir -p "${TEMP_CONTEXT}/vendor/SnowLuma"
  tar -xzf "${RELEASE_ARTIFACT}" -C "${TEMP_CONTEXT}/vendor/SnowLuma"
  BUILD_CONTEXT="${TEMP_CONTEXT}"
else
  if [ -f "${VENDORED_SNOWLUMA_DIR}/dist/index.mjs" ] && [ -f "${VENDORED_SNOWLUMA_DIR}/packages/runtime/package.json" ]; then
    echo "Using vendored SnowLuma sources from ${VENDORED_SNOWLUMA_DIR}"
  else
    echo "Missing vendored SnowLuma runtime inputs under ${VENDORED_SNOWLUMA_DIR}." >&2
    echo "Expected at least ${VENDORED_SNOWLUMA_DIR}/dist/index.mjs and ${VENDORED_SNOWLUMA_DIR}/packages/runtime/package.json." >&2
    echo "Run scripts/clone-vendors.sh first, or set SNOWLUMA_TAG=vX.Y.Z to build from a temporary downloaded release." >&2
    exit 1
  fi
fi

docker buildx build \
  --platform "${PLATFORM}" \
  --tag "${IMAGE}" \
  --file "${BUILD_CONTEXT}/Dockerfile" \
  ${OUTPUT} \
  "${BUILD_CONTEXT}"

echo "Built ${IMAGE} for ${PLATFORM}"

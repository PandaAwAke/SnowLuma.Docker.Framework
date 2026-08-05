#!/usr/bin/env bash
# Local helper: build the SnowLuma Docker image for one or more platforms.
#
# Examples:
#   ./scripts/build-image.sh                          # load host-native platform locally
#   PLATFORM=linux/arm64 ./scripts/build-image.sh
#   PUSH=1 PLATFORM=linux/arm64 IMAGE=example/snowluma:latest ./scripts/build-image.sh
#
# Tooling: requires Docker buildx.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMAGE="${IMAGE:-snowluma-docker-framework:latest}"
PUSH="${PUSH:-0}"
VENDORED_SNOWLUMA_DIR="${FRAMEWORK_DIR}/vendor/SnowLuma"

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

if [ ! -d "${FRAMEWORK_DIR}/vendor/noVNC" ] || [ ! -d "${FRAMEWORK_DIR}/vendor/websockify" ]; then
  echo "Missing vendored noVNC/websockify under ${FRAMEWORK_DIR}/vendor." >&2
  exit 1
fi

if [ ! -f "${VENDORED_SNOWLUMA_DIR}/dist/index.mjs" ] || [ ! -f "${VENDORED_SNOWLUMA_DIR}/packages/runtime/package.json" ]; then
  echo "Missing vendored SnowLuma runtime inputs under ${VENDORED_SNOWLUMA_DIR}." >&2
  echo "Expected at least ${VENDORED_SNOWLUMA_DIR}/dist/index.mjs and ${VENDORED_SNOWLUMA_DIR}/packages/runtime/package.json." >&2
  echo "Run ./scripts/clone-vendors.sh first, or verify your vendor/SnowLuma checkout contains released runtime files." >&2
  exit 1
fi

echo "Using vendored SnowLuma sources from ${VENDORED_SNOWLUMA_DIR}"

docker buildx build \
  --platform "${PLATFORM}" \
  --tag "${IMAGE}" \
  --file "${FRAMEWORK_DIR}/Dockerfile" \
  ${OUTPUT} \
  "${FRAMEWORK_DIR}"

echo "Built ${IMAGE} for ${PLATFORM} (${asset_arch})"

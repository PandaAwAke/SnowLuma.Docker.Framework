#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <vendor-snowluma-dir> <output-dir> <dpkg-arch>" >&2
  exit 2
fi

src_root="$1"
out_dir="$2"
dpkg_arch="$3"

case "${dpkg_arch}" in
  amd64) native_arch="x64" ;;
  arm64) native_arch="arm64" ;;
  *)
    echo "Unsupported Debian architecture: ${dpkg_arch}" >&2
    exit 1
    ;;
esac

if [ -f "${src_root}/dist/index.mjs" ] && [ -d "${src_root}/packages/runtime" ]; then
  dist_dir="${src_root}/dist"
  runtime_dir="${src_root}/packages/runtime"
  native_dir="${runtime_dir}/native"

  for required in \
    "${dist_dir}/index.mjs" \
    "${dist_dir}/client/index.html" \
    "${runtime_dir}/package.json" \
    "${runtime_dir}/launcher.sh" \
    "${native_dir}/snowluma-linux-${native_arch}.node" \
    "${native_dir}/snowluma-linux-${native_arch}.so" \
    "${native_dir}/websocket-linux-${native_arch}.node" \
    "${native_dir}/ffmpeg/ffmpegAddon.linux.${native_arch}.node"
  do
    if [ ! -f "${required}" ]; then
      echo "Missing required vendored SnowLuma file: ${required}" >&2
      exit 1
    fi
  done
else
  echo "Unsupported SnowLuma layout under ${src_root}" >&2
  exit 1
fi

rm -rf "${out_dir}"
mkdir -p "${out_dir}/native/ffmpeg"

cp -a "${dist_dir}/." "${out_dir}/"
rm -f "${out_dir}"/native/snowluma-linux-*.node
rm -f "${out_dir}"/native/snowluma-linux-*.so
rm -f "${out_dir}"/native/websocket-linux-*.node
rm -f "${out_dir}"/native/ffmpeg/ffmpegAddon.linux.*.node
cp "${runtime_dir}/package.json" "${out_dir}/package.json"
cp "${runtime_dir}/launcher.sh" "${out_dir}/launcher.sh"
cp "${native_dir}/snowluma-linux-${native_arch}.node" "${out_dir}/native/"
cp "${native_dir}/snowluma-linux-${native_arch}.so" "${out_dir}/native/"
cp "${native_dir}/websocket-linux-${native_arch}.node" "${out_dir}/native/"
cp "${native_dir}/ffmpeg/ffmpegAddon.linux.${native_arch}.node" "${out_dir}/native/ffmpeg/"

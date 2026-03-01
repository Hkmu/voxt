#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_MANIFEST="${1:-${ROOT_DIR}/build/release/artifacts/appcast.json}"
TARGET_MANIFEST="${2:-${ROOT_DIR}/updates/appcast.json}"

if [[ ! -f "${SOURCE_MANIFEST}" ]]; then
  echo "Manifest not found: ${SOURCE_MANIFEST}"
  exit 1
fi

mkdir -p "$(dirname "${TARGET_MANIFEST}")"
cp "${SOURCE_MANIFEST}" "${TARGET_MANIFEST}"
echo "Updated manifest: ${TARGET_MANIFEST}"


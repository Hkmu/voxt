#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/Voxt.xcodeproj"
SCHEME="${SCHEME:-Voxt}"
CONFIGURATION="${CONFIGURATION:-Release}"
VERSION="${1:-}"

if [[ -z "${VERSION}" ]]; then
  echo "Usage: $0 <version>"
  exit 1
fi

BUILD_DIR="${ROOT_DIR}/build/release"
ARCHIVE_PATH="${BUILD_DIR}/Voxt.xcarchive"
ARTIFACTS_DIR="${BUILD_DIR}/artifacts"
APP_PATH="${ARCHIVE_PATH}/Products/Applications/Voxt.app"
ZIP_PATH="${ARTIFACTS_DIR}/Voxt-${VERSION}.app.zip"
PKG_PATH="${ARTIFACTS_DIR}/Voxt-${VERSION}.pkg"
MANIFEST_PATH="${ARTIFACTS_DIR}/appcast.json"

rm -rf "${BUILD_DIR}"
mkdir -p "${ARTIFACTS_DIR}"

echo "==> Archiving ${SCHEME} (${CONFIGURATION})"
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -archivePath "${ARCHIVE_PATH}" \
  archive

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Archive succeeded but app not found: ${APP_PATH}"
  exit 1
fi

echo "==> Creating app zip"
/usr/bin/ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"

echo "==> Creating installer pkg"
productbuild --component "${APP_PATH}" /Applications "${PKG_PATH}"

SHA256="$(shasum -a 256 "${PKG_PATH}" | awk '{print $1}')"
DOWNLOAD_URL="${DOWNLOAD_URL:-https://github.com/hehehai/voxt/releases/download/v${VERSION}/Voxt-${VERSION}.pkg}"
RELEASE_NOTES="${RELEASE_NOTES:-See CHANGELOG.md for details.}"
PUBLISHED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

cat > "${MANIFEST_PATH}" <<JSON
{
  "version": "${VERSION}",
  "minimumSupportedVersion": "${MINIMUM_SUPPORTED_VERSION:-${VERSION}}",
  "downloadURL": "${DOWNLOAD_URL}",
  "releaseNotes": "${RELEASE_NOTES}",
  "publishedAt": "${PUBLISHED_AT}",
  "sha256": "${SHA256}"
}
JSON

echo "==> Release artifacts"
echo "ZIP: ${ZIP_PATH}"
echo "PKG: ${PKG_PATH}"
echo "Manifest: ${MANIFEST_PATH}"


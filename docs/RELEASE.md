# Release Guide

## What this provides
- `CHANGELOG.md` for release notes.
- `scripts/release/build_release.sh` to build:
  - `Voxt-<version>.app.zip`
  - `Voxt-<version>.pkg`
  - `appcast.json` update manifest
- `.github/workflows/release.yml` for tag-driven release automation.
- `updates/appcast.json` as the hosted update manifest path used by the app.

## Local release
1. Update `CHANGELOG.md`.
2. Run:
   ```bash
   chmod +x scripts/release/build_release.sh scripts/release/publish_manifest.sh
   scripts/release/build_release.sh 1.2.3
   scripts/release/publish_manifest.sh
   ```
3. Artifacts are generated in `build/release/artifacts/`.

## GitHub release flow
1. Create and push a tag:
   ```bash
   git tag v1.2.3
   git push origin v1.2.3
   ```
2. GitHub Actions will:
   - build the app archive
   - generate `.zip`, `.pkg`, and `appcast.json`
   - create a GitHub Release and upload artifacts

## In-app update checks
- Auto-check at launch is enabled by default.
- Users can manually trigger update check from menu:
  - `Check for Updates…`
- Update manifest URL default:
  - `https://raw.githubusercontent.com/hehehai/voxt/main/updates/appcast.json`


#!/usr/bin/env bash
# build-dmg.sh — builds AirportScanner.app and packages it as a .dmg
# Run this script from the artifacts/AirportScanner/ directory on your Mac.
# Requirements: Xcode command-line tools (xcode-select --install)

set -euo pipefail

APP_NAME="AirportScanner"
PROJECT="${APP_NAME}.xcodeproj"
SCHEME="${APP_NAME}"
BUILD_DIR="$(pwd)/build"
DERIVED_DATA="${BUILD_DIR}/DerivedData"
DMG_STAGING="${BUILD_DIR}/dmg-staging"
DMG_OUT="${BUILD_DIR}/${APP_NAME}.dmg"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Building ${APP_NAME}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 1. Build ────────────────────────────────────────────────────────────────
xcodebuild build \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  | xcpretty 2>/dev/null || true   # xcpretty is optional — falls back gracefully

# ── 2. Locate the built .app ─────────────────────────────────────────────────
APP_PATH=$(find "${DERIVED_DATA}" -name "${APP_NAME}.app" -maxdepth 8 | head -1)
if [ -z "${APP_PATH}" ]; then
  echo "❌  Could not find ${APP_NAME}.app in DerivedData. Build may have failed."
  exit 1
fi
echo "✅  Built: ${APP_PATH}"

# ── 3. Stage for DMG ─────────────────────────────────────────────────────────
rm -rf "${DMG_STAGING}"
mkdir -p "${DMG_STAGING}"
cp -R "${APP_PATH}" "${DMG_STAGING}/"
# Add an Applications shortcut so users get the drag-to-install experience
ln -s /Applications "${DMG_STAGING}/Applications"

# ── 4. Pack into DMG ─────────────────────────────────────────────────────────
rm -f "${DMG_OUT}"
hdiutil create \
  -volname "Airport Scanner" \
  -srcfolder "${DMG_STAGING}" \
  -ov \
  -format UDZO \
  "${DMG_OUT}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " ✅  Done!  →  ${DMG_OUT}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "To share: upload build/AirportScanner.dmg anywhere (see README for GitHub options)."
echo ""
echo "Note: because this build is ad-hoc signed (not notarized), recipients must"
echo "right-click → Open the first time to bypass Gatekeeper."

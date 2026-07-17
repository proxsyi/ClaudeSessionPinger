#!/bin/bash
set -euo pipefail

APP_NAME="Session Pinger"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

BUILD_DIR=".build/release"
APP_DIR="dist/${APP_NAME}.app"

swift build -c release

rm -rf dist
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/ClaudeSessionPinger" "${APP_DIR}/Contents/MacOS/ClaudeSessionPinger"
cp "Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"

# Strip Finder metadata / extended attributes before signing. codesign
# refuses to sign a bundle containing them ("resource fork, Finder
# information, or similar detritus not allowed"). Newer macOS versions add
# provenance/quarantine xattrs to copied files, so always clean first.
xattr -cr "${APP_DIR}"
find "${APP_DIR}" -name "._*" -delete

# Sign with a stable code-signing identity if one is available, so the app's
# code identity stays the same across updates and the macOS keychain does not
# re-prompt for access every time you update. Falls back to ad-hoc signing
# (which changes every build, causing keychain re-prompts) if no identity is
# found. Override the identity name with CODESIGN_IDENTITY if needed.
SIGN_IDENTITY="${CODESIGN_IDENTITY:-Session Pinger Signing}"
if security find-identity -v -p codesigning | grep -q "${SIGN_IDENTITY}"; then
    echo "Signing with identity: ${SIGN_IDENTITY}"
    codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_DIR}"
else
    echo "WARNING: code-signing identity \"${SIGN_IDENTITY}\" not found -- using ad-hoc signing."
    echo "         The keychain will re-prompt on every update until this identity exists."
    codesign --force --deep --sign - "${APP_DIR}"
fi

# Some Finder/Launch Services paths can attach FinderInfo while the bundle is
# being assembled. Remove any post-signing metadata, then fail the build if
# the finished bundle does not satisfy strict signature validation.
xattr -cr "${APP_DIR}"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

echo "Built: ${APP_DIR}"
echo "Move it into /Applications, then double-click to launch."

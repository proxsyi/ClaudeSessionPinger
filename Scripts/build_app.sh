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

codesign --force --deep --sign - "${APP_DIR}"

echo "Built: ${APP_DIR}"
echo "Move it into /Applications, then double-click to launch."

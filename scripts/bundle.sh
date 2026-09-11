#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build -c release
app="dist/Picrow.app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/Picrow "$app/Contents/MacOS/Picrow"
mkdir -p "$app/Contents/Resources"
cp PrivacyInfo.xcprivacy "$app/Contents/Resources/"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp Config/Picrow-Info.plist "$app/Contents/Info.plist"
codesign --force --sign - --entitlements scripts/PicLook.entitlements "$app"
rm -rf dist/PicLook.app

#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build -c release
app="dist/Picwa.app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/Picwa "$app/Contents/MacOS/Picwa"
mkdir -p "$app/Contents/Resources"
cp PrivacyInfo.xcprivacy "$app/Contents/Resources/"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp Config/Picwa-Info.plist "$app/Contents/Info.plist"
codesign --force --sign - --entitlements scripts/Picwa.entitlements "$app"

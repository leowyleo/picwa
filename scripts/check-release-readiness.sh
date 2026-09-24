#!/bin/zsh
set -u

cd "${0:A:h}/.."
app="${1:-dist/Picwa.app}"
failures=0

pass() { print "PASS  $1" }
warn() { print "WARN  $1" }
fail() { print "FAIL  $1"; failures=$((failures + 1)) }

if [[ ! -d "$app" ]]; then
    fail "app bundle not found: $app"
    exit 1
fi

if plutil -lint "$app/Contents/Info.plist" >/dev/null 2>&1; then pass "Info.plist is valid"; else fail "Info.plist is invalid"; fi
if [[ -x "$app/Contents/MacOS/Picwa" ]]; then pass "executable exists"; else fail "executable missing"; fi
if [[ -f "$app/Contents/Resources/AppIcon.icns" ]]; then pass "AppIcon.icns is bundled"; else fail "AppIcon.icns missing"; fi
if [[ -f "$app/Contents/Resources/PrivacyInfo.xcprivacy" ]] && plutil -lint "$app/Contents/Resources/PrivacyInfo.xcprivacy" >/dev/null 2>&1; then
    pass "PrivacyInfo.xcprivacy is bundled and valid"
else
    fail "PrivacyInfo.xcprivacy missing or invalid"
fi

bundle_id=$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist" 2>/dev/null || true)
version=$(plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist" 2>/dev/null || true)
build=$(plutil -extract CFBundleVersion raw -o - "$app/Contents/Info.plist" 2>/dev/null || true)
[[ "$bundle_id" == "cc.leowy.picwa" ]] && pass "Bundle ID: $bundle_id" || fail "unexpected Bundle ID: $bundle_id"
[[ -n "$version" && -n "$build" ]] && pass "Version/build: $version ($build)" || fail "version/build is incomplete"

archs=$(lipo -info "$app/Contents/MacOS/Picwa" 2>/dev/null || true)
if [[ "$archs" == *arm64* && "$archs" == *x86_64* ]]; then
    pass "universal binary: arm64 + x86_64"
elif [[ "$archs" == *arm64* ]]; then
    warn "Apple Silicon-only binary"
else
    fail "unsupported or unreadable binary architectures"
fi

signature=$(codesign -dvvv "$app" 2>&1 || true)
if [[ "$signature" == *"Signature=adhoc"* ]]; then
    warn "ad hoc signature; Apple Distribution signing is still required"
elif [[ "$signature" == *"TeamIdentifier="* ]]; then
    pass "bundle has a non-ad-hoc signature"
else
    warn "signature could not be classified"
fi

[[ -f docs/PRIVACY_POLICY.md ]] && pass "privacy policy draft exists" || fail "privacy policy draft missing"
[[ -f docs/APP_STORE_METADATA.md ]] && pass "App Store metadata draft exists" || fail "metadata draft missing"
[[ -f docs/STORE_ASSETS.md ]] && pass "store asset checklist exists" || fail "store asset checklist missing"
if rg -q "发布前请在此处补充" docs/privacy-policy.html 2>/dev/null; then
    warn "privacy policy HTML still needs operator/contact details"
else
    pass "privacy policy HTML has no pending contact placeholder"
fi

print ""
print "Account-dependent steps remain: Bundle ID, certificates, App Record, upload, and review submission."
exit "$failures"

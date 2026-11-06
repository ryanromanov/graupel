#!/bin/sh
#
# Builds a release of Graupel: signs it with the Developer ID certificate, has Apple notarize it,
# and zips the result. Nothing is uploaded anywhere except to Apple's notary service.
#
#   Scripts/release.sh               sign, notarize, staple, and zip
#   Scripts/release.sh --sign-only   stop after signing and checking, without contacting Apple
#
# Notarizing reads its credentials from the keychain. Store them once with:
#
#   xcrun notarytool store-credentials graupel-notary --apple-id <email> --team-id KL362RST7H
#
# NOTARY_PROFILE names a different keychain profile.

set -eu

cd "$(dirname "$0")/.."

team=KL362RST7H
profile=${NOTARY_PROFILE:-graupel-notary}
output=build-release
archive="$output/Graupel.xcarchive"
export_dir="$output/export"
app="$export_dir/Graupel.app"

sign_only=false
case "${1:-}" in
    --sign-only) sign_only=true ;;
    "") ;;
    *) echo "usage: $0 [--sign-only]" >&2; exit 2 ;;
esac

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application:.*($team)"; then
    echo "error: no Developer ID Application certificate for team $team in the keychain" >&2
    exit 1
fi
if ! $sign_only && ! xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
    echo "error: can't use the notary credentials \"$profile\"; see the top of this script" >&2
    exit 1
fi

rm -rf "$archive" "$export_dir"
mkdir -p "$output"

echo "==> Archiving (log: $output/archive.log)"
xcodebuild archive \
    -project CotEditor.xcodeproj -scheme CotEditor -configuration Release \
    -archivePath "$archive" -derivedDataPath "$output/derived" \
    -skipPackagePluginValidation -skipMacroValidation \
    CODE_SIGN_IDENTITY="Developer ID Application" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$team" \
    ENTITLEMENTS_VARIANT=DeveloperID \
    > "$output/archive.log" 2>&1 || { tail -30 "$output/archive.log" >&2; exit 1; }

echo "==> Signing (log: $output/export.log)"
xcodebuild -exportArchive \
    -archivePath "$archive" -exportPath "$export_dir" \
    -exportOptionsPlist Configurations/ExportOptions-DeveloperID.plist \
    > "$output/export.log" 2>&1 || { tail -30 "$output/export.log" >&2; exit 1; }

echo "==> Checking the signature"
codesign --verify --deep --strict "$app"
details=$(codesign -dvv "$app" 2>&1)
entitlements=$(codesign -d --entitlements - "$app" 2>/dev/null)
for expected in "TeamIdentifier=$team" "Authority=Developer ID Application" "Timestamp=" "flags=.*runtime"; do
    if ! echo "$details" | grep -q "$expected"; then
        echo "error: the signature lacks $expected" >&2
        exit 1
    fi
done
for unwanted in get-task-allow icloud disable-library-validation; do
    if echo "$entitlements" | grep -q "$unwanted"; then
        echo "error: the signature has the entitlement $unwanted" >&2
        exit 1
    fi
done

if $sign_only; then
    echo "Signed: $app (not notarized)"
    exit 0
fi

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")
zip="$output/Graupel-$version.zip"

echo "==> Notarizing"
upload="$output/notarize.zip"
ditto -c -k --keepParent "$app" "$upload"
xcrun notarytool submit "$upload" --keychain-profile "$profile" --wait --output-format plist > "$output/notarize.plist"
rm -f "$upload"
status=$(/usr/libexec/PlistBuddy -c "Print :status" "$output/notarize.plist")
if [ "$status" != "Accepted" ]; then
    id=$(/usr/libexec/PlistBuddy -c "Print :id" "$output/notarize.plist")
    echo "error: notarization ended with \"$status\"; the reasons:" >&2
    xcrun notarytool log "$id" --keychain-profile "$profile" >&2
    exit 1
fi

echo "==> Stapling"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose "$app"

ditto -c -k --keepParent "$app" "$zip"
echo "Done: $zip"

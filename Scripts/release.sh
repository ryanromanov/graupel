#!/bin/sh
#
# Builds a release of Graupel: signs it with the Developer ID certificate, has Apple notarize it,
# zips the result, and makes the signed update feed (appcast.xml) for Sparkle. Nothing is uploaded
# anywhere except to Apple's notary service. A copy of the archive, with its debug symbols, is kept in
# ~/Library/Developer/Xcode/Archives so crash reports from the release can be read.
#
#   Scripts/release.sh               sign, notarize, staple, and zip
#   Scripts/release.sh --sign-only   stop after signing and checking, without contacting Apple
#
# Notarizing reads its credentials from the keychain. Store them once with:
#
#   xcrun notarytool store-credentials graupel-notary --apple-id <email> --team-id KL362RST7H
#
# NOTARY_PROFILE names a different keychain profile.
#
# The update feed is signed with the EdDSA key stored in the keychain under the account "graupel",
# made once with Sparkle's generate_keys. Its public half is GRAUPEL_UPDATE_PUBLIC_KEY in
# Configurations/CotEditor.xcconfig. If the private key is lost, no installed copy can update again.

set -eu

cd "$(dirname "$0")/.."

team=KL362RST7H
key_account=graupel
repo=https://github.com/ryanromanov/graupel
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
    -project Graupel.xcodeproj -scheme Graupel -configuration Release \
    -archivePath "$archive" -derivedDataPath "$output/derived" \
    -skipPackagePluginValidation -skipMacroValidation \
    CODE_SIGN_IDENTITY="Developer ID Application" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$team" \
    ENTITLEMENTS_VARIANT=DeveloperID \
    > "$output/archive.log" 2>&1 || { tail -30 "$output/archive.log" >&2; exit 1; }

sparkle_bin="$output/derived/SourcePackages/artifacts/sparkle/Sparkle/bin"
public_key=$(sed -n 's/^GRAUPEL_UPDATE_PUBLIC_KEY = *//p' Configurations/CotEditor.xcconfig)
keychain_key=$("$sparkle_bin/generate_keys" --account "$key_account" -p 2>/dev/null || true)
if [ -z "$public_key" ] || [ "$public_key" != "$keychain_key" ]; then
    echo "error: GRAUPEL_UPDATE_PUBLIC_KEY doesn't match the update key in the keychain (account \"$key_account\")" >&2
    exit 1
fi

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
# The Homebrew tap's update workflow checks the zip against this file, so attach both to the release.
(cd "$output" && shasum -a 256 "$(basename "$zip")" > "$(basename "$zip").sha256")

echo "==> Making the update feed"
# The feed lists only this version: Sparkle reads it from the latest release, and older entries would never be offered.
feed_dir="$output/appcast"
rm -rf "$feed_dir" "$output/appcast.xml"
mkdir -p "$feed_dir"
cp "$zip" "$feed_dir/"
python3 Scripts/releaseNotes.py "$version" < CHANGELOG.md > "$feed_dir/Graupel-$version.html"
"$sparkle_bin/generate_appcast" "$feed_dir" \
    --account "$key_account" \
    --download-url-prefix "$repo/releases/download/v$version/" \
    --embed-release-notes \
    --full-release-notes-url "$repo/releases/tag/v$version" \
    --link "$repo" \
    --maximum-deltas 0 \
    -o "$output/appcast.xml"
rm -rf "$feed_dir"

echo "==> Keeping the archive"
# build-release is temporary, but the archive's debug symbols (dSYMs) are needed to read crash reports from
# this version and can't be rebuilt to match. Xcode's Organizer finds archives in this folder.
build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$app/Contents/Info.plist")
kept="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/Graupel $version ($build) $(date +%H.%M.%S).xcarchive"
mkdir -p "$(dirname "$kept")"
ditto "$archive" "$kept"
echo "Kept: $kept"

echo "Done: attach $zip, $zip.sha256, and $output/appcast.xml to the release"

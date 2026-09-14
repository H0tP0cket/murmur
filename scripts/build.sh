#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration=${1:-release}
[[ "$configuration" == release || "$configuration" == debug ]] || { echo 'Choose debug or release.'; exit 1; }
swift build -c "$configuration" --arch arm64
scripts/vendor-codex.sh
application_bundle=.build/bundle/MurMur.app
[[ ! -e "$application_bundle" ]] || /usr/bin/trash "$application_bundle"
mkdir -p "$application_bundle/Contents/MacOS" "$application_bundle/Contents/Resources/Companion"
cp ".build/$configuration/MurMur" "$application_bundle/Contents/MacOS/MurMur"
cp ".build/$configuration/MurMurMeetBridge" "$application_bundle/Contents/MacOS/MurMurMeetBridge"
cp .build/vendor/codex "$application_bundle/Contents/MacOS/codex"
cp -R Companion/Meet Companion/extension-id.txt "$application_bundle/Contents/Resources/Companion/"
cp -R Resources/Licenses "$application_bundle/Contents/Resources/"
cp Resources/Info.plist "$application_bundle/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/Brand/MurMurMark.png "$application_bundle/Contents/Resources/"
if [[ -n "${MURMUR_SIGNING_IDENTITY:-}" ]]; then
  for binary in codex MurMurMeetBridge MurMur; do
    codesign --force --options runtime --timestamp --sign "$MURMUR_SIGNING_IDENTITY" "$application_bundle/Contents/MacOS/$binary"
  done
  codesign --force --options runtime --timestamp --entitlements Resources/Entitlements.plist --sign "$MURMUR_SIGNING_IDENTITY" "$application_bundle"
else
  codesign --force --sign - "$application_bundle/Contents/MacOS/MurMurMeetBridge"
  codesign --force --sign - --identifier dev.oblivion.app --requirements '=designated => identifier "dev.oblivion.app"' "$application_bundle"
fi
codesign --verify --deep --strict "$application_bundle"
echo "Built $PWD/$application_bundle"

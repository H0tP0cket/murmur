#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
release_mode=${1:---preview}
[[ "$release_mode" == --preview || "$release_mode" == --signed ]] || { echo 'Use --preview or --signed.'; exit 1; }
if [[ "$release_mode" == --signed ]]; then
  [[ -n "${MURMUR_SIGNING_IDENTITY:-}" && -n "${MURMUR_NOTARY_PROFILE:-}" ]] || { echo 'Set MURMUR_SIGNING_IDENTITY and MURMUR_NOTARY_PROFILE for a notarized release.'; exit 1; }
else
  unset MURMUR_SIGNING_IDENTITY
fi
scripts/test.sh
scripts/build.sh
release_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
release_name="MurMur-${release_version}-arm64"
release_bundle="$PWD/.build/bundle/MurMur.app"
mkdir -p dist .build/dmg
if [[ "$release_mode" == --signed ]]; then
  ditto -c -k --sequesterRsrc --keepParent "$release_bundle" .build/notarize.zip
  xcrun notarytool submit .build/notarize.zip --keychain-profile "$MURMUR_NOTARY_PROFILE" --wait
  xcrun stapler staple "$release_bundle"
  spctl --assess --type execute --verbose "$release_bundle"
fi
# Explicit allowlist. No library, auth, test screenshots or developer settings.
[[ ! -e .build/dmg/MurMur.app ]] || /usr/bin/trash .build/dmg/MurMur.app
ditto "$release_bundle" .build/dmg/MurMur.app
ln -sfn /Applications .build/dmg/Applications
cp docs/INSTALL.txt '.build/dmg/Read me first.txt'
hdiutil create -quiet -ov -volname MurMur -srcfolder .build/dmg -format UDZO "dist/${release_name}.dmg"
if [[ "$release_mode" == --signed ]]; then
  codesign --timestamp --sign "$MURMUR_SIGNING_IDENTITY" "dist/${release_name}.dmg"
  xcrun notarytool submit "dist/${release_name}.dmg" --keychain-profile "$MURMUR_NOTARY_PROFILE" --wait
  xcrun stapler staple "dist/${release_name}.dmg"
fi
ditto -c -k --sequesterRsrc --keepParent "$release_bundle" "dist/${release_name}.zip"
(cd dist && shasum -a 256 "${release_name}.dmg" "${release_name}.zip" > SHA256SUMS.txt)
echo "Created ${release_name} ${release_mode#--} in dist"

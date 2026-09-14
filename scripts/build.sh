#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# Keep temporary bundles inside the hidden build tree, out of app searches.
configuration=${1:-release}
swift build -c "$configuration"
mkdir -p .build/bundle/Oblivion.app/Contents/MacOS .build/bundle/Oblivion.app/Contents/Resources
cp ".build/$configuration/Oblivion" .build/bundle/Oblivion.app/Contents/MacOS/Oblivion
cp -R Companion .build/bundle/Oblivion.app/Contents/Resources/
cp Resources/Info.plist .build/bundle/Oblivion.app/Contents/Info.plist
cp Resources/AppIcon.icns .build/bundle/Oblivion.app/Contents/Resources/AppIcon.icns
codesign --force --sign - --identifier dev.oblivion.app --requirements '=designated => identifier "dev.oblivion.app"' .build/bundle/Oblivion.app
echo "Built: $PWD/.build/bundle/Oblivion.app"

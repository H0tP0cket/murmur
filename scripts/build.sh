#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration=${1:-release}
swift build -c "$configuration"
mkdir -p build/Oblivion.app/Contents/MacOS build/Oblivion.app/Contents/Resources
cp ".build/$configuration/Oblivion" build/Oblivion.app/Contents/MacOS/Oblivion
cp -R Companion build/Oblivion.app/Contents/Resources/
cp Resources/Info.plist build/Oblivion.app/Contents/Info.plist
codesign --force --sign - --identifier dev.oblivion.app --requirements '=designated => identifier "dev.oblivion.app"' build/Oblivion.app
echo "Built: $PWD/build/Oblivion.app"

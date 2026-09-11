#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
icon_work=$(mktemp -d)
trap 'rm -rf "$icon_work"' EXIT
cp scripts/make-icon.swift "$icon_work/main.swift"
swiftc Sources/Oblivion/LogoGeometry.swift "$icon_work/main.swift" -o "$icon_work/render-icon"
"$icon_work/render-icon" .runtime/Oblivion.iconset Resources/Brand
iconutil -c icns .runtime/Oblivion.iconset -o Resources/AppIcon.icns

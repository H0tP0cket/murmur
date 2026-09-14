#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if pgrep -x Oblivion >/dev/null || pgrep -x MurMur >/dev/null; then
  echo 'Quit MurMur (or the earlier Oblivion app) before updating.'
  exit 1
fi
scripts/build.sh
application_destination="$HOME/Applications/MurMur.app"
mkdir -p "${application_destination:h}"
ditto .build/bundle/MurMur.app "$application_destination"
codesign --verify --deep --strict "$application_destination"
touch "$application_destination"
registration=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$registration" -f "$application_destination"
# Preserve identity and data. Retire the old bundle only after verification.
for obsolete in "$HOME/Applications/Oblivion.app" "$PWD/.build/bundle/Oblivion.app" "$PWD/.build/bundle/MurMur.app"; do
  if [[ -d "$obsolete" ]] && [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$obsolete/Contents/Info.plist" 2>/dev/null)" == dev.oblivion.app ]]; then
    "$registration" -u "$obsolete" >/dev/null 2>&1 || true
    /usr/bin/trash "$obsolete"
  fi
done
echo "Installed $application_destination"

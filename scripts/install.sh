#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if pgrep -x Oblivion >/dev/null || pgrep -x MurMur >/dev/null || pgrep -x murmur >/dev/null; then
  echo 'Quit murmur (or the earlier Oblivion app) before updating.'
  exit 1
fi
scripts/build.sh
application_destination="$HOME/Applications/murmur.app"
mkdir -p "${application_destination:h}"
# Install a fresh verified bundle. Merging would retain the old executable and
# directory casing on case-insensitive volumes.
install_stage=$(mktemp -d "$HOME/Applications/.murmur-install.XXXXXX")
ditto .build/bundle/murmur.app "$install_stage/murmur.app"
codesign --verify --deep --strict "$install_stage/murmur.app"
if [[ -e "$application_destination" ]]; then
  [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$application_destination/Contents/Info.plist" 2>/dev/null)" == dev.oblivion.app ]] || { echo 'An unrelated application already occupies the destination.'; exit 1; }
  mv "$application_destination" "$install_stage/previous.app"
fi
if ! mv "$install_stage/murmur.app" "$application_destination"; then
  [[ ! -d "$install_stage/previous.app" ]] || mv "$install_stage/previous.app" "$application_destination"
  exit 1
fi
[[ ! -d "$install_stage/previous.app" ]] || /usr/bin/trash "$install_stage/previous.app"
rmdir "$install_stage"
touch "$application_destination"
registration=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$registration" -f "$application_destination"
# Preserve identity and data. Retire the old bundle only after verification.
for obsolete in "$HOME/Applications/Oblivion.app" "$HOME/Applications/MurMur.app" "$PWD/.build/bundle/Oblivion.app" "$PWD/.build/bundle/MurMur.app" "$PWD/.build/bundle/murmur.app"; do
  [[ ! "$obsolete" -ef "$application_destination" ]] || continue
  if [[ -d "$obsolete" ]] && [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$obsolete/Contents/Info.plist" 2>/dev/null)" == dev.oblivion.app ]]; then
    "$registration" -u "$obsolete" >/dev/null 2>&1 || true
    /usr/bin/trash "$obsolete"
  fi
done
echo "Installed $application_destination"

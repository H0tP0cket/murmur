#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if pgrep -x Oblivion >/dev/null; then
  echo "Quit Oblivion before updating the installed application."
  exit 1
fi
scripts/build.sh
application_destination="$HOME/Applications/Oblivion.app"
mkdir -p "${application_destination:h}"
ditto .build/bundle/Oblivion.app "$application_destination"
codesign --verify --deep --strict "$application_destination"
# ditto preserves directory timestamps. Notify Finder and Launch Services that
# this bundle changed, including its icon, after the completed copy is verified.
touch "$application_destination"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$application_destination"
# The installed app is the only launchable copy left after installation.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$PWD/.build/bundle/Oblivion.app" >/dev/null 2>&1 || true
/usr/bin/trash .build/bundle/Oblivion.app
echo "Installed: $application_destination"

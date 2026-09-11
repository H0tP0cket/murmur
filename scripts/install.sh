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
ditto build/Oblivion.app "$application_destination"
codesign --verify --deep --strict "$application_destination"
echo "Installed: $application_destination"

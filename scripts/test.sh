#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
developer_dir=$(xcode-select -p)
if [[ "$developer_dir" == */CommandLineTools ]]; then
  swift test -Xswiftc "-F$developer_dir/Library/Developer/Frameworks" \
    -Xlinker "-F$developer_dir/Library/Developer/Frameworks" \
    -Xlinker -rpath -Xlinker "$developer_dir/Library/Developer/Frameworks" \
    -Xlinker -rpath -Xlinker "$developer_dir/Library/Developer/usr/lib" "$@"
else
  swift test "$@"
fi

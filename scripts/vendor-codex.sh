#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# Official upstream artifact. Never package a developer's CLI, credentials or settings.
runtime_version=0.154.0
runtime_sha256=344310a0a591c1b192e04feff304321a69907c9498baaac331ca7e16ebcef9d7
runtime_archive=.build/vendor/codex-arm64.tar.gz
mkdir -p .build/vendor
if [[ ! -f "$runtime_archive" ]] || [[ "$(shasum -a 256 "$runtime_archive" | cut -d ' ' -f 1)" != "$runtime_sha256" ]]; then
  curl -fL --retry 3 --silent --show-error "https://github.com/openai/codex/releases/download/rust-v${runtime_version}/codex-aarch64-apple-darwin.tar.gz" -o "${runtime_archive}.download"
  [[ "$(shasum -a 256 "${runtime_archive}.download" | cut -d ' ' -f 1)" == "$runtime_sha256" ]] || { echo 'Codex checksum verification failed.'; exit 1; }
  mv "${runtime_archive}.download" "$runtime_archive"
fi
tar -xzf "$runtime_archive" -C .build/vendor codex-aarch64-apple-darwin
mv .build/vendor/codex-aarch64-apple-darwin .build/vendor/codex
chmod 755 .build/vendor/codex
echo "Bundled official Codex ${runtime_version}"

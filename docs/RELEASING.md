# Building a release

The supported binary is Apple Silicon, macOS 26 or later. Swift modules keep the original internal `Oblivion` name; the product and main executable are `murmur`. Existing artwork and native helper filenames are retained.

## Downloadable preview

Run `scripts/release.sh --preview` on an Apple Silicon Mac with the macOS 26 SDK. This runs the tests, builds the app and native Meet helper, downloads the pinned official Codex 0.154.0 artifact, verifies its SHA-256, and creates a DMG, ZIP and checksums in `dist/`.

The packaging allowlist includes only executables, the supplied branding, companion extension, permission descriptions and third-party notices. Local libraries, login tokens, screenshots, test data, `.codex` settings and developer environment files are excluded. Never package a copy of an installed app's user data.

Preview builds use ad-hoc app signing. They are not Apple-notarized. Label GitHub releases **pre-release** and retain the Open Anyway instructions until signing is configured.

## Apple-notarized release

Install a Developer ID Application certificate in the build Mac's keychain. Store notarization credentials with `xcrun notarytool store-credentials` under a named keychain profile. Set `MURMUR_SIGNING_IDENTITY` to that certificate name and `MURMUR_NOTARY_PROFILE` to the profile name, then run `scripts/release.sh --signed`.

The script signs nested executables with the hardened runtime, signs the app, submits it for notarization, staples the ticket and verifies Gatekeeper acceptance. It also signs, notarizes and staples the DMG. Credentials are never written into the repository or release assets. A preview run is not evidence that the signed path has passed.

## Before publishing

Use the packaged app with a separate clean library, complete browser sign-in, prepare a chat, choose a model and effort, send an image, copy a multi-paragraph/table response, edit the header, organize folders, reopen saved data, exercise notes and cue cards, and start/return/end the HUD. Verify calendar permission and event preparation using calendars explicitly connected by the tester. Exercise the bundled native helper with the Meet extension. Never substitute synthetic transcript tests for a claim of a tested remote two-person meeting.

Publish the exact verified commit with the DMG, ZIP and SHA256SUMS.txt. Document any untested integrations or platform limitations in the release notes. Keep the old `dev.oblivion.app` bundle identifier and data folder so upgrades remain compatible.

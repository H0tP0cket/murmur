# Oblivion

A personal macOS meeting copilot. Every call starts as a preparation chat, becomes a live conversation workspace, and leaves behind a searchable transcript, editable notes, and useful follow-up context.

Before the call, think deeply. During the call, make me glance, not read. After the call, remember everything.

## Status

The native application is implemented and undergoing final integration testing. Real microphone and Chrome audio capture → on-device transcript → Codex coaching, stable answers while speaking, and exact prepared-story retrieval have passed through the running app. The installed Meet companion and two-person roster attribution have also passed. Preparation, PDF/link research, notes, transcript editing/import/export, direct questions, and post-call summaries have been exercised with computer use. Actual Zoom meeting audio, larger-meeting speaker signals, headphones/device changes, and remote receiver checks remain open; see [the verification log](docs/TESTING.md).

## Run locally

Requires macOS 26, Apple Silicon, Swift tools, and `codex login` using ChatGPT.

```sh
scripts/build.sh
# Launch build/Oblivion.app in Finder.
scripts/install.sh # Quit Oblivion first; installs to ~/Applications.
scripts/test.sh
OBLIVION_CODEX_TEST=1 scripts/test.sh
```

The last command exercises your real Codex account. Calls and attachments are stored under `~/Library/Application Support/Oblivion`; raw audio is not retained. Use `scripts/build.sh debug` for a quicker development build.

## Using the app

Create a call and work through your preparation in the chat. Use the attachment button for PDFs/text and paste links for research. Save complete stories with **Save answer**. Your shared personal background lives in Settings.

The app uses a dark-only charcoal palette with a glass sidebar. The compact composer grows with your text; Return sends and Shift-Return inserts a line break. Call notes display formatted text; choose **Edit** to change them.

**Start call** captures microphone and meeting audio. The upper HUD gives one recommendation and a small coaching strip. **Chat** returns to the main window while listening continues; **End call** stops capture and saves the transcript. The sidebar document button opens transcript search/corrections/export. Notes and prepared answers open from the chat header.

- `⌘⇧Space`: hide/show the HUD during a call.
- `⌘⇧X`: return to the chat.
- `⌘⌥K`: ask the copilot globally; `⌘K` works inside the HUD.
- `⌘⇧P`: pop out from the app.

Share a specific tab/application window or use a separate display for the HUD. Full-display sharing may expose it. A local Chrome tab-capture receiver test passed; this is not a universal capture-exclusion guarantee.

For Meet names, Settings → **Set up Meet companion…** installs the native host and opens the extension folder. Manually load that folder in Chrome's extensions page, open the extension in your meeting, and select **Use this meeting**. The call still works without names; uncertain speakers remain “Meeting.”

The monochrome Oblivion mark is available as [light](Resources/Brand/OblivionMark.svg) and [dark](Resources/Brand/OblivionMark-Black.svg) SVGs. Its two flowing shapes form an O around a central void. `scripts/make-icon.sh` regenerates these exports and the macOS icon from the same geometry used by the native interface.

## Build priorities

1. Build the SwiftUI/AppKit application with real live listening, streaming transcription, and Codex App Server advice, alongside persistent chats, preparation, attachments, research, notes, and call records. Start with native macOS audio capture and Apple's on-device SpeechAnalyzer/SpeechTranscriber. Validate the running app using computer use. Live functionality is required for the first usable release.
2. Complete the floating Call Mode HUD and Google Meet/Zoom speaker attribution. GPT-Live-1 remains an optional later evaluation; deferring that model does not defer live audio or coaching.

Codex App Server is required for preparation, research, answer generation, coaching, and analysis. GPT-Live-1 is the only authorized separately billed AI API integration. Do not silently substitute a Responses API backend or a third-party transcription service.

## Project documents

- [Product specification](docs/PRODUCT.md)
- [Technical decisions and verified sources](docs/TECHNICAL_DECISIONS.md)
- [Implementation milestones and acceptance criteria](docs/IMPLEMENTATION.md)

Development will use small, coherent Git commits and bounded subagents when useful. Keep credentials, personal call content, and runtime logs out of source control.

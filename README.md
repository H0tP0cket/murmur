# Oblivion

A personal macOS meeting copilot. Every call starts as a preparation chat, becomes a live conversation workspace, and leaves behind a searchable transcript, editable notes, and useful follow-up context.

Before the call, think deeply. During the call, make me glance, not read. After the call, remember everything.

## Status

Pre-build decisions recorded on September 11, 2026. The repository is initialized; application implementation and the build goal loop have not started.

## Build priorities

1. Build the SwiftUI/AppKit application with real live listening, streaming transcription, and Codex App Server advice, alongside persistent chats, preparation, attachments, research, notes, and call records. Start with native macOS audio capture and Apple's on-device SpeechAnalyzer/SpeechTranscriber. Validate the running app using computer use. Live functionality is required for the first usable release.
2. Complete the floating Call Mode HUD and Google Meet/Zoom speaker attribution. GPT-Live-1 remains an optional later evaluation; deferring that model does not defer live audio or coaching.

Codex App Server is required for preparation, research, answer generation, coaching, and analysis. GPT-Live-1 is the only authorized separately billed AI API integration. Do not silently substitute a Responses API backend or a third-party transcription service.

## Project documents

- [Product specification](docs/PRODUCT.md)
- [Technical decisions and verified sources](docs/TECHNICAL_DECISIONS.md)
- [Implementation milestones and acceptance criteria](docs/IMPLEMENTATION.md)

Development will use small, coherent Git commits and bounded subagents when useful. Keep credentials, personal call content, and runtime logs out of source control.

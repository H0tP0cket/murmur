# Oblivion

A personal macOS meeting copilot. Every call starts as a preparation chat, becomes a live conversation workspace, and leaves behind a searchable transcript, editable notes, and useful follow-up context.

Before the call, think deeply. During the call, make me glance, not read. After the call, remember everything.

## Status

Pre-build decisions recorded on September 11, 2026. The repository is initialized; application implementation and the build goal loop have not started.

## Build priorities

1. Build the native main application and real Codex App Server integration: persistent chats, free-form intake, preparation, attachments, research, prepared answers, notes, and transcript interaction.
2. Add Google Meet/Zoom audio capture, GPT-Live-1, speaker attribution, and the floating Call Mode HUD.

Codex App Server is required for preparation, research, answer generation, coaching, and analysis. GPT-Live-1 is the only authorized separately billed AI API integration. Do not silently substitute a Responses API backend or a third-party transcription service.

## Project documents

- [Product specification](docs/PRODUCT.md)
- [Technical decisions and verified sources](docs/TECHNICAL_DECISIONS.md)
- [Implementation milestones and acceptance criteria](docs/IMPLEMENTATION.md)

Development will use small, coherent Git commits and bounded subagents when useful. Keep credentials, personal call content, and runtime logs out of source control.

<p align="center"><img src="Resources/Brand/AppIcon.png" width="88" alt="Oblivion icon"></p>

# Oblivion

A native macOS copilot for better conversations. Prepare in a chat, get live coaching during a call, and keep the transcript and notes afterward.

- Free-form preparation with images, PDFs, text, links, and research.
- Automatic person + company/role chat names, with manual renaming.
- A floating HUD with one next recommendation, full prepared answers, and quick private questions.
- On-device transcription of microphone and meeting audio.
- Searchable, editable transcripts and notes attached to each conversation.
- SwiftUI + AppKit, a monochrome dark interface, and a glass sidebar.

All AI reasoning runs through **Codex App Server** using your ChatGPT account. Transcription uses Apple's on-device SpeechAnalyzer.

## Run

Requires **macOS 26**, Apple Silicon, Swift tools, and the Codex CLI signed in with ChatGPT.

```sh
scripts/install.sh
open ~/Applications/Oblivion.app
```

Quit Oblivion before reinstalling. Run `scripts/test.sh` for tests.

Use **+** to attach files, or paste screenshots and copied image files into the composer. Click a thumbnail to preview it. Select across paragraphs in a response to copy text; its Copy action copies the full Markdown response. **Save for call** opens the prepared-answer editor so you can approve wording for the live HUD.

Chats, attachments, and transcripts stay in `~/Library/Application Support/Oblivion`. Relevant text and attached images are sent to Codex for advice; raw audio is not saved. Share a specific tab or application window: full-display sharing can expose the HUD.

Personal project, still being tested. See the [verification log](docs/TESTING.md) for tested flows and remaining meeting-integration checks.

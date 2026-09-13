<p align="center"><img src="Resources/Brand/AppIcon.png" width="88" alt="Oblivion icon"></p>

# Oblivion

A native macOS copilot for better conversations. Prepare in a chat, get live coaching during a call, and keep the transcript and notes afterward.

- Free-form preparation with images, PDFs, text, links, and research.
- Automatic person + company/role chat names, with manual renaming.
- A floating HUD with one next recommendation, exact Must-say wording, and quick private questions.
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

Use **+** to attach files, or paste screenshots and copied image files into the composer. Click a thumbnail to preview it. Select across paragraphs in a response to copy text; **Copy** copies the full Markdown response.

**Save for call** opens **Must-say** with two fields: **When to use it** and **What to say**. Keep perfected introductions, questions, pitches, and answers here. The live coach matches situations and paraphrases, then the app retrieves your exact saved wording. Existing prepared answers remain available. This is priority context, not a separate model cache or a guarantee of perfect matching.

**Notes** opens a full-height personal notepad. In the pop-out HUD, **Notes** opens a separate movable notepad alongside the live guidance. Both edit the same notes for the active call. Close the notepad to keep only the HUD, or return to chat to continue in the notes sidebar. The hide shortcut hides both floating windows together. Your notes are saved with the call and included when you ask the chat to reference them. The **AI notes** tab keeps generated findings, edits, and updates separate.

Chats, attachments, and transcripts stay in `~/Library/Application Support/Oblivion`. Relevant text and attached images are sent to Codex for advice; raw audio is not saved. Share a specific tab or application window: full-display sharing can expose the HUD.

Personal project, still being tested. See the [verification log](docs/TESTING.md) for tested flows and remaining meeting-integration checks.

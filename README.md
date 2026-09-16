<p align="center"><img src="Resources/Brand/AppIcon.png" width="88" alt="murmur icon"></p>

# murmur

A native macOS copilot for better conversations. Prepare in a chat, get live coaching during a call, and keep the transcript and notes afterward.

- Free-form preparation with images, PDFs, text, links, and research.
- Per-chat model and reasoning effort controls, with buffered replies and selectable tables.
- Home with upcoming meetings, person/company folders, and numbered calls with inline titles.
- A floating HUD with one next recommendation, exact saved wording, and quick private questions.
- On-device transcription of microphone and meeting audio.
- Searchable, editable transcripts and notes attached to each conversation.
- SwiftUI + AppKit, a monochrome dark interface, and a glass sidebar.

All AI reasoning runs through **Codex App Server** using your ChatGPT account. Transcription uses Apple's on-device SpeechAnalyzer.

## Download

**[Download murmur for macOS](https://github.com/H0tP0cket/oblivion/releases)**

Requires **macOS 26 or later and Apple Silicon**, plus a ChatGPT account with Codex access. The app bundles Codex, so you do not need an API key, Terminal, Homebrew or developer tools. Your plan determines available models and usage limits.

1. Download the DMG, open it, and drag murmur to Applications.
2. Open murmur and choose **Sign in with ChatGPT**. Finish in your browser.
3. Prepare a chat. Start call requests audio permissions when you need them.

This first release is a **preview, not Apple-notarized**. If macOS blocks it, use **System Settings → Privacy & Security → Open Anyway** after attempting to open it. Follow [Apple’s instructions](https://support.apple.com/en-us/102445) and install only releases you trust. Full setup instructions are [here](docs/INSTALL.txt).

## Home and folders

Use **Create folder** below Search calls to group meetings with a person or company. New chats are named **Call 1**, **Call 2**, and so on within each folder. Edit any title directly in the chat header. Move existing chats using the row menu. Removing a folder keeps its calls.

**Sync Google Calendar** reads calendars connected through **macOS Internet Accounts**, including Google. Connect Google there, enable Calendars, then choose calendars in murmur. Home shows the next two weeks. **Prepare** attaches that event’s context to a new chat; **Open chat** returns to it. Calendar access is optional, stays on the Mac, and never edits events.

## Build from source

With Swift tools and the macOS 26 SDK installed, run `scripts/install.sh`, then open `~/Applications/murmur.app`. Quit murmur before updating. The installer replaces the old Oblivion bundle while preserving existing data and sign-in. Run `scripts/test.sh` for tests or `scripts/release.sh --preview` to produce download assets. See [release instructions](docs/RELEASING.md) for signing and notarization.

## Using murmur

Use **+** to attach files, or paste screenshots and copied image files into the composer. Sent images leave the composer and stay on their original message; the × removes an unsent attachment. Click a thumbnail to preview it. Select across paragraphs in a response to copy text; **Copy** copies the full Markdown response.

Edit the chat name directly in the header. Return or clicking away saves it, and Escape cancels. Both sidebars slide open and closed, and the header icons show a short label after half a second of hovering.

Choose the model and reasoning effort inside the composer. The controls highlight on hover and flip their arrows while a menu is open. Choices are saved per chat and apply to its next reply. Replies appear in coherent chunks; Copy keeps the original Markdown, including tables.

In **Settings → Personal context**, expand **Build your context with ChatGPT** and copy the prompt to generate a factual first-person summary. Paste the result into your personal context to make it available across calls.

**Save for call** opens **Cue cards** with two fields: **When to use it** and **What to say**. Keep perfected introductions, questions, pitches, and answers here. The live coach matches situations and paraphrases, then the app retrieves your exact saved wording. Existing saved wording remains available. This is priority context, not a separate model cache or a guarantee of perfect matching.

**Notes** opens a full-height personal notepad. From the HUD, it restores the main chat with notes while keeping live guidance visible. **Pop out** returns to the overlay alone. Notes are saved with the call and available when you ask the chat to reference them. Drag the panel edge to widen it.

Expand **AI notes** below your notepad and drag the divider to resize both sections. AI notes summarize the conversation or follow your written notes when present. Opening the section refreshes changed source material; **Update** refreshes it on demand. Manual edits remain protected until you accept a proposed replacement.

Chats, attachments, and transcripts stay in `~/Library/Application Support/Oblivion`. Relevant text and attached images are sent to Codex for advice; raw audio is not saved. Share a specific tab or application window: full-display sharing can expose the HUD.

murmur has no developer-run backend or analytics. See [privacy details](docs/PRIVACY.md) and the [verification log](docs/TESTING.md) for tested flows and limitations. This project is independent of OpenAI. The bundled Codex runtime retains its [upstream license and notices](Resources/Licenses).

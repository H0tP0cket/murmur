# Release verification

MurMur 0.2.0 targets Apple Silicon and macOS 26 or later. It is a preview, not an Apple-notarized production release.

## Automated coverage

Run `scripts/test.sh`. The regular suite exercises persisted chats and notes, folder numbering and removal without deleting calls, calendar-event preparation and deduplication, per-chat model/effort selection, image attachment lifecycle, buffered streaming and cancellation, Markdown tables and multi-paragraph selection, transcript revisions, cue-card retrieval, stable recommendations, and the chat/HUD notes lifecycle.

A local JSON-RPC fixture covers ChatGPT sign-in, cancellation, late callbacks, failure, success, account refresh and sign-out. Fresh libraries receive a separate Codex home; upgrade tests preserve existing thread IDs. AI-note tests preserve the user's notepad and edited summaries while applying new source context.

The native Meet helper is tested as a subprocess for framing, allowed origins, bounded metadata, stale sessions, malformed input and owner-only files. Python is used by the development test runner, not by the shipped app or helper.

Three provider/speech integration tests are opt-in. Their environment switches are declared on the tests; a passing default suite does not mean those opt-in tests ran.

## On-screen release checks

Native macOS Accessibility actions and window screenshots were used because the computer-use connector was unavailable. Testing used a separate local library and fictional call content.

- First launch displayed the MurMur Home page and sign-in action without needing a separately installed CLI. Clicking Sign in with ChatGPT completed authentication using the tester's existing browser session and the bundled Codex runtime.
- A real prep response referenced the fictional personal notes and rendered a two-column table correctly. AI notes generated from those notes without changing the notepad.
- Pasting and removing an unsent image worked. Sending cleared the composer attachment, retained the original message image, and produced a correct visual description through the bundled runtime.
- Folder creation, numbered calls, persistence across restart and direct header editing were exercised. The test caught and fixed a first-click title-focus issue.
- The new brand was checked in the app and generated Dock/Finder icon artwork. The notepad divider matches the neutral sidebar divider.
- Microphone and system-audio capture both transcribed a synthetic spoken fixture. An approved introduction appeared verbatim in the HUD. The HUD's Notes action restored the main app and retained the overlay. Start and end actions were exercised.
- Calendar setup and the denied-access flow were checked. Calendar access was denied on this test Mac, so live Google calendar synchronization was not verified. Event-to-chat behavior is covered with synthetic event records.
- The download package is scanned for credentials, local conversations, databases, test artifacts and obsolete runtime dependencies. The app and bundled executables pass code-signature integrity verification.

## Limits

This is not a test on a second person's Mac. Password entry and a different user's ChatGPT subscription were not tested. Available models and account access depend on OpenAI. Live multi-participant Meet/Zoom attribution and sustained long meetings still need broader testing; unknown speakers remain generic. Full-display sharing can expose the HUD.

There is no Developer ID certificate on the build Mac, so the notarized release path and ordinary Gatekeeper acceptance are unverified. Preview installation uses Apple's documented Open Anyway path. Calendar integration requires Google to be connected in macOS Internet Accounts and selected in MurMur.

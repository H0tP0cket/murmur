# Privacy

murmur has no developer-operated service, analytics endpoint, remote account database, advertising SDK or automatic crash-upload service. The developer receives no meeting content or account credentials through the app.

## On this Mac

Chats, attachments, notes, cue cards, transcripts and folder organization are stored in `~/Library/Application Support/Oblivion`. The original directory and bundle identifier are retained for upgrade compatibility. Personal context and UI preferences use macOS UserDefaults. Local files are not encrypted by murmur; your Mac's account permissions and disk encryption protect them.

Audio is processed with Apple's on-device SpeechAnalyzer. murmur retains the text transcript, not raw audio recordings or screen video. Initial use can download Apple's speech assets. Microphone and Screen & System Audio Recording access are requested when starting capture. Unknown speakers remain generic rather than receiving a guessed name.

Calendar access is optional and read-only in murmur's implementation. macOS asks for full Calendar access because that is the permission EventKit provides for reading events. You choose calendars already connected on your Mac, including Google calendars. Upcoming event details stay in memory until you choose an event to prepare. Only that event's details are attached to its chat. murmur does not create or edit calendar events.

The optional Meet extension passes participant names and speaking activity through Chrome native messaging to a local helper. It has no developer backend. Zoom attribution reads explicit speaking labels through Accessibility where available.

## OpenAI

murmur bundles the official Codex CLI and uses its documented App Server protocol. Sign-in opens OpenAI's authentication page. murmur does not ask for your password or copy authentication tokens to a developer service. New installations use a private Codex home in the local library. Upgraded libraries retain their existing shared Codex home to preserve saved threads and sign-in. Settings identifies that shared state before sign-out.

Relevant prep chat, selected event context, personal background, attachments, notes, transcripts and cue cards go to OpenAI when requesting AI assistance. Codex may use web search when preparing a call. OpenAI's account terms, data controls, model availability and usage limits apply. “Local library” does not mean that AI inference or its provider-side processing happens locally.

## Sharing and removal

Exports happen only when you request them. The HUD is not guaranteed invisible in full-screen capture. Use application/window or browser-tab sharing for presentation privacy.

To disconnect a calendar, open Home > Calendars > Disconnect. To remove credentials, sign out in Settings before deleting local data. For upgraded shared Codex homes, this also signs out the shared Codex account. Deleting the app bundle alone does not delete your library. You can reveal the library from Settings and delete it yourself when no longer needed.

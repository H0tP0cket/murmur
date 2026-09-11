# Verification log

## Initial native foundation — September 11, 2026

- Release and debug builds compile on this Mac (macOS 26.6, Apple M5, Swift 6.3.3).
- Computer use launched the application and visually inspected the initial dark appearance at 1120 × 760.
- Three persistence tests pass: corrections preserve original text, notes and approved stories round-trip, independent call/thread identities and archive state survive restart, and corrupt data is reported without being overwritten.
- A real App Server integration test passed with ChatGPT authentication and `gpt-5.6-luna`: model discovery, ephemeral thread, streamed response and structured coaching JSON. This caught and fixed the sandbox enum spelling before interactive chat testing.
- Native audio capture, speaker adapters, and complete UI flows remain under test. These initial checks do not establish end-to-end readiness.

## Live engine hardening

- Computer use created a fictional call and sent a preparation message. A real streamed Codex response appeared in the native chat.
- On-device speech integration now passes a 20.16-second generated speech fixture: five final passages preserve negation, the $50,000 threshold, reviewers, and 40-minute review duration. This uses the actual SpeechAnalyzer and the app's resampler, not a transcript stub. It caught both sample overlap and sub-sample gaps that were fragmenting words; contiguous buffers now share a sample clock. It does not yet verify system capture or microphone permissions.
- Added tests for changing provisional transcript boundaries, simultaneous channels, duplicate finals, draft separation, and conservative speaker attribution.
- Native messaging tests verify that the Meet bridge accepts only its fixed extension origin, rejects expired calls, writes owner-only metadata, and never copies transcript payloads.
- Current Meet roster and participant tile selectors were inspected in an isolated live Meet session with computer use. Extension loading, multi-person speaking signals, and Zoom labels still need real UI verification.
- Microphone capture testing is waiting for the user to approve a system-owned permission prompt that computer use cannot operate.

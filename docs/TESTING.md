# Verification log

## Initial native foundation — September 11, 2026

- Release and debug builds compile on this Mac (macOS 26.6, Apple M5, Swift 6.3.3).
- Computer use launched the application and visually inspected the initial dark appearance at 1120 × 760.
- Three persistence tests pass: corrections preserve original text, notes and approved stories round-trip, independent call/thread identities and archive state survive restart, and corrupt data is reported without being overwritten.
- A real App Server integration test passed with ChatGPT authentication and `gpt-5.6-luna`: model discovery, ephemeral thread, streamed response and structured coaching JSON. This caught and fixed the sandbox enum spelling before interactive chat testing.
- Native audio capture, speaker adapters, and complete UI flows remain under test. These initial checks do not establish end-to-end readiness.

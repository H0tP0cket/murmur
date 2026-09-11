# Implementation milestones

The build goal is active. This document lists acceptance criteria; completed checks are recorded in `TESTING.md`.

## 1. Native foundation and a real live pipeline

- Create a launchable SwiftUI/AppKit application with past calls, New call, chat, composer, and restrained native styling.
- Connect to the installed Codex App Server through its documented protocol and existing ChatGPT authentication.
- Support streaming, cancellation, actionable connection failures, and conversation resume.
- Persist call metadata and map it to the correct backend thread.
- Integrate separate microphone and meeting/system audio capture with the required native permissions.
- Use Apple SpeechAnalyzer/SpeechTranscriber for local live transcription; runtime availability and installed en-US assets have been verified, but capture and accuracy have not.
- Feed new transcript context into a bounded App Server coaching loop and display real streamed advice.

Acceptance: create two calls, chat in each using real App Server responses, restart, resume the correct histories, and verify that cancellation and reconnection do not corrupt or duplicate messages. Exercise actual microphone and system capture with known speech and verify transcript-driven advice. No mock answers in the ordinary app flow. The first usable release requires live functionality; deferring GPT-Live-1 does not make it a preparation-only app.

## 2. Useful preparation and durable call records

- Implement conversational intake and editable prepared introductions/stories/questions.
- Support text, PDF extraction, links, and source-backed research through App Server tools.
- Add notes and full transcript views, corrections, search, selection-to-chat, and export.
- Make prior-call context retrievable when relevant to a user request.
- Use imported or synthetic transcripts explicitly as development fixtures for reproducible checks, alongside real audio integration tests.

Acceptance: prepare a call using a PDF and a research link, refine and retain an approved answer, reopen all data after restart, correct/search a transcript, and ask grounded questions about selected and earlier-call material. AI notes updates must preserve manual edits.

## 3. Call engine and floating HUD

- Separate call lifecycle from main-window/HUD visibility.
- Add the upper floating panel, one recommendation, small coaching strip, direct-question input, hide, return, and End call actions.
- Keep an answer stable during local speech and allow explicit replacement.
- Make prepared material available during backend interruption.

Acceptance: replay a scripted conversation and verify introduction, short follow-up, full prepared answer retrieval, mid-answer stability, direct questions, and ending. Hiding or returning to chat must not end the call; End call must stop all live work.

## 4. Meeting integration and live reliability

- Harden the native audio/transcription pipeline from milestone 1 for longer real calls. Keep original transcript fragments and user corrections locally durable.
- Add Zoom Accessibility attribution and the approved Meet companion Chrome extension for participant names and speaking activity.
- Keep reasoning and coaching on App Server; test usage-limit and connection failures while prepared material stays available.
- Verify real Google Meet/Zoom behavior with headphones and device changes.

Acceptance: test both human audio sources, transcript completeness/gap reporting, speaker correction, overlapping speech, interruption, disconnect/recovery, credential handling, session shutdown, and presentation behavior on the receiving side. Do not claim verified full functionality from a synthetic replay alone.

## 5. Optional GPT-Live evaluation

After the native live pipeline works, evaluate whether GPT-Live-1 offers enough measurable improvement to justify adding it. Possible later uses include spoken rehearsal and intake. Preserve the user's restriction on separately billed AI APIs, and do not replace the working native pipeline based on documentation alone. If selected, measure account availability, session cost, transcript quality, timing, and compatibility with App Server reasoning.

## Development practice

Commit after coherent, validated milestones. Use subagents for bounded independent implementation or review work when useful. Run meaningful tests for persistence, protocol handling, and lifecycle behavior; visually verify native UI and validate actual external integrations separately. Keep personal data and credentials outside Git.

## Required computer-use verification

The user explicitly requires computer use to test the application. Launch and operate the real native app through the computer-use tools as it becomes available. Compilation, model-level tests, and synthetic replay alone do not satisfy this requirement.

- Create and switch calls, type into the composer, send messages, stop generation, and inspect streamed App Server responses.
- Import a fixture PDF through the actual UI, open its context, and use research and prepared answers in the chat.
- Open and edit notes; open the sidebar transcript file action; search, select, and correct transcript text; ask about a selection.
- Quit/relaunch the app and verify persisted content and the correct conversation resume through the interface.
- Exercise resizing, scrolling, keyboard navigation, text selection, and standard editing shortcuts. Inspect representative light/dark layouts and long messages for clipping and focus errors.
- When the HUD exists, operate pop out, direct questions, hide, return to chat, and End call. Verify window placement, focus behavior, readable full stories, and the independent call lifecycle.
- Save useful screenshots and record the exercised scenarios and observed results. Distinguish completed UI checks from deferred audio or receiver-side sharing tests. Report unavailable computer-use access as an unverified check, never a pass.

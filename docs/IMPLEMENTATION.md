# Implementation milestones

This is the intended build order, not a record of completed implementation. The user requested remaining clarification before starting the build goal loop.

## 1. Native chat and real backend

- Create a launchable native application with past calls, New call, chat, composer, and restrained native styling.
- Connect to the installed Codex App Server through its documented protocol and existing ChatGPT authentication.
- Support streaming, cancellation, actionable connection failures, and conversation resume.
- Persist call metadata and map it to the correct backend thread.

Acceptance: create two calls, chat in each using real App Server responses, restart, resume the correct histories, and verify that cancellation and reconnection do not corrupt or duplicate messages. No mock answers in the ordinary app flow.

## 2. Useful preparation and durable call records

- Implement conversational intake and editable prepared introductions/stories/questions.
- Support text, PDF extraction, links, and source-backed research through App Server tools.
- Add notes and full transcript views, corrections, search, selection-to-chat, and export.
- Make prior-call context retrievable when relevant to a user request.
- Use imported or synthetic transcripts explicitly as development fixtures while live audio is deferred.

Acceptance: prepare a call using a PDF and a research link, refine and retain an approved answer, reopen all data after restart, correct/search a transcript, and ask grounded questions about selected and earlier-call material. AI notes updates must preserve manual edits.

## 3. Call engine and floating HUD

- Separate call lifecycle from main-window/HUD visibility.
- Add the upper floating panel, one recommendation, small coaching strip, direct-question input, hide, return, and End call actions.
- Keep an answer stable during local speech and allow explicit replacement.
- Make prepared material available during backend interruption.

Acceptance: replay a scripted conversation and verify introduction, short follow-up, full prepared answer retrieval, mid-answer stability, direct questions, and ending. Hiding or returning to chat must not end the call; End call must stop all live work.

## 4. Live audio and GPT-Live-1

- Integrate separate microphone and meeting audio capture on this Mac.
- Add GPT-Live-1 transcript ingestion with locally durable original fragments and user corrections.
- Add Zoom Accessibility attribution and the approved Meet companion Chrome extension for participant names and speaking activity.
- Route reasoning and coaching through App Server and account for Live API session costs.
- Verify real Google Meet/Zoom behavior with headphones and device changes.

Acceptance: test both human audio sources, transcript completeness/gap reporting, speaker correction, overlapping speech, interruption, disconnect/recovery, credential handling, session shutdown, and presentation behavior on the receiving side. Do not claim verified full functionality from a synthetic replay alone.

## Development practice

Commit after coherent, validated milestones. Use subagents for bounded independent implementation or review work when useful. Run meaningful tests for persistence, protocol handling, and lifecycle behavior; visually verify native UI and validate actual external integrations separately. Keep personal data and credentials outside Git.

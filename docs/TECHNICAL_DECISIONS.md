# Technical decisions and research

Checked September 11, 2026. Documented capability is not evidence of measured performance on this user's calls.

## Confirmed native application stack

The user confirmed SwiftUI for the main chat and AppKit where precise window, focus, and floating-panel behavior is required. Use native audio capture and a local persistence layer. Framework memory use has not been benchmarked. Computer-use testing of the actual running app is required in addition to appropriate automated checks.

[Tauri](https://v2.tauri.app/concept/architecture/) uses a system WebView and is a reasonable alternative, but would introduce a web/native boundary alongside the macOS audio and accessibility work this product still needs. Prefer direct native integration here.

Design reference: [Apple's macOS human interface guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos).

Local inspection found macOS 26.6, arm64, Swift 6.3.3, and command line developer tools. A full Xcode installation was not established by these checks.

## Codex App Server is mandatory

Local `codex-cli 0.154.0` is installed and `codex login status` reports ChatGPT authentication. No credentials were read or copied. No model inference or application integration has been tested yet.

The [App Server documentation](https://learn.chatgpt.com/docs/app-server) provides managed ChatGPT authentication, persistent threads, streamed events, model discovery, and tool integration. Proposed architecture: a Swift service manages a local App Server process over stdio, maps calls to persistent threads, and resumes them after restart. Discover supported models and reasoning efforts using `model/list` rather than hardcoding an unsupported "no reasoning" value. Account access and usage limits remain runtime concerns.

All preparation, research, story work, notes generation, answer selection, coaching, and post-call analysis run through App Server. No direct paid Responses backend or third-party AI fallback is authorized.

## GPT-Live-1: deferred candidate

The user wants the core application built without this integration first. GPT-Live-1 remains the only authorized separately billed AI API candidate, but has not been selected as the final audio implementation. Keep all core reasoning and tools on Codex App Server.

[GPT-Live-1](https://developers.openai.com/api/docs/models/gpt-live-1) is a full-duplex voice model. Published session pricing is $0.05 per minute, billed per second, with backend usage separate. A single continuously open one-hour session is therefore $3 before any separately billed backend. Multiple sessions multiply session cost.

The [client delegation mode](https://developers.openai.com/api/docs/guides/live-delegation) lets the application select and execute its own backend. Proposed fit: use App Server for the reasoning and tools, and keep the full prepared answers in the application. Do not choose managed Responses delegation, which would violate the user's backend constraint.

For a silent visual copilot, natural generated speech is not the acceptance criterion. Evaluate input transcript accuracy, timing, continuous listening, and interruptions. The application must control/discard generated audio instead of relying on a prompt to prevent playback. GPT-Live's suitability for this passive-listening use case is untested.

Potential later uses include spoken intake and voice rehearsal, where the model's spoken interaction is directly useful. Audio-based timing cues are an experiment to evaluate, not an established advantage over transcript-driven coaching. These possibilities do not expand the current build scope.

### Transcripts

[Live session documentation](https://developers.openai.com/api/docs/guides/live-conversations) exposes timestamped input and output transcript fragments. We can persist input fragments directly. Input refers to audio supplied to the model; output refers to the AI's speech, not the second human participant. Both humans must be captured as input. The documented fragments are not authoritative completed turns or individual human speaker labels. Preserve originals and implement revisable transcript grouping, speaker assignment, and capture-gap reporting in the app.

This differs from the older Realtime API's separate transcription configuration. Do not copy older Realtime event names or turn handling into a GPT-Live implementation.

## Audio and speaker identity

Capture microphone and meeting/system audio separately. With headphones, microphone audio can represent the local user and meeting audio the remote side. Exact named participants require additional signals; who a speaker is addressing is a contextual inference.

Granola documents [Zoom speaker tags](https://docs.granola.ai/help-center/taking-notes/speaker-attribution-zoom) using macOS Accessibility to read participant names and active-speaker information. Its [Meet integration](https://docs.granola.ai/help-center/taking-notes/speaker-attribution-google-meet) uses a browser extension. These are precedents for platform adapters, not proof that our integration is already implemented. Missing signals, overlap, and shared meeting-room devices require conservative labels and editable corrections.

[Granola's security page](https://www.granola.ai/security) names Deepgram and Assembly as transcription providers, and OpenAI and Anthropic for AI processing. It describes desktop microphone/meeting capture without a bot and storing transcripts/notes instead of recordings. This explains Granola; it is not authorization to use those transcription APIs in Oblivion.

## Quality targets to measure

- Preserve questions, names, quantities, negations, corrections, and commitments.
- Distinguish the local user from remote speech before adding named participant labels.
- Measure question-to-useful-recommendation latency, including audio, transcription, retrieval, and inference.
- Stress overlapping speech, backchannels, pauses, long answers, and device changes.
- Detect dropped audio and disconnections rather than silently presenting an incomplete transcript as complete.
- Never replace a displayed answer mid-delivery due only to a partial transcript revision.

No speech accuracy percentage, latency target achievement, or reliable capture-exclusion claim has been established yet. Those require a real audio and presentation test on this Mac in the secondary phase.

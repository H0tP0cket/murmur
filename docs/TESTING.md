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

## Native UI and real Chrome capture

Computer use exercised the following in the built application with two clearly fictional calls:

- Free-form preparation with real streamed Codex responses; separate call histories, stopped response recovery, and persistence after relaunch.
- Imported a selectable-text PDF through NSOpenPanel. Codex correctly answered its threshold, reviewer count, and duration. Requested current Apple documentation research; a source-linked response appeared after the real research tool ran.
- Created and saved a full approved story with matching-question cues; confirmed its exact wording survived restart.
- Edited manual notes and generated notes. A subsequent AI update appeared as a proposal and preserved the user's edited wording until accepted.
- Inspected light/dark main chat and long responses. Fixed an infinite SwiftUI layout loop caused by competing scroll anchoring and an unconstrained attachment strip. Streaming now follows the bottom unless the user scrolls away.
- Granted Screen & System Audio Recording through System Settings. Captured an actual native Chrome Incognito tab playing a 20-second synthetic speech fixture through the app-scoped ScreenCaptureKit stream. This is real OS capture of generated test speech, not a mocked transcript or a real human interview. Diagnostic audio metadata confirmed 48 kHz buffers and nonzero RMS.
- Six accurate captured passages preserved negation, $50,000, three reviewers, 40 minutes, downstream rework, and the production-ownership question. That question automatically displayed the complete approved 133-word story in the upper HUD. The expanded panel fit the full answer.
- A private question about threshold and duration returned the correct $50,000/40-minute answer while the call continued. Return to chat and Pop out preserved the active session. Local menu shortcuts for pop-out/return worked.
- Searched the captured transcript, changed a speaker to Morgan, edited a passage while preserving its original, and used Ask about this to populate the composer with the corrected passage and timestamp. Exported Markdown through NSSavePanel and verified the corrected transcript in the resulting file.
- Imported a separate timestamped text transcript through NSOpenPanel; times and speaker names were retained.
- End call finalized capture and generated a grounded summary. The summary correctly said no answer to the final question had been recorded, despite the HUD having suggested one.

The HUD Hide button removed the HUD; subsequent computer-use app activation reopened the main window. A physical global-hotkey test from another application remains open: registration succeeded, but CUA's application-targeted synthetic keystroke did not establish global interception.

## Recovery and regression checks

- Ten enabled tests passed (one additional speech test was skipped in that run). The real App Server test now interrupts a long streamed turn and immediately starts another on the same thread, which finishes with the expected new response. Notifications are correlated by turn ID and old-process output is rejected.
- The actual on-device SpeechAnalyzer test passed again after startup/stop hardening: five final passages, 20.16125 seconds converted versus 20.16127 seconds of source audio.
- Added stable-answer tests for local speaking, pending recommendations, pin/unpin, and brief coaching updates. Added automatic speaker revision versus manual override coverage.
- A corrupt call is reported and left untouched while healthy calls still load.
- Audited and fixed startup cancellation, cleanup of each capture attempt, stale SCStream callbacks, inference cancellation delaying audio shutdown, concurrent End/Quit waiting for finalization, and speaker/transcript clock alignment.

## External checks still open

- Actual microphone/headphone capture, device changes, and human overlapping speech. Microphone approval was requested, but computer-use automatic review refused access to the system-owned UserNotificationCenter app. No microphone test is claimed as passed.
- Meet extension loading and multi-person attribution. The app installed the native host and extension files; bridge isolation tests pass. Browser policy explicitly blocked chrome://extensions and prohibited alternate automation routes. The user has been asked to load the unpacked extension manually.
- Zoom native Accessibility labels and multi-person attribution, prolonged calls, connection/usage-limit behavior under real service failure, and receiver-side tab/window sharing.
- These remaining checks are not implied by the successful synthetic-audio integration.

## Installed release and final checks

- Installed the signed local release at `~/Applications/Oblivion.app`; the install script verifies its signature. Added a reproducible native vector app icon. This is a personal ad-hoc-signed build, not a notarized distribution package.
- Replayed actual Chrome audio after switching live coaching to incremental transcript updates and exact story-ID retrieval. The complete approved answer appeared again in the running release. Preparation is retained in each coach thread; new and corrected segments replace their earlier versions. Threads rotate after 16 turns or preparation/profile changes.
- In native Chrome, used `getDisplayMedia` to select only the owned fixture tab, then inspected the resulting stream in a separate local receiver page while the native HUD was available. The video contained the fixture content and no HUD. Stopped the share and closed the owned native test tabs. This validates the local tab capture stream; it is not a remote Meet/Zoom receiver or full-display test.
- End during the unresolved microphone permission request returned immediately to idle. Confirmed that canceling setup without new audio no longer creates a duplicate summary from an older transcript.
- Added a real App Server failure/recovery check: disconnect the process during a streamed reply, assert the pending request fails, reconnect, create a fresh thread, and receive the expected response. It passed, along with same-thread interruption/replacement. Actual account usage-limit exhaustion is still untested.
- Original intake goals stay in bounded preparation context even after a long chat. A complete `conversation.md` file is available to the preparation/research assistant for material beyond the excerpt.
- Downloaded Zoom Workplace 7.1.5 from the official Zoom site, verified its Apple developer signature/notarization, and installed its application in `~/Applications`. The normal native login/join UI opened. Launching Zoom's own isolated test meeting stalled its main thread inside Core Audio device startup; computer-use window calls timed out. Stopped only the test Zoom process. Zoom meeting capture/attribution remains unverified.
- Archived both fictional test conversations through the native UI, restored System appearance and microphone-enabled defaults, ended every Oblivion session, and stopped the local fixture server. The archived evidence remains available locally.

## Reopen and permission verification

- Fixed AppDelegate's reopen handling to return `false` after restoring the existing main window. Apple's [reopen delegate documentation](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldhandlereopen(_:hasvisiblewindows:)) says custom handling should suppress the default behavior, which can otherwise create an untitled window when only an NSPanel exists.
- Added a read-only Audio access section in Settings using the application's native microphone authorization status and screen-capture preflight API. Computer use confirmed microphone status is unresolved (`notDetermined`) and screen/system audio is **Allowed**. The final unresolved label is **Approval needed**, since the API does not distinguish a prompt awaiting a decision from a prompt never shown. The section refreshes on app activation and has a manual Refresh button. It does not change permissions or begin recording.
- System audio inventory currently reports only the built-in MacBook Pro microphone and speakers. No connected headphone device was available for a headphones/device-change test.
- Started an isolated, microphone-off capture scoped to Zoom's idle login window. The native capture session and HUD started, with both audio meters at zero. After hiding the HUD and reopening Oblivion, the original `main-AppWindow-1` returned, and the Window menu listed only one Oblivion main window. Minimize/reopen also restored the same window while the call stayed active. End call returned to idle without generating a summary because no speech was captured.
- This idle Zoom check does not verify Zoom meeting speech, participant attribution, or the earlier Core Audio test-meeting startup stall.
- Archived the labeled lifecycle test, restored microphone-on/Chrome defaults, closed the idle Zoom app, and left the original fresh preparation chat selected. The microphone and Meet extension manual steps remain pending; no permission or extension-policy workaround was attempted.

## Microphone and installed Meet companion — September 11, afternoon

- The user approved microphone access and loaded the companion. The installed app now reports **Allowed** for microphone and screen/system audio. Started two microphone-enabled, Chrome-scoped sessions through the native UI.
- Played the known 20-second fixture in native Chrome through the built-in speakers. Both real ScreenCaptureKit channels produced accurate local SpeechAnalyzer transcripts, including negation, $50,000, three reviewers, 40 minutes, rework ownership, and the complete production-system question. Because speakers were in use, the microphone captured the same sound acoustically; this deliberately tests both channels, not independent human speakers or headphones.
- During playback the HUD showed **Holding your answer**. Across successive UI observations, the main answer remained unchanged while the short coaching line changed and both meters showed activity. The hold cleared after speech stopped. A second replay finalized the full last question while the call was still active; End call was not required to obtain it. Both ended sessions saved their transcripts without capture interruptions.
- The actual loaded extension popup reported **Connected to your active Oblivion call**. Its native-host envelope matched the active session and refreshed within a fraction of a second. With People closed it conservatively reported an incomplete roster. Opening People correctly identified the self participant and complete roster.
- Joined the isolated Meet from the user's second Chrome profile, with camera and microphone off, and admitted that profile from the host. The bridge reported two distinct participant IDs, one self and one remote, and a complete roster. Native Oblivion Settings displayed the remote participant's name. No external participants were invited or messaged.
- This establishes installed-extension/native-host integration and two-person roster attribution. Shared Meet media, multi-person active-speaker signals, actual Zoom meeting audio, connected headphones/device changes, human overlap, and physical global hotkeys remain unverified. Live tests were stopped before the user's requested visual refinement.

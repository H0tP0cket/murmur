# Product specification

The user's conversation and subsequent clarifications are authoritative. This document records that scope and distinguishes suggested additions from confirmed requirements.

## Audience and platform

- One user, on their own Apple Silicon Mac.
- Google Meet and Zoom, usually with headphones.
- Include a companion Chrome extension for Google Meet participant names and speaking activity in the live audio phase; approved September 11, 2026.
- A calm native Mac application using ChatGPT/Codex interaction patterns and Apple's design guidance.
- Working name: Oblivion.
- No accounts, cloud sync, calendar, project spaces, or dashboard required for the first release.

## Main application

The sidebar contains New call and past chats. One chat is the persistent home of one call, including preparation and the conversation afterward.

The main area is a proper streaming chat with a composer and attachments. Notes and Pop out/Call Mode are compact controls in the chat header. A transcript file icon appears when hovering over a call in the sidebar, next to its overflow menu. The transcript remains associated with that call rather than becoming a separate navigation category.

Use readable native typography, restrained colors, clear text hierarchy, a quiet sidebar, and standard keyboard/editing behavior. Avoid technical configuration and share-mode controls in the normal conversation flow.

## Preparation

A new call begins with one conversational intake prompt, not a required form. Invite context about:

- The user, their background, relevant experience, and relationship to the other person.
- The other person, their role/company, the setting, and how the call came about.
- The desired outcome, intended impression, and what the user wants to learn.
- Research, hypotheses, concerns, boundaries, and topics to avoid.

Continue a natural back-and-forth conversation until the user is satisfied. Clarify competing goals, improve introductions and questions, challenge leading phrasing, and help create and revise full prepared stories and answers. Support text, PDFs, links, and research. Available tools should support the preparation task without cluttering the interface.

Prepared stories must retain the user's confirmed facts, examples, metrics, and preferred wording. Do not invent achievements or silently replace an approved story with a different version.

## Call Mode

Pop out hides/minimizes the main application and presents a floating local HUD near the upper part of the display. It does not become a large centered overlay.

Two visible AI surfaces:

1. A small LIVE coaching strip with a brief observation or correction.
2. One dominant recommendation area below it: what to say or ask next.

The opening recommendation is a context-specific introduction derived from preparation. A simple follow-up is short. A substantive question can surface the entire relevant prepared answer or story, with readable structure and enough vertical space to deliver it. Long answers remain accessible; do not impose a one-sentence cap.

Keep the primary answer stable while the user speaks. The small coaching strip can continue changing. Refresh the main recommendation when the other person responds or the user explicitly asks for an update. Generate candidates early as speech arrives, but do not replace useful text with unstable partial interpretations.

The user can open a small direct-question input with a configurable shortcut, initially Command-K. Answers use the preparation plus the transcript so far.

Returning to the main chat, including through the requested Command-X action, does not stop transcription or coaching. Preserve ordinary Cut behavior when typing and resolve global shortcut conflicts during implementation. Include an instant-hide action and a separate End call control in Call Mode. End call stops capture, live sessions, and coaching, then finalizes the call record.

Call-session state must be independent of window visibility. Provide access to End call from the main application as well so ending does not require the HUD to be visible.

## Notes and transcript

Notes open in a simple editable right sidebar. AI organizes useful findings, pain points, people/systems, follow-ups, and commitments. Preserve the user's edits when updating generated material.

The full transcript is searchable, selectable, copyable, and editable. Preserve original transcript data separately from user corrections. Allow timestamp navigation within the transcript and asking the associated chat about selected passages. Without retained audio, timestamp navigation means navigating transcript text, not playing a recording.

After End call, the same chat can summarize findings, unresolved questions, signals, opportunities, promises, recommended next steps, and a draft follow-up message. Sending messages is separate from drafting and requires explicit user authorization. Cross-call questions should retrieve the relevant earlier calls and make the source clear.

## Storage and presentation assumptions

Default to storing chats, attachments, notes, prepared material, and transcripts locally. Local storage does not mean local inference: relevant context is sent through Codex App Server, and live audio would be sent to GPT-Live-1. Default to no retained raw audio recording; revisit only if requested. Do not claim a provider's server-side retention policy is controlled by our local storage choice.

Explain presentation safety during intake/onboarding. Keep the HUD in its own native window and support sharing a selected application/window or using an unshared display. Do not promise universal invisibility under full-display capture or infer a verified safe state from incomplete meeting-app signals.

## Suggested additions for discussion

These are recommendations, not reasons to expand the main navigation:

- Reusable personal background and approved stories, selectable for each call.
- A compact preparation brief with goals, opening, priority questions, and known evidence gaps.
- Rehearsal in the same chat, including skeptical follow-ups and short/full versions of stories.
- Source references on research claims and an explicit distinction between known facts and hypotheses.
- Tracking unanswered questions, promises, and topics already covered during a call.
- Prepared material that stays readable if inference disconnects or hits a usage limit.

## Remaining defaults

- English-first behavior and no retained audio are proposed defaults, not prerequisites for building the main app.

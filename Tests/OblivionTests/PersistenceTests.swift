import Foundation
import AVFoundation
import CoreMedia
import Testing
@testable import Oblivion

@Test @MainActor func callRoundTripPreservesEditsAndApprovedStory() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("oblivion-test-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let library = try LibraryStore(root: root)
    var call = CallRecord(title: "Discovery with Morgan")
    call.notes = "My own note — keep this wording."
    call.generatedNotes = "AI findings"
    call.stories = [PreparedStory(title: "Production ownership", body: "I reduced review time by 25%.", cues: "Ownership, impact")]
    let session = CallSession(endedAt: Date())
    call.sessions = [session]
    call.transcript = [TranscriptSegment(sessionID: session.id, source: "meeting", speaker: "Morgan", start: 12, end: 15, original: "We do automate it", correction: "We don’t automate it")]
    try library.save(call)
    let loaded = try library.load()
    #expect(loaded.count == 1)
    #expect(loaded[0].notes == call.notes)
    #expect(loaded[0].transcript[0].original == "We do automate it")
    #expect(loaded[0].transcript[0].text == "We don’t automate it")
    #expect(loaded[0].stories[0].approved)
    #expect(loaded[0].stories[0].body == call.stories[0].body)
    #expect(try String(contentsOf: library.directory(call.id).appendingPathComponent("transcript.txt"), encoding: .utf8).contains("We don’t automate it"))
}

@Test @MainActor func corruptRecordIsReportedWithoutOverwritingIt() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("oblivion-test-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let library = try LibraryStore(root: root)
    let call = CallRecord()
    try library.save(call)
    let url = library.directory(call.id).appendingPathComponent("call.json")
    let original = Data("corrupted fixture".utf8)
    try original.write(to: url)
    let healthy = CallRecord(title: "Healthy call")
    try library.save(healthy)
    #expect(try library.load().map(\.id) == [healthy.id])
    #expect(library.loadWarnings.count == 1)
    #expect(try Data(contentsOf: url) == original)
}

@Test @MainActor func longIntakeRetainsInitialGoalAndFullConversationSource() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("oblivion-test-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let library = try LibraryStore(root: root)
    var call = CallRecord()
    call.messages = [ChatMessage(role: "user", text: "Initial goal: understand ownership, not pitch."), ChatMessage(role: "assistant", text: String(repeating: "Preparation discussion. ", count: 1600) + "Middle fact: use the approved production story." + String(repeating: "More discussion. ", count: 1600)), ChatMessage(role: "user", text: "Latest decision: lead with the workflow question.")]
    #expect(call.preparationText.contains("Initial goal: understand ownership, not pitch."))
    #expect(call.preparationText.contains("Latest decision: lead with the workflow question."))
    try library.save(call)
    let full = try String(contentsOf: library.directory(call.id).appendingPathComponent("conversation.md"), encoding: .utf8)
    #expect(full.contains("Middle fact: use the approved production story."))
    #expect(full.count > 50000)
}

@Test @MainActor func coachingHoldsFullAnswersWhileSpeakingAndPinned() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("oblivion-test-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let state = AppState(root: root, connect: false)
    let first = Recommendation(kind: "ANSWER", coaching: "Lead with impact.", answer: "My complete approved story.")
    let next = Recommendation(kind: "ASK", coaching: "Ask about ownership.", answer: "Who owns that work?")
    state.acceptRecommendation(first)
    state.audio.localSpeaking = true
    state.acceptRecommendation(next)
    #expect(state.recommendation.answer == first.answer)
    #expect(state.recommendation.coaching == next.coaching)
    state.audio.localSpeaking = false
    state.audio.onSpeakingChanged(false)
    #expect(state.recommendation.answer == next.answer)
    state.recommendationPinned = true
    state.acceptRecommendation(first)
    #expect(state.recommendation.answer == next.answer)
    state.recommendationPinned = false
    #expect(state.recommendation.answer == first.answer)
}

@Test @MainActor func independentCallContextsAndArchiveSurviveRestart() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("oblivion-test-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let state = AppState(root: root, connect: false)
    let first = state.newCall(), second = state.newCall()
    state.modify(first) { $0.title = "First"; $0.notes = "First private notes"; $0.threadID = "thread-one" }
    state.modify(second) { $0.title = "Second"; $0.notes = "Second private notes"; $0.threadID = "thread-two" }
    state.archive(first)
    let restored = AppState(root: root, connect: false)
    #expect(restored.visibleCalls.count == 1)
    #expect(restored.visibleCalls.first?.threadID == "thread-two")
    restored.showArchived = true
    #expect(restored.visibleCalls.first?.notes == "First private notes")
    restored.archive(first)
    restored.showArchived = false
    #expect(restored.visibleCalls.count == 2)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["OBLIVION_CODEX_TEST"] == "1"))
@MainActor func realCodexStreamAndStructuredCoaching() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("oblivion-codex-test-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let service = CodexService()
    defer { service.disconnect() }
    try await service.connect()
    #expect(service.isConnected)
    #expect(!service.models.isEmpty)
    let thread = try await service.thread(cwd: root, live: true)
    var streamed = ""
    let result = try await service.run(threadID: thread, text: "The user is Alex, meeting Morgan to understand manual review. Morgan just said: We do NOT automate reviews above fifty thousand dollars. Give one grounded follow-up question. Do not invent facts.", live: true, schema: Recommendation.schema, onText: { streamed = $0 })
    let recommendation = try JSONDecoder().decode(Recommendation.self, from: Data(result.utf8))
    #expect(!streamed.isEmpty)
    #expect(!recommendation.answer.isEmpty)
    #expect(!recommendation.coaching.isEmpty)
    print("Codex integration passed: \(service.model(live: true) ?? "automatic"), \(result.count) characters.")
    var cancellationRequested = false
    do {
        _ = try await service.run(threadID: thread, text: "Write a detailed 2500-word meeting preparation guide.", live: true, onText: { text in
            if text.count > 20 && !cancellationRequested {
                cancellationRequested = true
                Task { await service.cancel(threadID: thread) }
            }
        })
        Issue.record("Expected the long response to be interrupted.")
    } catch is CancellationError { }
    let replacement = try await service.run(threadID: thread, text: "Reply with exactly replacement-complete and nothing else.", live: true)
    #expect(cancellationRequested)
    let replacementText = (try? JSONDecoder().decode(String.self, from: Data(replacement.utf8))) ?? replacement.trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(replacementText == "replacement-complete")
    var disconnectedDuringReply = false
    do {
        _ = try await service.run(threadID: thread, text: "Write a detailed 2500-word guide to interview preparation.", live: true, onText: { text in
            if text.count > 20 && !disconnectedDuringReply { disconnectedDuringReply = true; service.disconnect() }
        })
        Issue.record("Expected the interrupted process to fail its pending reply.")
    } catch { #expect(error.localizedDescription.contains("disconnected")) }
    #expect(disconnectedDuringReply)
    #expect(!service.isConnected)
    try await service.connect()
    let fresh = try await service.thread(cwd: root, live: true)
    let recovered = try await service.run(threadID: fresh, text: "Reply with exactly reconnected and nothing else.", live: true)
    let recoveredText = (try? JSONDecoder().decode(String.self, from: Data(recovered.utf8))) ?? recovered.trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(recoveredText == "reconnected")
}

@Test func volatileTranscriptRevisionsPreserveNegationAndSeparateSources() {
    var call = CallRecord()
    let session = CallSession(); call.sessions = [session]
    TranscriptIngestor.apply(SpeechUpdate(source: "meeting", text: "We do automate", start: 1, end: 3, isFinal: false), speaker: "Morgan", session: session.id, to: &call)
    let id = call.transcript[0].id
    call.transcript[0].correction = "User's correction"
    TranscriptIngestor.apply(SpeechUpdate(source: "microphone", text: "Right", start: 2, end: 2.5, isFinal: true), speaker: "You", session: session.id, to: &call)
    let final = SpeechUpdate(source: "meeting", text: "We do not automate reviews above fifty thousand dollars.", start: 1.3, end: 5, isFinal: true)
    TranscriptIngestor.apply(final, speaker: "Morgan", session: session.id, to: &call)
    TranscriptIngestor.apply(final, speaker: "Morgan", session: session.id, to: &call)
    #expect(call.transcript.count == 2)
    #expect(call.transcript[0].id == id)
    #expect(call.transcript[0].original.contains("not automate"))
    #expect(call.transcript[0].correction == "User's correction")
    #expect(call.transcript[1].speaker == "You")
    #expect(call.transcript.allSatisfy { $0.isFinal })
}

@Test func finalAttributionUpdatesAutomaticNamesButPreservesManualNames() {
    var call = CallRecord(); let session = UUID()
    let interim = SpeechUpdate(source: "meeting", text: "We do", start: 1, end: 2, isFinal: false)
    let final = SpeechUpdate(source: "meeting", text: "We do not automate it.", start: 1, end: 4, isFinal: true)
    TranscriptIngestor.apply(interim, speaker: "Meeting", session: session, to: &call)
    TranscriptIngestor.apply(final, speaker: "Morgan", session: session, to: &call)
    #expect(call.transcript[0].speaker == "Morgan")
    call.transcript = []
    TranscriptIngestor.apply(interim, speaker: "Meeting", session: session, to: &call)
    call.transcript[0].speaker = "Taylor"; call.transcript[0].speakerEdited = true
    TranscriptIngestor.apply(final, speaker: "Morgan", session: session, to: &call)
    #expect(call.transcript[0].speaker == "Taylor")
}

@Test @MainActor func callDraftsDoNotLeakAcrossConversations() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("oblivion-test-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let state = AppState(root: root, connect: false)
    let first = state.newCall(); state.composer = "First unfinished question"
    let second = state.newCall()
    #expect(state.composer.isEmpty)
    state.composer = "Second question"
    state.selectedID = first
    #expect(state.composer == "First unfinished question")
    state.selectedID = second
    #expect(state.composer == "Second question")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["OBLIVION_SPEECH_TEST"] != nil))
@MainActor func realOnDeviceSpeechPreservesKnownFacts() async throws {
    let path = ProcessInfo.processInfo.environment["OBLIVION_SPEECH_TEST"]!
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    var finals: [SpeechUpdate] = [], errors: [String] = []
    let pipeline = SpeechPipeline(source: "fixture", onResult: { if $0.isFinal { finals.append($0) } }, onError: { errors.append($0) })
    try await pipeline.start()
    let sampleRate = file.processingFormat.sampleRate
    while file.framePosition < file.length {
        let position = file.framePosition
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(sampleRate / 5))!
        try file.read(into: buffer)
        pipeline.append(buffer, time: CMTime(seconds: Double(position) / sampleRate, preferredTimescale: 48000))
        await Task.yield()
    }
    await pipeline.stop()
    print("Converted duration: \(pipeline.processedDuration), source: \(Double(file.length)/sampleRate)")
    #expect(abs(pipeline.processedDuration - Double(file.length)/sampleRate) < 0.1)
    let transcript = finals.map(\.text).joined(separator: " ").lowercased()
    #expect(errors.isEmpty)
    #expect(transcript.contains("not automate"))
    #expect(transcript.contains("review"))
    #expect(transcript.contains("forty") || transcript.contains("40"))
    #expect(finals.count > 1)
    #expect((finals.last?.end ?? 0) > 10)
    print("Local speech integration: \(finals.count) finalized passages, \(transcript.count) characters.")
}

@Test func speakerAttributionRejectsAmbiguousOrIncompleteRosters() {
    let me = MeetingParticipant(id: "me", name: "Alex", isSelf: true)
    let other = MeetingParticipant(id: "other", name: "Morgan", isSelf: false)
    var event = SpeakerEnvelope(session: "s", room: "aaa-bbbb-ccc", receivedAt: 0, participants: [me, other], activeIDs: [], completeRoster: false)
    #expect(event.remoteSpeaker() == nil)
    event.completeRoster = true
    #expect(event.remoteSpeaker() == "Morgan")
    event.participants.append(MeetingParticipant(id: "third", name: "Taylor", isSelf: false))
    #expect(event.remoteSpeaker() == nil)
    event.activeIDs = ["other"]
    #expect(event.remoteSpeaker() == "Morgan")
    event.activeIDs = ["me", "other"]
    #expect(event.remoteSpeaker() == nil)
    #expect(ZoomSpeakerReader.explicitName("Morgan is speaking") == "Morgan")
    #expect(ZoomSpeakerReader.explicitName("Morgan's video") == nil)
}

@Test func transcriptImportRetainsRealTimesAndSpeakerNames() throws {
    let session=UUID()
    let plain=try TranscriptImporter.parse("00:03 Morgan: We do not automate it.\n00:12 Alex: Who owns it?",session:session)
    #expect(plain.map(\.speaker) == ["Morgan","Alex"])
    #expect(plain.map(\.start) == [3,12])
    let vtt=try TranscriptImporter.parse("WEBVTT\n\n00:01:03.200 --> 00:01:08.500\n<v Morgan>Forty minutes.</v>\n",session:session)
    #expect(vtt[0].speaker == "Morgan")
    #expect(vtt[0].start == 63.2)
    #expect(vtt[0].end == 68.5)
    #expect(vtt[0].text == "Forty minutes.")
    let untimed=try TranscriptImporter.parse("Morgan: No timestamps here.",session:session)
    #expect(untimed[0].timestamp == "—")
}

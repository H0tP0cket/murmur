import Foundation
import AVFoundation
import Testing
@testable import Oblivion

private func passage(_ text: String, source: String = "meeting", start: Double = 10, end: Double = 14, session: UUID) -> TranscriptSegment {
    TranscriptSegment(sessionID: session, source: source, speaker: source == "meeting" ? "Morgan" : "You", start: start, end: end, original: text)
}

@Test func echoReconciliationIsConservativeAndReversible() throws {
    let session = UUID()
    let remote = passage("Our agents enter the policy details on forty screens", session: session)
    var mic = passage(remote.text, source: "microphone", start: 10.2, end: 14.1, session: session)
    #expect(TranscriptQuality.isEcho(mic, of: remote))
    var call = CallRecord(); call.transcript = [mic, remote]
    TranscriptQuality.reconcile(&call, session: session, around: 10)
    #expect(call.cleanTranscript.count == 1 && call.transcript.count == 2)
    #expect(call.rawTranscriptText.contains("You"))
    call.transcript[0].correction = "I was repeating this for confirmation."
    #expect(call.cleanTranscript.count == 2)
    mic.start = 14.2; mic.end = 18
    #expect(!TranscriptQuality.isEcho(mic, of: remote)) // An actual repeated question later.
    let short = passage("Yes that is correct", session: session)
    #expect(!TranscriptQuality.isEcho(passage(short.text, source: "microphone", session: session), of: short))
    for other in ["Our agents do not enter the policy details on forty screens", "Our agents enter the policy details on 14 screens", "The workflow is owned by the service team instead"] {
        #expect(!TranscriptQuality.isEcho(passage(other, source: "microphone", session: session), of: remote))
    }
    var partial = passage(remote.text, source: "microphone", session: session); partial.isFinal = false
    #expect(!TranscriptQuality.isEcho(partial, of: remote))
    partial.isFinal = true; partial.speakerEdited = true
    #expect(!TranscriptQuality.isEcho(partial, of: remote))
    #expect(!TranscriptQuality.isEcho(passage(remote.text, source: "microphone", session: UUID()), of: remote))
    // Corrections that disagree on negation must remain visible for human review.
    let negation = passage("The experiment with those forty screens did not work", session: session)
    #expect(!TranscriptQuality.isEcho(passage("The experiment with those forty screens did work", source: "microphone", session: session), of: negation))
    let decoded = try JSONDecoder().decode(CallRecord.self, from: JSONEncoder().encode(call))
    #expect(decoded.cleanTranscript.count == 2)
}

@Test func finalRevisionsAndConfidenceSurviveBothArrivalOrders() {
    let session = UUID(), text = "Our agents enter the policy details on forty screens"
    for sources in [["microphone", "meeting"], ["meeting", "microphone"]] {
        var call = CallRecord()
        for source in sources {
            TranscriptIngestor.apply(SpeechUpdate(source: source, text: "Our agents enter", start: 10, end: 11, isFinal: false), speaker: source, session: session, to: &call)
            TranscriptIngestor.apply(SpeechUpdate(source: source, text: text, start: 10, end: 14, isFinal: true, confidence: 0.6), speaker: source, session: session, to: &call)
        }
        #expect(call.transcript.count == 2)
        #expect(call.cleanTranscript.count == 1)
        #expect(call.cleanTranscript[0].confidence == 0.6)
        #expect(call.transcriptText.contains("uncertain wording"))
    }
}

@Test func preparationRetrievesTheMiddleAndMemoryPersists() throws {
    var call = CallRecord()
    call.messages = [ChatMessage(role: "user", text: String(repeating: "Unrelated background. ", count: 1800) + "\nZEBRA workflow has forty screens and duplicate paper entry.\n" + String(repeating: "Unrelated conclusions. ", count: 1800))]
    let source = LiveContext.source(call, background: "Technical founder")
    #expect(LiveContext.chunks(source).joined() == source)
    let prep = LiveContext.preparation(call, background: "Technical founder", query: "ZEBRA workflow paper entry")
    #expect(prep.contains("ZEBRA workflow has forty screens"))
    call.liveBrief = LiveBrief(fingerprint: LiveContext.fingerprint(source), text: "Verified complete brief")
    #expect(LiveContext.preparation(call, background: "Technical founder", query: "").contains("Verified complete brief"))
    call.messages[0].text += " A correction"
    #expect(!LiveContext.preparation(call, background: "Technical founder", query: "").contains("Verified complete brief"))
    call.liveMemory = ConversationMemory(counterpartRole: "Insurance adviser, not a claims operator", direction: "Learning and referral", facts: ["Forty screens"], answered: ["Who fills the form"], open: ["Why the paper is copied"], nextStep: "Concrete example")
    let restored = try JSONDecoder().decode(CallRecord.self, from: JSONEncoder().encode(call))
    #expect(restored.liveMemory == call.liveMemory)
    #expect(CallVocabulary.extract("Morgan uses Guidewire and ACORD with Avery Quinn").contains("Avery Quinn"))
}

@Test func coachingWaitsForMeaningfulConfirmedSpeechAndRequiresEvidence() {
    var cadence = CoachingCadence()
    let now = Date(), session = UUID()
    var line = passage("We enter the same details on forty screens", session: session)
    line.isFinal = false
    #expect(!cadence.shouldRequest([line], now: now, lastSpeech: .distantPast, force: false))
    line.isFinal = true
    #expect(cadence.shouldRequest([line], now: now, lastSpeech: .distantPast, force: false))
    cadence.mark([line], now: now)
    #expect(!cadence.shouldRequest([line], now: now.addingTimeInterval(20), lastSpeech: .distantPast, force: false))
    let acknowledgement = passage("Yes", start: 15, end: 16, session: session)
    #expect(!cadence.shouldRequest([line, acknowledgement], now: now.addingTimeInterval(20), lastSpeech: .distantPast, force: false))
    let next = passage("Someone then copies every field to a paper form", start: 15, end: 20, session: session)
    #expect(!cadence.shouldRequest([line, next], now: now.addingTimeInterval(6), lastSpeech: now.addingTimeInterval(6), force: false))
    #expect(cadence.shouldRequest([line, next], now: now.addingTimeInterval(7), lastSpeech: now.addingTimeInterval(6), force: false))
    #expect(cadence.shouldRequest([line, next], now: now.addingTimeInterval(13), lastSpeech: now.addingTimeInterval(13), force: false))
    var result = LiveCoachingResult(recommendation: Recommendation(kind: "ASK", coaching: "", answer: "Why copy the forty screens back to paper?"), memory: ConversationMemory(), anchorIDs: [line.id.uuidString], questionGap: "Why paper remains necessary")
    #expect(result.grounded(in: [line, next]))
    result.anchorIDs = [UUID().uuidString]
    #expect(!result.grounded(in: [line, next]))
    result.recommendation.kind = "INTRO"
    #expect(!result.grounded(in: [line, next]))
    #expect(result.grounded(in: [], introduction: true))
}

@Test @MainActor func listenCoachingDoesNotReplaceTheQuestionAndAskDismissesEverything() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let state = AppState(root: root, connect: false)
    state.recommendation = Recommendation(kind: "ASK", coaching: "", answer: "Who copies the paper form?")
    state.acceptRecommendation(Recommendation(kind: "LISTEN", coaching: "Let them finish.", answer: ""))
    #expect(state.recommendation.answer == "Who copies the paper form?")
    #expect(state.recommendation.coaching == "Let them finish.")
    state.recommendationPinned = true
    state.acceptRecommendation(Recommendation(kind: "ASK", coaching: "Follow this detail.", answer: "Which fields require re-entry?"))
    #expect(state.recommendation.answer == "Who copies the paper form?")
    state.recommendationPinned = false
    #expect(state.recommendation.answer == "Which fields require re-entry?")
    state.showDirectQuestion = true; state.directQuestion = "Draft"; state.directAnswer = "An old answer"; state.directBusy = true
    state.dismissDirectQuestion()
    #expect(!state.showDirectQuestion && !state.directBusy && state.directQuestion.isEmpty && state.directAnswer.isEmpty)
}

private func signal(_ count: Int, seed: UInt64) -> [Int16] {
    var state = seed
    return (0..<count).map { _ in
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int16(Int((state >> 32) % 16000) - 8000)
    }
}
private func energy(_ values: [Int16]) -> Double { values.reduce(0) { $0 + Double($1) * Double($1) } / Double(max(1, values.count)) }

@Test func adaptiveFilterSuppressesDelayedEchoWithoutMutingDoubleTalk() {
    let count = 16000 * 8, delay = 640
    let remote = signal(count, seed: 7), local = signal(count, seed: 83)
    let mic = (0..<count).map { i in Int16(i >= delay ? Double(remote[i-delay]) * 0.55 : 0) }
    let filter = AcousticEchoCanceller()
    var cleaned: [Int16] = []
    for start in stride(from: 0, to: count, by: 160) {
        let near = (start..<start+160).map { i in Int16(Int(mic[i]) + (i >= count/2 ? Int(local[i]) : 0)) }
        cleaned += filter.process(microphone: near, reference: Array(remote[start..<start+160]))
    }
    let echoResidual = energy(Array(cleaned[48000..<64000])) / energy(Array(mic[48000..<64000]))
    let doubleTalk = energy(Array(cleaned[96000..<count])) / energy(Array(local[96000..<count]))
    print("AEC synthetic residual=\(echoResidual), double-talk energy ratio=\(doubleTalk)")
    #expect(echoResidual < 0.2)
    #expect(doubleTalk > 0.65 && doubleTalk < 1.4)
    filter.reset()
    var solo: [Int16] = []
    for start in stride(from: 0, to: 16000, by: 160) { solo += filter.process(microphone: Array(local[start..<start+160]), reference: Array(repeating: 0, count: 160)) }
    #expect(energy(solo) / energy(Array(local[0..<16000])) > 0.8)
}

@Test func captureProcessorHandlesReorderingGapsAndGenerationBoundaries() throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
    func buffer(_ count: Int) throws -> AVAudioPCMBuffer {
        let b = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)))
        b.frameLength = AVAudioFrameCount(count)
        for i in 0..<count { b.floatChannelData![0][i] = Float(sin(Double(i) * 0.2) * 0.2) }
        return b
    }
    let processor = CaptureAudioProcessor(), old = UUID(), current = UUID()
    processor.begin(old)
    let initial = processor.consume(try buffer(400), pts: CMTime(seconds: 100, preferredTimescale: 16000), source: "microphone")
    #expect(initial.isEmpty) // Waits briefly for corresponding playback reference.
    let reordered = processor.consume(try buffer(400), pts: CMTime(seconds: 100, preferredTimescale: 16000), source: "meeting")
    #expect(reordered.filter { $0.source == "microphone" }.reduce(0) { $0 + Int($1.buffer.frameLength) } == 320)
    let tail = processor.finish(old)
    #expect(tail.reduce(0) { $0 + Int($1.buffer.frameLength) } == 80)
    #expect(processor.finish(old).isEmpty)
    processor.begin(current)
    #expect(processor.finish(old).isEmpty)
    _ = processor.consume(try buffer(160), pts: CMTime(seconds: 200, preferredTimescale: 16000), source: "microphone")
    let gap = processor.consume(try buffer(160), pts: CMTime(seconds: 400, preferredTimescale: 16000), source: "microphone")
    #expect(gap.count < 10) // No synthetic two hundred seconds of silence.
    let final = processor.finish(current)
    #expect(final.allSatisfy { $0.pts.seconds >= 400 })
}

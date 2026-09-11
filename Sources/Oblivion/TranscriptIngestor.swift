import Foundation

/// SpeechAnalyzer may revise a provisional passage's boundaries as well as its words.
/// Merge revisions within a source; simultaneous microphone/meeting speech stays separate.
enum TranscriptIngestor {
    static func apply(_ update: SpeechUpdate, speaker: String, session: UUID, to call: inout CallRecord) {
        let text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.contains(where: { $0.isLetter || $0.isNumber }), update.start.isFinite, update.end.isFinite else { return }
        let matches: (TranscriptSegment) -> Bool = { segment in
            segment.sessionID == session && segment.source == update.source &&
            (abs(segment.start - update.start) < 0.2 || (segment.start < update.end && segment.end > update.start))
        }
        if call.transcript.contains(where: { matches($0) && $0.isFinal && $0.original == text }) { return }
        let provisional = call.transcript.filter { matches($0) && !$0.isFinal }
        var next = provisional.first ?? TranscriptSegment(sessionID: session, source: update.source, speaker: speaker, start: update.start, end: update.end, original: text)
        next.start = max(0, update.start); next.end = max(next.start, update.end)
        next.original = text; next.isFinal = update.isFinal
        if next.speakerEdited != true { next.speaker = speaker }
        let replacedIDs = Set(provisional.map(\.id))
        call.transcript.removeAll { replacedIDs.contains($0.id) }
        call.transcript.append(next)
        let order = Dictionary(uniqueKeysWithValues: call.sessions.enumerated().map { ($0.element.id, $0.offset) })
        call.transcript.sort { lhs, rhs in lhs.sessionID == rhs.sessionID ? lhs.start < rhs.start : (order[lhs.sessionID] ?? 0) < (order[rhs.sessionID] ?? 0) }
    }
}

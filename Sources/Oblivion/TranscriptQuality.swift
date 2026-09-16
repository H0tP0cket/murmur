import Foundation

/// Echo reconciliation is reversible. The original microphone passage stays in
/// call.json and the raw transcript; only the default view/context hides it.
enum TranscriptQuality {
    static func words(_ text: String) -> [String] {
        text.lowercased().replacingOccurrences(of: "’", with: "'").split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map(String.init)
    }
    static func isEcho(_ mic: TranscriptSegment, of remote: TranscriptSegment) -> Bool {
        guard mic.source == "microphone", remote.source == "meeting", mic.sessionID == remote.sessionID,
              mic.speakerEdited != true, mic.correction == nil, mic.isFinal, remote.isFinal else { return false }
        let overlap = min(mic.end, remote.end) - max(mic.start, remote.start)
        let duration = max(0.1, min(mic.end - mic.start, remote.end - remote.start))
        guard overlap / duration >= 0.8, abs(mic.start - remote.start) <= 1.5 else { return false }
        let a = words(mic.text), b = words(remote.text)
        guard min(a.count, b.count) >= 6, max(a.count, b.count) <= 256, Double(min(a.count, b.count)) / Double(max(a.count, b.count)) >= 0.8 else { return false }
        let critical: (String) -> Bool = { $0.contains(where: \.isNumber) || ["not", "no", "never", "without", "cannot", "can't", "didn't", "don't", "isn't", "wasn't", "won't"].contains($0) }
        guard a.filter(critical) == b.filter(critical) else { return false }
        // Ordered edit distance, not bag-of-words matching, preserves distinct claims.
        var row = Array(0...b.count)
        for (i, word) in a.enumerated() {
            var next = [i + 1] + Array(repeating: 0, count: b.count)
            for j in b.indices { next[j + 1] = min(next[j] + 1, row[j + 1] + 1, row[j] + (word == b[j] ? 0 : 1)) }
            row = next
        }
        return Double(row[b.count]) / Double(max(a.count, b.count)) <= 0.15
    }
    static func reconcile(_ call: inout CallRecord, session: UUID, around time: Double) {
        let indices = call.transcript.indices.filter { call.transcript[$0].sessionID == session && abs(call.transcript[$0].start - time) < 20 }
        let remote = indices.map { call.transcript[$0] }.filter { $0.source == "meeting" && $0.isFinal }
        for index in indices where call.transcript[index].source == "microphone" {
            call.transcript[index].echoOf = remote.first { isEcho(call.transcript[index], of: $0) }?.id
        }
    }
    static func text(_ segments: [TranscriptSegment], includeIDs: Bool = false) -> String {
        segments.map { segment in
            let uncertainty = (segment.confidence ?? 1) < 0.65 ? " [uncertain wording]" : ""
            return "\(includeIDs ? "[segment \(segment.id)] " : "")[\(segment.timestamp)] \(segment.speaker)\(segment.isFinal ? "" : " [partial]")\(uncertainty): \(segment.text)"
        }.joined(separator: "\n")
    }
}

/// Use exact vocabulary from the call, without inventing phonetic corrections.
enum CallVocabulary {
    static func extract(_ text: String) -> [String] {
        let pattern = #"\b(?:[A-Z][a-z]+(?:[ -][A-Z][a-z]+){0,3}|[A-Z][A-Z0-9&]{1,10})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = text as NSString
        var seen = Set<String>()
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap {
            let term = source.substring(with: $0.range)
            guard term.count >= 3, seen.insert(term.lowercased()).inserted else { return nil }
            return term
        }.prefix(150).map { $0 }
    }
}

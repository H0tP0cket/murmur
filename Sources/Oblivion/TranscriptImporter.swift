import Foundation

enum TranscriptImporter {
    static func parse(_ text: String, session: UUID) throws -> [TranscriptSegment] {
        guard text.utf8.count <= 20 * 1024 * 1024 else { throw OblivionError.message("Choose a transcript smaller than 20 MB.") }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var output: [TranscriptSegment] = [], index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines); index += 1
            if line.isEmpty || line.hasPrefix("WEBVTT") || line.allSatisfy(\.isNumber) { continue }
            if line.contains("-->") {
                let times = line.components(separatedBy: "-->")
                guard let start = seconds(times[0]), let end = seconds(times[1].split(separator: " ").first.map(String.init) ?? times[1]) else { continue }
                var body: [String] = []
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).isEmpty { body.append(lines[index]); index += 1 }
                let (speaker, content) = speakerAndText(body.joined(separator: " "))
                if !content.isEmpty { output.append(TranscriptSegment(sessionID: session, source: "import", speaker: speaker, start: start, end: max(start,end), original: content)) }
                continue
            }
            if let match = groups(#"^\[?((?:\d{1,3}:)?\d{1,2}:\d{2}(?:[.,]\d{1,3})?)\]?\s+(.+)$"#, in: line), let time = seconds(match[0]) {
                let (speaker, content) = speakerAndText(match[1])
                output.append(TranscriptSegment(sessionID: session, source: "import", speaker: speaker, start: time, end: time, original: content))
            } else {
                let (speaker, content) = speakerAndText(line)
                output.append(TranscriptSegment(sessionID: session, source: "import-untimed", speaker: speaker, start: 0, end: 0, original: content))
            }
        }
        guard !output.isEmpty else { throw OblivionError.message("This file doesn’t contain readable transcript passages.") }
        return output
    }

    private static func seconds(_ value: String) -> Double? {
        let fields = value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").components(separatedBy: ":")
        guard (2...3).contains(fields.count), fields.allSatisfy({ Double($0) != nil }) else { return nil }
        return fields.reduce(0) { $0 * 60 + (Double($1) ?? 0) }
    }
    private static func speakerAndText(_ value: String) -> (String,String) {
        if let parts = groups(#"^<v\s+([^>]+)>(.*?)(?:</v>)?$"#, in: value) { return (parts[0], stripTags(parts[1])) }
        if let parts = groups(#"^([^:\n]{1,80}):\s*(.+)$"#, in: value) { return (parts[0], stripTags(parts[1])) }
        return ("Imported",stripTags(value))
    }
    private static func stripTags(_ value: String) -> String {
        value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func groups(_ pattern: String, in value: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { Range(match.range(at:$0), in:value).map { String(value[$0]) } }
    }
}

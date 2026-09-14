import Foundation

/// Coherent Markdown chunks, independent of network packet/token frequency.
/// Keep one latest snapshot and one published snapshot, never a delta queue.
struct ChatStreamBuffer {
    private(set) var latest = ""
    private(set) var published = ""
    private var lastPublication: TimeInterval?

    mutating func receive(_ text: String, at time: TimeInterval) {
        latest = text
        if lastPublication == nil { lastPublication = time }
    }

    mutating func takeReady(at time: TimeInterval) -> String? {
        guard latest != published, time - (lastPublication ?? time) >= 0.7 else { return nil }
        let boundary = Self.completedBlockEnd(in: latest)
        var candidate = String(latest[..<boundary]).trimmingCharacters(in: .newlines)
        // Very long prose can reveal a complete sentence after a short wait.
        // Table rows and open code fences stay buffered as a unit.
        let tail = String(latest[boundary...])
        if time - (lastPublication ?? time) >= 2,
           !tail.contains("|"), !tail.contains("```"), !tail.contains("~~~"),
           let range = tail.range(of: #"[.!?][”\"']?(?:\s|$)"#, options: .regularExpression, range: nil, locale: nil) {
            // Prefer the last complete sentence, not the first sentence forever.
            let matches = tail.ranges(of: #"[.!?][”\"']?(?:\s|$)"#)
            let end = matches.last?.upperBound ?? range.upperBound
            let prose = String(tail[..<end])
            if prose.count >= 120, Self.balancedInline(prose) {
                candidate = String(latest[..<boundary]) + prose
            }
        }
        guard !candidate.isEmpty, candidate != published,
              candidate.count > published.count || !latest.hasPrefix(published) else { return nil }
        published = candidate; lastPublication = time
        return candidate
    }

    mutating func finish(_ final: String? = nil) -> String? {
        if let final { latest = final }
        guard latest != published else { return nil }
        published = latest
        return latest
    }

    private static func balancedInline(_ value: String) -> Bool {
        // Don't flash raw delimiters while a link/emphasis/code span is unfinished.
        ["*", "_", "`", "~"].allSatisfy { token in value.filter { String($0) == token }.count.isMultiple(of: 2) }
            && value.filter { $0 == "[" }.count == value.filter { $0 == "]" }.count
            && value.filter { $0 == "(" }.count == value.filter { $0 == ")" }.count
    }

    private static func completedBlockEnd(in text: String) -> String.Index {
        var boundary = text.startIndex, start = text.startIndex
        var fence: (Character, Int)?
        while let newline = text[start...].firstIndex(of: "\n") {
            let line = text[start..<newline].trimmingCharacters(in: .whitespaces)
            if let marker = line.first, marker == "`" || marker == "~" {
                let count = line.prefix { $0 == marker }.count
                if count >= 3 {
                    if let open = fence {
                        if marker == open.0, count >= open.1, line.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
                    } else { fence = (marker, count) }
                }
            }
            let next = text.index(after: newline)
            if fence == nil, line.isEmpty { boundary = next }
            start = next
        }
        return boundary
    }
}

private extension String {
    func ranges(of pattern: String) -> [Range<String.Index>] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return expression.matches(in: self, range: NSRange(startIndex..., in: self)).compactMap { Range($0.range, in: self) }
    }
}

@MainActor final class ChatResponseStream {
    private var buffer = ChatStreamBuffer()
    private var task: Task<Void, Never>?
    private var stopped = false
    private let publish: (String) -> Void
    init(publish: @escaping (String) -> Void) { self.publish = publish }

    func receive(_ text: String) {
        guard !stopped else { return }
        buffer.receive(text, at: ProcessInfo.processInfo.systemUptime)
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
                guard let self, !self.stopped else { return }
                if let text = self.buffer.takeReady(at: ProcessInfo.processInfo.systemUptime) { self.publish(text) }
            }
        }
    }
    func finish(_ final: String? = nil) {
        guard !stopped else { return }
        if let text = buffer.finish(final) { publish(text) }
        stop()
    }
    func stop() { stopped = true; task?.cancel(); task = nil }
}

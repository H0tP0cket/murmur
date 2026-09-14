import Foundation
import CryptoKit

enum NotesGeneration {
    static func hasMaterial(_ call: CallRecord) -> Bool {
        !call.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !call.transcript.isEmpty
            || call.messages.contains { $0.role == "user" } || !call.attachments.isEmpty
    }

    static func signature(_ call: CallRecord) -> String {
        // Exclude generated output so opening unchanged notes never triggers a
        // second request. Include corrections and prep, not just passage counts.
        var source = call
        source.generatedNotes = ""
        return SHA256.hash(data: Data((source.preparationText + "\n" + source.transcriptText).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    static func prompt(_ call: CallRecord) -> String {
        let guided = !call.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let direction = guided
            ? "Use the user's written notes as your outline and focus. Organize their points and expand shorthand only with supported details from the conversation. Retain their priorities. Put important additional meeting details in a short Additional context section."
            : "Create concise default meeting notes covering Key findings, Decisions, People and systems, Open questions, and Follow-ups. Omit empty sections."
        return """
        \(direction)
        Ground every item in the supplied material. Distinguish confirmed conversation facts, the user's notes, preparation, and unresolved questions. If there is no transcript, describe preparation and written notes without claiming a meeting occurred. Do not invent decisions, results, owners, deadlines, or what someone said. Preserve corrections and avoid duplicate items. Return only the organized AI notes. Never rewrite the user's original notepad. Do not use tools.

        EXISTING AI NOTES
        \(call.generatedNotes)

        \(call.preparationText)

        TRANSCRIPT
        \(call.transcriptText)
        """
    }
}

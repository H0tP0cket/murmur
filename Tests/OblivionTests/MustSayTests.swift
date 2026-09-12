import Foundation
import Testing
@testable import Oblivion

@Test func mustSayPreservesLegacyItemsAndExactWordingForEveryRecommendationKind() throws {
    let oldData = Data(#"{"id":"9552B85A-9986-48DB-9726-86FC98F81358","title":"Opening introduction","body":"Hi, I'm Alex.\n\nI study claims workflows — not model costs.","cues":"","approved":true}"#.utf8)
    let item = try JSONDecoder().decode(PreparedStory.self, from: oldData)
    #expect(item.trigger == "Opening introduction")
    #expect(try JSONDecoder().decode(PreparedStory.self, from: JSONEncoder().encode(item)) == item)
    for kind in ["INTRO", "ASK", "FOLLOW UP", "ANSWER"] {
        let result = Recommendation(kind: kind, coaching: "Keep it natural.", answer: "A model paraphrase", storyID: item.id.uuidString.lowercased()).resolvingMustSay(from: [item])
        #expect(result.answer == item.body)
        #expect(result.kind == kind)
    }
    var draft = item; draft.approved = false
    #expect(Recommendation(kind: "ANSWER", coaching: "", answer: "Fallback", storyID: item.id.uuidString).resolvingMustSay(from: [draft]).storyID == nil)
}

@Test @MainActor func noteEditsReachContextImmediatelyAndFlushToTheRightCall() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("oblivion-notes-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let state = AppState(root: root, connect: false)
    let first = state.newCall(), second = state.newCall()
    state.editNotes(callID: first, text: "First draft")
    state.editNotes(callID: first, text: "Budget is $72,000.\nAsk about pilot ownership.")
    state.editNotes(callID: second, text: "Other call's notes")
    #expect(state.calls.first { $0.id == first }!.preparationText.contains("Budget is $72,000.\nAsk about pilot ownership."))
    #expect(!state.selected!.preparationText.contains("$72,000"))
    state.editNotes(callID: first, text: "AI draft, edited by user", generated: true)
    state.flushNoteEdits()
    let restored = try state.library.load()
    #expect(restored.first { $0.id == first }?.notes == "Budget is $72,000.\nAsk about pilot ownership.")
    #expect(restored.first { $0.id == first }?.generatedNotesEdited == true)
    #expect(restored.first { $0.id == second }?.notes == "Other call's notes")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["OBLIVION_MUST_SAY_TEST"] == "1"))
@MainActor func realCodexMatchesMustSaySituationsAndParaphrases() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("oblivion-must-say-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let service = CodexService()
    defer { service.disconnect() }
    try await service.connect()
    let intro = PreparedStory(title: "", body: "Thanks for making time, Morgan. I'm Alex, researching the work that remains after claims automation.", cues: "At the beginning of the call, introduce myself.")
    let question = PreparedStory(title: "", body: "Who takes responsibility for fixing a claim after the automation gets it wrong?", cues: "They mention manual cleanup or rework after an automated decision.")
    let pitch = PreparedStory(title: "", body: "My proposal is a two-week pilot measuring review time and rework together.", cues: "They ask what I would propose as a next step.")
    var call = CallRecord(); call.stories = [intro, question, pitch]
    let cases: [(String, PreparedStory, String)] = [
        ("This is the start of a new call session. Nobody has spoken yet. Prepare the opening introduction now.", intro, "INTRO"),
        ("Morgan just finished saying: We spend half the day undoing mistakes made by the automated pipeline. The user is listening. Give the next recommendation.", question, "ASK"),
        ("Morgan asks: Okay, where would you take this from here? The user is listening. Give the next recommendation.", pitch, "ANSWER")
    ]
    for (situation, item, _) in cases {
        let thread = try await service.thread(cwd: root, live: true, ephemeral: true)
        let response = try await service.run(threadID: thread, text: call.preparationText + "\n\nLIVE SITUATION:\n" + situation, live: true, schema: Recommendation.schema)
        let result = try JSONDecoder().decode(Recommendation.self, from: Data(response.utf8))
        #expect(result.storyID?.lowercased() == item.id.uuidString.lowercased())
        #expect(result.resolvingMustSay(from: call.stories).answer == item.body)
    }
}

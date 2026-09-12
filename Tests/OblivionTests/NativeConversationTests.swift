import AppKit
import Testing
@testable import Oblivion

@Test @MainActor func nativeChatAppliesStreamingCorrectionsWithoutDuplicatingHistory() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("oblivion-render-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let library = try LibraryStore(root: root)
    let text = ChatDocumentView(frame: NSRect(x: 0, y: 0, width: 760, height: 600))
    let coordinator = NativeConversationView.Coordinator()
    coordinator.textView = text
    var messages = [ChatMessage(role: "user", text: "A question"), ChatMessage(role: "assistant", text: "We do automate", pending: true)]
    var view = NativeConversationView(callID: UUID(), messages: messages, library: library, busy: true, status: "Thinking…", save: { _ in })
    coordinator.update(view)
    coordinator.following = false
    messages[1].text = "We do **not** automate.\n\nKeep this second paragraph."
    messages[1].pending = false
    view.messages = messages; view.busy = false
    coordinator.update(view)
    #expect(text.string.components(separatedBy: "A question").count == 2)
    #expect(text.string.contains("We do not automate.\n\nKeep this second paragraph."))
    #expect(!text.string.contains("Thinking…"))
    #expect(!text.string.contains("We do automate"))
    #expect(!coordinator.following)
    view.messages.append(ChatMessage(role: "user", text: "A follow-up"))
    coordinator.update(view)
    #expect(text.string.components(separatedBy: "Keep this second paragraph.").count == 2)
    #expect(text.string.contains("A follow-up"))
    #expect(coordinator.following)
    view.callID = UUID(); view.messages = [ChatMessage(role: "assistant", text: "A separate call")]
    coordinator.update(view)
    #expect(text.string == "A separate call\n\n")
}

@Test @MainActor func nativeChatKeepsSelectionOnUnrelatedUpdatesAndRoutesSavedAnswers() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("oblivion-selection-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let library = try LibraryStore(root: root)
    let text = ChatDocumentView(frame: NSRect(x: 0, y: 0, width: 760, height: 600))
    let coordinator = NativeConversationView.Coordinator()
    coordinator.textView = text
    let answer = ChatMessage(role: "assistant", text: "First paragraph.\n\n**Second paragraph.**")
    var saved = ""
    var view = NativeConversationView(callID: UUID(), messages: [ChatMessage(role: "user", text: "Prepare a story"), answer], library: library, busy: false, status: "", save: { saved = $0 })
    coordinator.update(view)
    let range = (text.string as NSString).range(of: "First paragraph.\n\nSecond paragraph.")
    text.setSelectedRange(range)
    view.status = "An unrelated status while not busy"
    coordinator.update(view)
    #expect(text.selectedRange() == range)
    #expect((text.string as NSString).substring(with: range) == "First paragraph.\n\nSecond paragraph.")
    #expect(coordinator.textView(text, clickedOnLink: URL(string: "oblivion://save/\(answer.id.uuidString)")!, at: 0))
    #expect(saved == answer.text)
}

@Test @MainActor func nativeChatUsesClickableButtonsOnlyForVisibleMessages() throws {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("oblivion-buttons-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let library = try LibraryStore(root: root)
    let scroll = ChatScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    let text = ChatDocumentView(frame: NSRect(x: 0, y: 0, width: 580, height: 400))
    text.isEditable = false; text.isVerticallyResizable = true
    text.textContainer?.widthTracksTextView = true
    scroll.documentView = text
    let coordinator = NativeConversationView.Coordinator(); coordinator.textView = text
    var saved = ""
    let messages = (0..<120).map { ChatMessage(role: "assistant", text: "Response \($0)\n\nA second paragraph of useful context.") }
    let view = NativeConversationView(callID: UUID(), messages: messages, library: library, busy: false, status: "", save: { saved = $0 })
    text.onAction = { url in _ = coordinator.textView(text, clickedOnLink: url, at: 0) }
    coordinator.update(view)
    text.layoutManager?.ensureLayout(for: text.textContainer!)
    text.sizeToFit()
    text.layoutActionButtons()
    #expect(!text.actionButtons.isEmpty)
    #expect(text.actionButtons.count < 20)
    #expect(text.accessibilityChildren()?.contains { $0 is ChatActionButton } == true)
    let oldURLs = Set(text.actionButtons.keys)
    let save = try #require(text.actionButtons.first { $0.key.host == "save" })
    save.value.performClick(nil)
    #expect(saved == messages.first { $0.id.uuidString == save.key.lastPathComponent }?.text)
    text.scrollRangeToVisible(NSRange(location: text.string.utf16.count, length: 0))
    text.layoutActionButtons()
    #expect(text.actionButtons.count < 20)
    #expect(Set(text.actionButtons.keys).isDisjoint(with: oldURLs))
}

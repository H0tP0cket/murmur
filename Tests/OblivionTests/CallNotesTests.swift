import AppKit
import Testing
@testable import Oblivion

@Test @MainActor func callNotesReopenMainChatWithoutHidingGuidanceOrEndingTheCall() throws {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("oblivion-call-notes-\(UUID())")
    let state = AppState(root: root, connect: false)
    let call = state.newCall(), other = state.newCall()
    state.activeCallID = call
    let recommendation = state.recommendation
    let main = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    main.isReleasedWhenClosed = false
    state.windows.mainWindow = main
    defer {
        state.windows.returnToChat()
        for window in NSApp.windows where window.title == "murmur · Call" {
            window.contentView = nil; window.close()
        }
        main.close()
        try? FileManager.default.removeItem(at: root)
    }

    state.windows.showHUD()
    let hud = try #require(NSApp.windows.first { $0.title == "murmur · Call" })
    #expect(hud.isVisible && !main.isVisible)
    #expect(state.selectedID == other)
    state.windows.showCallNotes()
    #expect(hud.isVisible && main.isVisible)
    #expect(state.selectedID == call && state.detail == .notes)
    #expect(state.activeCallID == call && state.recommendation == recommendation)
    #expect(!NSApp.windows.contains { $0.title == "murmur · Notes" })

    state.editNotes(callID: call, text: "Ask who owns the pilot.\nKeep this exact note.")
    state.windows.toggleHUD()
    #expect(!hud.isVisible && main.isVisible)
    #expect(try state.library.load().first { $0.id == call }?.notes == "Ask who owns the pilot.\nKeep this exact note.")
    #expect(try state.library.load().first { $0.id == other }?.notes == "")
    state.windows.toggleHUD()
    #expect(hud.isVisible && main.isVisible)
    state.windows.ask()
    #expect(hud.isVisible && main.isVisible && state.showDirectQuestion)
    #expect(state.activeCallID == call && state.recommendation == recommendation)

    state.windows.showHUD() // Explicit Pop out still gives the overlay alone.
    #expect(hud.isVisible && !main.isVisible)
    state.windows.showCallNotes()
    #expect(hud.isVisible && main.isVisible)
    state.editNotes(callID: call, text: "The last keystroke is saved on return.")
    state.windows.returnToChat()
    #expect(!hud.isVisible && main.isVisible && !state.hudVisible)
    #expect(state.activeCallID == call)
    #expect(state.selectedID == call && state.detail == .notes)
    #expect(try state.library.load().first { $0.id == call }?.notes == "The last keystroke is saved on return.")
}

import AppKit
import Testing
@testable import Oblivion

@Test @MainActor func floatingNotesSaveAndFollowTheCallWindowsWithoutEndingTheCall() throws {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("oblivion-call-notes-\(UUID())")
    let state = AppState(root: root, connect: false)
    let call = state.newCall(), other = state.newCall()
    state.activeCallID = call
    let recommendation = state.recommendation
    defer {
        state.windows.returnToChat()
        for window in NSApp.windows where window.title == "Oblivion · Notes" || window.title == "Oblivion · Call" {
            window.contentView = nil; window.close()
        }
        try? FileManager.default.removeItem(at: root)
    }

    state.windows.showHUD()
    state.windows.toggleCallNotes()
    let hud = try #require(NSApp.windows.first { $0.title == "Oblivion · Call" })
    let notes = try #require(NSApp.windows.first { $0.title == "Oblivion · Notes" })
    #expect(hud.isVisible && notes.isVisible)
    #expect(state.selectedID == other)
    #expect(state.activeCallID == call)

    state.editNotes(callID: call, text: "Ask who owns the pilot.\nKeep this exact note.")
    state.windows.closeCallNotes()
    #expect(!notes.isVisible && hud.isVisible)
    #expect(!state.showCallNotes)
    #expect(try state.library.load().first { $0.id == call }?.notes == "Ask who owns the pilot.\nKeep this exact note.")
    #expect(try state.library.load().first { $0.id == other }?.notes == "")

    state.windows.toggleCallNotes()
    state.windows.toggleHUD()
    #expect(!hud.isVisible && !notes.isVisible)
    #expect(state.showCallNotes) // Restore the notepad together with the HUD.
    state.windows.toggleHUD()
    #expect(hud.isVisible && notes.isVisible)
    #expect(state.activeCallID == call && state.recommendation == recommendation)

    state.editNotes(callID: call, text: "The last keystroke is saved on return.")
    state.windows.returnToChat()
    #expect(!hud.isVisible && !notes.isVisible)
    #expect(!state.showCallNotes && !state.hudVisible)
    #expect(state.activeCallID == call)
    #expect(state.selectedID == call && state.detail == .notes)
    #expect(try state.library.load().first { $0.id == call }?.notes == "The last keystroke is saved on return.")
}

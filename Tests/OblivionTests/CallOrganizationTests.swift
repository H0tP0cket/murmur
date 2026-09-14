import Foundation
import Testing
@testable import Oblivion

@Test @MainActor func foldersKeepNumberingAndCallsAcrossRenameMoveRemovalAndReload() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-folders-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let state = AppState(root: root, connect: false)
    let folder = try #require(state.createFolder(name: "  Example Labs  "))
    let first = state.newCall(), second = state.newCall()
    #expect(state.calls.first { $0.id == first }?.title == "Call 1")
    #expect(state.calls.first { $0.id == second }?.title == "Call 2")
    #expect(state.selected?.folderID == folder)
    state.renameCall(first, title: "Technical discovery")
    state.renameFolder(folder, name: "Example")
    let restored = AppState(root: root, connect: false)
    #expect(restored.selectedID == nil)
    restored.openFolder(folder)
    let third = restored.newCall()
    #expect(restored.selected?.title == "Call 3")
    #expect(restored.selectedFolder?.name == "Example")
    #expect(restored.calls.first { $0.id == first }?.title == "Technical discovery")
    restored.moveCall(third, to: nil)
    #expect(restored.calls.first { $0.id == third }?.folderID == nil)
    restored.removeFolder(folder)
    #expect(restored.calls.count == 3 && restored.calls.allSatisfy { $0.folderID == nil })
    #expect(try restored.library.load().count == 3)
    #expect(try restored.library.loadOrganization().folders.isEmpty)
}

@Test @MainActor func calendarPreparationIsExplicitDeduplicatedAndKeepsDistinctOccurrences() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-calendar-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let state = AppState(root: root, connect: false)
    let folder = try #require(state.createFolder(name: "Avery"))
    let event = CalendarMeeting(id: "event/1000", title: "Discovery with Avery", start: Date(timeIntervalSince1970: 1000), end: Date(timeIntervalSince1970: 2800), calendarName: "Work", participants: ["Avery"], location: "Google Meet", notes: "Discuss the pilot", meetingURL: nil)
    #expect(state.calls.isEmpty)
    let id = state.prepareEvent(event, folderID: folder)
    #expect(state.selected?.title == "Call 1")
    #expect(state.selected?.preparationText.contains("Discuss the pilot") == true)
    #expect(state.selected?.messages.isEmpty == true)
    #expect(state.prepareEvent(event) == id && state.calls.count == 1)
    var recurring = event; recurring.id = "event/2000"
    #expect(state.prepareEvent(recurring, folderID: folder) != id)
    #expect(state.selected?.title == "Call 2")
    let persisted = try #require(try state.library.load().first { $0.id == id })
    #expect(persisted.folderID == folder && persisted.calendarEventID == event.id)
    #expect(persisted.calendarContext == event.preparationContext)
}

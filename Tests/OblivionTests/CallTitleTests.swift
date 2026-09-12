import Foundation
import Testing
@testable import Oblivion

@Test @MainActor func automaticTitlesUsePersonAndCompanyAndPersist() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("oblivion-title-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let state = AppState(root: root, connect: false)
    let id = state.newCall()
    #expect(state.selected?.title == "New call")
    state.applyAutomaticTitle(CallTitleSuggestion(person: "  Morgan Chen  ", companyOrRole: "Acme\nInsurance"), callID: id)
    #expect(state.selected?.title == "Morgan Chen · Acme Insurance")
    let restored = AppState(root: root, connect: false)
    #expect(restored.calls.first(where: { $0.id == id })?.title == "Morgan Chen · Acme Insurance")
    #expect(restored.calls.first(where: { $0.id == id })?.automaticTitlePending == false)
}

@Test @MainActor func uncertainTitlesWaitAndManualNamesWinOverLateResults() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("oblivion-title-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let state = AppState(root: root, connect: false)
    let id = state.newCall()
    state.applyAutomaticTitle(CallTitleSuggestion(person: nil, companyOrRole: "Acme"), callID: id)
    #expect(state.selected?.title == "New call")
    #expect(state.selected?.automaticTitlePending == true)
    state.renameCall(id, title: "My custom title")
    state.applyAutomaticTitle(CallTitleSuggestion(person: "Morgan", companyOrRole: "Claims lead"), callID: id)
    #expect(state.selected?.title == "My custom title")
    #expect(CallTitleSuggestion(person: "Morgan", companyOrRole: nil).title == "Morgan")
    var legacy = CallRecord(title: "Existing name")
    #expect(legacy.automaticTitlePending == nil)
    try state.library.save(legacy)
    legacy = try #require(state.library.load().first(where: { $0.id == legacy.id }))
    #expect(legacy.title == "Existing name")
}

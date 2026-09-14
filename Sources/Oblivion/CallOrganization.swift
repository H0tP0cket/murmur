import Foundation

struct CallFolder: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var nextCallNumber = 1
}

struct CallOrganization: Codable, Equatable {
    var folders: [CallFolder] = []
    var nextCallNumber = 1
}

extension LibraryStore {
    func loadOrganization() throws -> CallOrganization {
        let url = root.appendingPathComponent("organization.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return CallOrganization() }
        return try JSONDecoder().decode(CallOrganization.self, from: Data(contentsOf: url))
    }
    func saveOrganization(_ value: CallOrganization) throws {
        try JSONEncoder().encode(value).write(to: root.appendingPathComponent("organization.json"), options: .atomic)
    }
}

extension AppState {
    var folders: [CallFolder] { organization.folders }
    var selectedFolder: CallFolder? { folders.first { $0.id == selectedFolderID } }
    func showHome() { selectedID = nil; selectedFolderID = nil; detail = nil; showArchived = false }
    func openFolder(_ id: UUID) { selectedID = nil; selectedFolderID = id; detail = nil; showArchived = false }
    @discardableResult func createFolder(name: String) -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let folder = CallFolder(name: String(name.prefix(120)))
        organization.folders.append(folder); saveOrganization(); openFolder(folder.id)
        return folder.id
    }
    func renameFolder(_ id: UUID, name: String) {
        guard let index = organization.folders.firstIndex(where: { $0.id == id }), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        organization.folders[index].name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)); saveOrganization()
    }
    func removeFolder(_ id: UUID) {
        // Removing an organizational folder always keeps its calls.
        for call in calls where call.folderID == id { modify(call.id) { $0.folderID = nil } }
        organization.folders.removeAll { $0.id == id }; saveOrganization()
        if selectedFolderID == id { selectedFolderID = nil }
    }
    func moveCall(_ id: UUID, to folderID: UUID?) {
        guard folderID == nil || folders.contains(where: { $0.id == folderID }) else { return }
        modify(id) { $0.folderID = folderID }
    }
    func saveOrganization() {
        do { try library.saveOrganization(organization) } catch { self.error = "Couldn’t save folders. \(error.localizedDescription)" }
    }
    func nextCallTitle(in folderID: UUID?) -> String {
        let number: Int
        if let index = organization.folders.firstIndex(where: { $0.id == folderID }) {
            number = organization.folders[index].nextCallNumber
            organization.folders[index].nextCallNumber += 1
        } else { number = organization.nextCallNumber; organization.nextCallNumber += 1 }
        saveOrganization()
        return "Call \(number)"
    }
    @discardableResult func prepareEvent(_ event: CalendarMeeting, folderID: UUID? = nil) -> UUID {
        if let call = calls.first(where: { $0.calendarEventID == event.id }) { selectedID = call.id; selectedFolderID = call.folderID; return call.id }
        selectedFolderID = folderID
        let id = newCall()
        modify(id) { $0.calendarEventID = event.id; $0.calendarContext = event.preparationContext }
        return id
    }
}

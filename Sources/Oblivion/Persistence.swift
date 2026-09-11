import Foundation
import PDFKit

@MainActor
final class LibraryStore {
    let root: URL
    private(set) var loadWarnings: [String] = []
    private let encoder: JSONEncoder = {
        let result = JSONEncoder()
        result.outputFormatting = [.prettyPrinted, .sortedKeys]
        result.dateEncodingStrategy = .iso8601
        return result
    }()
    private let decoder: JSONDecoder = {
        let result = JSONDecoder(); result.dateDecodingStrategy = .iso8601; return result
    }()

    init(root: URL? = nil) throws {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Oblivion", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root.appendingPathComponent("Calls"), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    func directory(_ id: UUID) -> URL { root.appendingPathComponent("Calls/\(id.uuidString)", isDirectory: true) }

    func load() throws -> [CallRecord] {
        loadWarnings = []
        let folders = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Calls"), includingPropertiesForKeys: nil)
        var records: [CallRecord] = []
        for folder in folders {
            let url = folder.appendingPathComponent("call.json")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do { records.append(try decoder.decode(CallRecord.self, from: Data(contentsOf: url))) }
            catch { loadWarnings.append("Couldn’t read \(folder.lastPathComponent). Your saved file has been left intact. \(error.localizedDescription)") }
        }
        return records.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ record: CallRecord) throws {
        let folder = directory(record.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try encoder.encode(record).write(to: folder.appendingPathComponent("call.json"), options: .atomic)
        try record.preparationText.write(to: folder.appendingPathComponent("preparation.md"), atomically: true, encoding: .utf8)
        try record.transcriptText.write(to: folder.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)
    }

    func importFile(_ url: URL, callID: UUID) throws -> Attachment {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 30 * 1024 * 1024 else { throw OblivionError.message("Choose a file smaller than 30 MB.") }
        let data = try Data(contentsOf: url)
        let text: String
        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(data: data) else { throw OblivionError.message("This PDF couldn’t be opened.") }
            text = (0..<document.pageCount).compactMap { index in document.page(at: index)?.string.map { "[Page \(index + 1)]\n\($0)" } }.joined(separator: "\n\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OblivionError.message("This PDF has no selectable text. Add a text version or paste the relevant material.") }
        } else {
            guard let decoded = String(data: data, encoding: .utf8) else { throw OblivionError.message("Use a PDF or a UTF-8 text/Markdown file.") }
            text = decoded
        }
        let name = "\(UUID().uuidString)-\(url.lastPathComponent)"
        let folder = directory(callID).appendingPathComponent("attachments")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        try text.write(to: folder.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
        return Attachment(name: url.lastPathComponent, relativePath: "attachments/\(name)", text: text)
    }

    func export(_ record: CallRecord, to url: URL) throws {
        let text = "# \(record.title)\n\n## Preparation\n\n\(record.preparationText)\n\n## Notes\n\n\(record.notes)\n\n\(record.generatedNotes)\n\n## Transcript\n\n\(record.transcriptText)"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

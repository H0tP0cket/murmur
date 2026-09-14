import Foundation
import PDFKit
import ImageIO
import UniformTypeIdentifiers

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
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: self.root.path)
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
        let conversation = record.messages.map { message in
            let images = (message.images ?? []).map { "![\($0.name)](\($0.imageRelativePath ?? $0.relativePath))" }.joined(separator: "\n")
            return "## \(message.role.uppercased())\n\n\(message.text)\n\(images)"
        }.joined(separator: "\n\n")
        try conversation.write(to: folder.appendingPathComponent("conversation.md"), atomically: true, encoding: .utf8)
        try record.transcriptText.write(to: folder.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)
    }

    func importFile(_ url: URL, callID: UUID) throws -> Attachment {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 30 * 1024 * 1024 else { throw OblivionError.message("Choose a file smaller than 30 MB.") }
        let data = try Data(contentsOf: url)
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true {
            return try importImage(data, name: url.lastPathComponent, callID: callID)
        }
        let text: String
        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(data: data) else { throw OblivionError.message("This PDF couldn’t be opened.") }
            text = (0..<document.pageCount).compactMap { index in document.page(at: index)?.string.map { "[Page \(index + 1)]\n\($0)" } }.joined(separator: "\n\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OblivionError.message("This PDF has no selectable text. Add a text version or paste the relevant material.") }
        } else {
            guard let decoded = String(data: data, encoding: .utf8) else { throw OblivionError.message("Use an image, PDF, or UTF-8 text/Markdown file.") }
            text = decoded
        }
        let name = "\(UUID().uuidString)-\(url.lastPathComponent)"
        let folder = directory(callID).appendingPathComponent("attachments")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        try text.write(to: folder.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
        return Attachment(name: url.lastPathComponent, relativePath: "attachments/\(name)", text: text)
    }

    func importImage(_ data: Data, name: String, callID: UUID) throws -> Attachment {
        guard data.count <= 30 * 1024 * 1024 else { throw OblivionError.message("Choose an image smaller than 30 MB.") }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, Double(width) * Double(height) <= 100_000_000 else {
            throw OblivionError.message("This image couldn’t be opened. Use a valid image up to 100 megapixels.")
        }
        // ImageIO applies orientation and bounds decoded size. PNG also makes
        // HEIC, TIFF, WebP, and the first frame of GIF usable by Codex.
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096
        ] as CFDictionary) else { throw OblivionError.message("This image format couldn’t be decoded. Try PNG or JPEG.") }
        let normalized = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(normalized, UTType.png.identifier as CFString, 1, nil) else {
            throw OblivionError.message("Couldn’t prepare this image.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw OblivionError.message("Couldn’t prepare this image.") }
        let id = UUID()
        var safeName = URL(fileURLWithPath: name).lastPathComponent
        if URL(fileURLWithPath: safeName).pathExtension.isEmpty,
           let type = CGImageSourceGetType(source), let ext = UTType(type as String)?.preferredFilenameExtension { safeName += "." + ext }
        let relative = "attachments/\(id.uuidString)-\(safeName)"
        let imagePath = "attachments/\(id.uuidString)-vision.png"
        let folder = directory(callID).appendingPathComponent("attachments")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: directory(callID).appendingPathComponent(relative), options: .atomic)
        try (normalized as Data).write(to: directory(callID).appendingPathComponent(imagePath), options: .atomic)
        return Attachment(id: id, name: safeName, relativePath: relative,
                          text: "Image attachment (\(width) × \(height)); inspect the image for visual details. Multi-frame images use their first frame.",
                          imageRelativePath: imagePath)
    }

    func imageURL(_ attachment: Attachment, callID: UUID) -> URL? {
        guard let path = attachment.imageRelativePath else { return nil }
        let folder = directory(callID).appendingPathComponent("attachments").resolvingSymlinksInPath()
        let url = directory(callID).appendingPathComponent(path).resolvingSymlinksInPath()
        guard url.path.hasPrefix(folder.path + "/") else { return nil }
        return url
    }

    func imageURLs(for call: CallRecord) throws -> [URL] {
        try call.attachments.filter(\.isImage).map { attachment in
            guard let url = imageURL(attachment, callID: call.id), FileManager.default.isReadableFile(atPath: url.path) else {
                throw OblivionError.message("The image ‘\(attachment.name)’ is missing. Remove it from context and attach it again.")
            }
            return url
        }
    }

    func export(_ record: CallRecord, to url: URL) throws {
        let text = "# \(record.title)\n\n## Preparation\n\n\(record.preparationText)\n\n## Notes\n\n\(record.notes)\n\n\(record.generatedNotes)\n\n## Transcript\n\n\(record.transcriptText)"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

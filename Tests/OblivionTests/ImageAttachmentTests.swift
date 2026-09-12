import AppKit
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import Oblivion

private func jpegFixture() throws -> Data {
    let context = try #require(CGContext(data: nil, width: 640, height: 320, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 640, height: 320))
    context.setFillColor(NSColor.black.cgColor); context.fillEllipse(in: CGRect(x: 30, y: 30, width: 90, height: 90))
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(context.makeImage()), [kCGImagePropertyOrientation: 6] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

@Test @MainActor func imagesKeepOriginalsNormalizeOrientationAndSurviveRestart() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("oblivion-images-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let library = try LibraryStore(root: root)
    let data = try jpegFixture()
    let input = root.appendingPathComponent("photo.jpg"); try data.write(to: input)
    var call = CallRecord()
    let image = try library.importFile(input, callID: call.id)
    #expect(image.isImage)
    #expect(try Data(contentsOf: library.directory(call.id).appendingPathComponent(image.relativePath)) == data)
    let url = try #require(library.imageURL(image, callID: call.id))
    let normalized = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(normalized, 0, nil) as? [CFString: Any])
    #expect(properties[kCGImagePropertyPixelWidth] as? Int == 320)
    #expect(properties[kCGImagePropertyPixelHeight] as? Int == 640)
    call.attachments = [image]
    #expect(call.unsentImages == [image])
    call.messages = [ChatMessage(role: "user", text: "Explain this diagram", images: [image])]
    #expect(call.unsentImages.isEmpty)
    try library.save(call)
    let loaded = try #require(library.load().first)
    #expect(loaded.messages[0].images == [image])
    #expect(try library.imageURLs(for: loaded) == [url])
    call.attachments = []; try library.save(call)
    #expect(try library.imageURLs(for: call).isEmpty)
    #expect(try library.load().first?.messages[0].images == [image])
    #expect(FileManager.default.isReadableFile(atPath: url.path))
}

@Test @MainActor func invalidAndMissingImagesReportErrorsAndOldAttachmentsLoad() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("oblivion-images-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let library = try LibraryStore(root: root)
    let old = Attachment(name: "notes.txt", relativePath: "attachments/notes.txt", text: "Prior preparation")
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
    object.removeValue(forKey: "imageRelativePath")
    let restored = try JSONDecoder().decode(Attachment.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(!restored.isImage)
    #expect(restored.text == "Prior preparation")
    #expect(throws: (any Error).self) { try library.importImage(Data("not an image".utf8), name: "broken.png", callID: UUID()) }
    #expect(throws: (any Error).self) { try library.importImage(Data(count: 30 * 1024 * 1024 + 1), name: "large.png", callID: UUID()) }
    var call = CallRecord()
    call.attachments = [Attachment(name: "missing.png", relativePath: "attachments/missing.png", text: "", imageRelativePath: "attachments/missing-vision.png")]
    #expect(throws: (any Error).self) { try library.imageURLs(for: call) }
    call.attachments[0].imageRelativePath = "../../private.png"
    #expect(library.imageURL(call.attachments[0], callID: call.id) == nil)
}

@Test @MainActor func pastedImagesEnableSendAndStayInTheirOwnCall() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("oblivion-images-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let state = AppState(root: root, connect: false)
    let first = state.newCall()
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let editor = SubmitTextView()
    editor.onImage = state.attachImage
    board.setData(try jpegFixture(), forType: .tiff)
    board.setString("OCR fallback alongside the image", forType: .string)
    #expect(editor.pasteAttachments(from: board))
    #expect(state.canSend)
    #expect(state.selected?.attachments.count == 1)
    #expect(state.composer.isEmpty)
    let second = state.newCall()
    #expect(!state.canSend)
    #expect(state.selected?.attachments.isEmpty == true)
    state.selectedID = first
    #expect(state.canSend)
    board.clearContents(); board.setString("Normal pasted text", forType: .string)
    #expect(!editor.pasteAttachments(from: board))
    var urls: [URL] = []
    editor.onFiles = { urls = $0 }
    board.clearContents(); board.writeObjects([root.appendingPathComponent("photo.jpg") as NSURL])
    #expect(editor.pasteAttachments(from: board))
    #expect(urls.count == 1)
    state.selectedID = second
    let restored = AppState(root: root, connect: false)
    #expect(restored.calls.first(where: { $0.id == first })?.attachments.count == 1)
}

@Test @MainActor func markdownIsOneCopyableDocumentWithFormattingAndLinks() throws {
    let rendered = MarkdownBody.render("## Findings\n\nFirst **important** paragraph.\n\n- One\n- Two\n\n[Source](https://example.com)\n\n```\nlet value = 42\n```", fontSize: 15)
    #expect(rendered.string == "Findings\n\nFirst important paragraph.\n\n• One\n• Two\n\nSource\n\nlet value = 42")
    let sourceRange = (rendered.string as NSString).range(of: "Source")
    #expect(rendered.attribute(.link, at: sourceRange.location, effectiveRange: nil) as? URL == URL(string: "https://example.com"))
    let emphasized = (rendered.string as NSString).range(of: "important")
    let font = try #require(rendered.attribute(.font, at: emphasized.location, effectiveRange: nil) as? NSFont)
    #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    let view = NSTextView()
    view.isEditable = false; view.isSelectable = true; view.textStorage?.setAttributedString(rendered)
    view.selectAll(nil)
    #expect(view.selectedRange().length == rendered.length)
}

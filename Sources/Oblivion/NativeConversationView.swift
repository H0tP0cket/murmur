import SwiftUI
import AppKit
import ImageIO

/// One native, viewport-backed document. TextKit keeps offscreen history as text
/// and layout data instead of retaining a SwiftUI view/layer for every reply.
/// Streaming replaces only the changed tail; selection spans the whole chat.
struct NativeConversationView: NSViewRepresentable {
    var callID: UUID
    var messages: [ChatMessage]
    var library: LibraryStore
    var busy: Bool
    var status: String
    var save: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ChatScrollView {
        let scroll = ChatScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let text = ChatDocumentView(frame: .zero)
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = true
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 35, height: 22)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.lineFragmentPadding = 0
        text.layoutManager?.allowsNonContiguousLayout = true
        text.linkTextAttributes = [.foregroundColor: NSColor.secondaryLabelColor, .underlineStyle: 0]
        text.setAccessibilityLabel("Conversation")
        text.delegate = context.coordinator
        scroll.documentView = text
        context.coordinator.textView = text
        context.coordinator.scrollView = scroll
        text.onWidthChanged = { [weak coordinator = context.coordinator] in coordinator?.scrollIfFollowing() }
        scroll.onUserScroll = { [weak coordinator = context.coordinator] in coordinator?.following = false }
        scroll.onDidScroll = { [weak coordinator = context.coordinator] in coordinator?.updateFollowing() }
        return scroll
    }

    func updateNSView(_ scroll: ChatScrollView, context: Context) { context.coordinator.update(self) }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate, NSPopoverDelegate {
        weak var textView: ChatDocumentView?
        weak var scrollView: ChatScrollView?
        var following = true
        private var parent: NativeConversationView?
        private var previous: [ChatMessage] = []
        private var offsets: [Int] = []
        private var messageEnd = 0
        private var previousStatus = ""
        private var scrollScheduled = false
        private var imageLinks: [String: URL] = [:]
        private var thumbnails: [URL: NSImage] = [:]
        private var imagePopover: NSPopover?

        func update(_ next: NativeConversationView) {
            guard let view = textView, let storage = view.textStorage else { return }
            let switched = parent?.callID != next.callID
            let status = next.busy ? next.status : ""
            parent = next
            guard switched || previous != next.messages || status != previousStatus else { return }
            if switched {
                previous = []; offsets = []; messageEnd = 0
                thumbnails = [:]; imageLinks = [:]; following = true
            }
            if next.messages.count > previous.count { following = true }
            var prefix = 0
            while prefix < min(previous.count, next.messages.count), previous[prefix] == next.messages[prefix] { prefix += 1 }
            let start = switched ? 0 : prefix < offsets.count ? offsets[prefix] : messageEnd
            offsets = Array(offsets.prefix(prefix))
            let tail = NSMutableAttributedString(string: "")
            for index in prefix..<next.messages.count {
                offsets.append(start + tail.length)
                tail.append(render(next.messages[index], index: index, parent: next))
            }
            messageEnd = start + tail.length
            if !status.isEmpty { tail.append(label(status, size: 12)) }
            storage.beginEditing()
            storage.replaceCharacters(in: NSRange(location: start, length: storage.length - start), with: tail)
            storage.endEditing()
            previous = next.messages; previousStatus = status
            view.userRanges = next.messages.enumerated().compactMap { index, message in
                guard message.role == "user" else { return nil }
                let end = index + 1 < offsets.count ? offsets[index + 1] : messageEnd
                return NSRange(location: offsets[index], length: max(0, end - offsets[index] - 2))
            }
            view.needsDisplay = true
            scrollIfFollowing()
        }

        private func render(_ message: ChatMessage, index: Int, parent: NativeConversationView) -> NSAttributedString {
            let result = NSMutableAttributedString(string: "")
            for attachment in message.images ?? [] {
                guard let url = parent.library.imageURL(attachment, callID: parent.callID) else { continue }
                let token = attachment.id.uuidString
                imageLinks[token] = url
                if let image = thumbnail(url) {
                    let attachment = NSTextAttachment()
                    attachment.image = image
                    let attributed = NSMutableAttributedString(attachment: attachment)
                    attributed.addAttribute(.link, value: URL(string: "oblivion://image/\(token)")!, range: NSRange(location: 0, length: attributed.length))
                    result.append(attributed)
                }
                result.append(label("  \(attachment.name)\n\n", size: 11))
            }
            if message.role == "user" {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = 6
                paragraph.firstLineHeadIndent = 50
                paragraph.headIndent = 50
                paragraph.tailIndent = -12
                paragraph.paragraphSpacingBefore = 12
                paragraph.paragraphSpacing = 12
                result.append(NSAttributedString(string: message.text, attributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]))
            } else if message.role == "system" {
                result.append(label(message.text, size: 12))
            } else {
                result.append(MarkdownBody.render(message.text.isEmpty ? " " : message.text, fontSize: 15))
            }
            if message.role == "assistant", index > 0, !message.text.isEmpty {
                result.append(label("\n", size: 10))
                result.append(action("Copy", kind: "copy", id: message.id))
                result.append(label("    ", size: 10))
                result.append(action("Save for call", kind: "save", id: message.id))
                if message.interrupted { result.append(label("    Stopped", size: 10)) }
            }
            result.append(NSAttributedString(string: "\n\n", attributes: [.font: NSFont.systemFont(ofSize: 15)]))
            return result
        }

        private func label(_ text: String, size: CGFloat) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            return NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph])
        }

        private func action(_ text: String, kind: String, id: UUID) -> NSAttributedString {
            let value = NSMutableAttributedString(attributedString: label(text, size: 10))
            value.addAttributes([
                .link: URL(string: "oblivion://\(kind)/\(id.uuidString)")!,
                .toolTip: kind == "save" ? "Save this response as a prepared answer for the live call HUD" : "Copy the full Markdown response"
            ], range: NSRange(location: 0, length: value.length))
            return value
        }

        private func thumbnail(_ url: URL) -> NSImage? {
            if let cached = thumbnails[url] { return cached }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 224] as CFDictionary) else { return nil }
            let scale = min(112 / CGFloat(cg.width), 112 / CGFloat(cg.height))
            let image = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) * scale, height: CGFloat(cg.height) * scale))
            thumbnails[url] = image
            return image
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL, url.scheme == "oblivion", let parent else { return false }
            let token = url.lastPathComponent
            if url.host == "image", let imageURL = imageLinks[token] {
                imagePopover?.close()
                let popover = NSPopover()
                imagePopover = popover
                popover.behavior = .transient
                popover.delegate = self
                popover.contentSize = NSSize(width: 556, height: 480)
                popover.contentViewController = NSHostingController(rootView: ChatImagePreview(url: imageURL, initialImage: thumbnails[imageURL], close: { [weak popover] in popover?.close() }))
                let rect = textView.firstRect(forCharacterRange: NSRange(location: charIndex, length: 1), actualRange: nil)
                if let window = textView.window {
                    popover.show(relativeTo: textView.convert(window.convertFromScreen(rect), from: nil), of: textView, preferredEdge: .maxY)
                }
            } else if let message = parent.messages.first(where: { $0.id.uuidString == token }) {
                if url.host == "copy" { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string) }
                if url.host == "save" { parent.save(message.text) }
            }
            return true
        }

        func popoverDidClose(_ notification: Notification) { imagePopover = nil }

        func updateFollowing() {
            guard let scroll = scrollView, let view = textView else { return }
            following = scroll.contentView.bounds.maxY >= view.bounds.height - 25
        }

        func scrollIfFollowing() {
            guard following, !scrollScheduled else { return }
            scrollScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scrollScheduled = false
                guard self.following, let view = self.textView else { return }
                view.scrollRangeToVisible(NSRange(location: view.textStorage?.length ?? 0, length: 0))
            }
        }
    }
}

final class ChatScrollView: NSScrollView {
    var onUserScroll: (() -> Void)?
    var onDidScroll: (() -> Void)?
    private var liveObservers: [NSObjectProtocol] = []
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        liveObservers = [
            NotificationCenter.default.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: self, queue: .main) { [weak self] _ in self?.onUserScroll?() },
            NotificationCenter.default.addObserver(forName: NSScrollView.didLiveScrollNotification, object: self, queue: .main) { [weak self] _ in self?.onDidScroll?() }
        ]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { liveObservers.forEach(NotificationCenter.default.removeObserver) }
    override func scrollWheel(with event: NSEvent) { onUserScroll?(); super.scrollWheel(with: event); onDidScroll?() }
}

final class ChatDocumentView: NSTextView {
    var userRanges: [NSRange] = []
    var onWidthChanged: (() -> Void)?
    override func setFrameSize(_ newSize: NSSize) {
        let changed = abs(frame.width - newSize.width) > 0.5
        super.setFrameSize(newSize)
        if changed { onWidthChanged?() }
    }
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let layoutManager, let textContainer else { return }
        let origin = textContainerOrigin
        let visibleGlyphs = layoutManager.glyphRange(forBoundingRect: rect.offsetBy(dx: -origin.x, dy: -origin.y), in: textContainer)
        let visibleCharacters = layoutManager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
        NSColor(white: 1, alpha: 0.045).setFill()
        for range in userRanges where NSIntersectionRange(range, visibleCharacters).length > 0 {
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let bounds = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer).offsetBy(dx: origin.x, dy: origin.y)
            NSBezierPath(roundedRect: bounds.insetBy(dx: -12, dy: -9), xRadius: 18, yRadius: 18).fill()
        }
    }
}

private struct ChatImagePreview: View {
    let url: URL
    var initialImage: NSImage?
    var close: () -> Void
    @State private var image: NSImage?
    var body: some View {
        VStack(spacing: 14) {
            HStack { Text("Image preview").font(.headline); Spacer(); Button("Done", action: close) }
            if let image = image ?? initialImage { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 520, maxHeight: 380) }
            Spacer(minLength: 0)
            Button("Open full image") { NSWorkspace.shared.open(url) }
        }.padding(18).frame(width: 556, height: 480).preferredColorScheme(.dark).tint(OblivionStyle.accent)
            .task {
                let cg = await Task.detached(priority: .utility) {
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil as CGImage? }
                    return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1040] as CFDictionary)
                }.value
                guard !Task.isCancelled else { return }
                image = cg.map { NSImage(cgImage: $0, size: .zero) }
            }
    }
}

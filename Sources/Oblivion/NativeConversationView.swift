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
        text.onAction = { [weak coordinator = context.coordinator] url in
            guard let coordinator, let text = coordinator.textView else { return }
            _ = coordinator.textView(text, clickedOnLink: url, at: 0)
        }
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
            view.scheduleActionLayout()
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
                result.append(label("  ", size: 11))
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
            // Text reserves space; only visible actions get real native buttons.
            let value = NSMutableAttributedString(attributedString: label("   \(text)   ", size: 11))
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = 30
            paragraph.paragraphSpacingBefore = 8
            value.addAttributes([
                .oblivionAction: URL(string: "oblivion://\(kind)/\(id.uuidString)")!,
                .foregroundColor: NSColor.clear,
                .paragraphStyle: paragraph
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
        contentView.postsBoundsChangedNotifications = true
        liveObservers = [
            NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: contentView, queue: .main) { [weak self] _ in
                (self?.documentView as? ChatDocumentView)?.scheduleActionLayout()
            },
            NotificationCenter.default.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: self, queue: .main) { [weak self] _ in self?.onUserScroll?() },
            NotificationCenter.default.addObserver(forName: NSScrollView.didLiveScrollNotification, object: self, queue: .main) { [weak self] _ in self?.onDidScroll?() }
        ]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { liveObservers.forEach(NotificationCenter.default.removeObserver) }
    override func scrollWheel(with event: NSEvent) { onUserScroll?(); super.scrollWheel(with: event); onDidScroll?() }
}

extension NSAttributedString.Key {
    static let oblivionAction = NSAttributedString.Key("OblivionMessageAction")
}

final class ChatDocumentView: NSTextView {
    var userRanges: [NSRange] = []
    var onWidthChanged: (() -> Void)?
    var onAction: ((URL) -> Void)?
    private(set) var actionButtons: [URL: ChatActionButton] = [:]
    private var actionLayoutScheduled = false

    func scheduleActionLayout() {
        guard !actionLayoutScheduled else { return }
        actionLayoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.actionLayoutScheduled = false
            self.layoutActionButtons()
        }
    }

    override func layout() {
        super.layout()
        layoutActionButtons()
    }

    override func accessibilityChildren() -> [Any]? {
        // NSTextView exposes its text links, but not embedded NSButton subviews.
        (super.accessibilityChildren() ?? []) + actionButtons.values.sorted {
            $0.frame.minY == $1.frame.minY ? $0.frame.minX < $1.frame.minX : $0.frame.minY < $1.frame.minY
        }
    }

    func layoutActionButtons() {
        guard let layoutManager, let textContainer, let textStorage else { return }
        let origin = textContainerOrigin
        let glyphs = layoutManager.glyphRange(forBoundingRect: visibleRect.offsetBy(dx: -origin.x, dy: -origin.y), in: textContainer)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var visible = Set<URL>()
        textStorage.enumerateAttribute(.oblivionAction, in: characters) { value, range, _ in
            guard let url = value as? URL else { return }
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer).offsetBy(dx: origin.x, dy: origin.y)
            let frame = NSRect(x: rect.minX, y: rect.midY - 13, width: max(46, rect.width), height: 26)
            guard visibleRect.intersects(frame) else { return }
            visible.insert(url)
            let button: ChatActionButton
            if let existing = actionButtons[url] { button = existing }
            else {
                button = ChatActionButton(frame: .zero)
                button.title = url.host == "save" ? "Save for call" : "Copy"
                button.toolTip = url.host == "save" ? "Edit and save this response to Must-say" : "Copy the full Markdown response"
                button.onPress = { [weak self, weak button] in
                    self?.onAction?(url)
                    if url.host == "copy" { button?.showCopied() }
                }
                actionButtons[url] = button; addSubview(button)
            }
            if button.frame != frame { button.frame = frame }
        }
        for url in Array(actionButtons.keys) where !visible.contains(url) {
            actionButtons.removeValue(forKey: url)?.removeFromSuperview()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = abs(frame.width - newSize.width) > 0.5
        super.setFrameSize(newSize)
        if changed { onWidthChanged?(); scheduleActionLayout() }
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

/// A small neutral pill with native button semantics, cursor and press feedback.
/// Instances are recycled offscreen, rather than retained for the whole history.
final class ChatActionButton: NSButton {
    var onPress: (() -> Void)?
    private var hovering = false
    private var tracking: NSTrackingArea?
    private var feedbackID = UUID()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        setButtonType(.momentaryPushIn)
        font = .systemFont(ofSize: 11, weight: .medium)
        target = self; action = #selector(pressed)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func pressed() { onPress?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        NSColor(white: 1, alpha: isHighlighted ? 0.18 : hovering ? 0.11 : 0.045).setFill(); path.fill()
        NSColor(white: 1, alpha: hovering ? 0.17 : 0.08).setStroke(); path.lineWidth = 1; path.stroke()
        let label = NSAttributedString(string: title, attributes: [.font: font ?? .systemFont(ofSize: 11), .foregroundColor: hovering ? NSColor.labelColor : NSColor.secondaryLabelColor])
        let size = label.size()
        label.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
    func showCopied() {
        let token = UUID(); feedbackID = token
        title = "Copied"; needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.feedbackID == token else { return }
            self.title = "Copy"; self.needsDisplay = true
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

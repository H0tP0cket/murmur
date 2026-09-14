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
        text.textContainerInset = NSSize(width: 28, height: 18)
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
        private var userWidths: [UUID: (text: String, width: CGFloat)] = [:]

        func update(_ next: NativeConversationView) {
            guard let view = textView, let storage = view.textStorage else { return }
            let switched = parent?.callID != next.callID
            let status = next.busy ? next.status : ""
            parent = next
            guard switched || previous != next.messages || status != previousStatus else { return }
            if switched {
                previous = []; offsets = []; messageEnd = 0
                thumbnails = [:]; imageLinks = [:]; userWidths = [:]; following = true
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
            view.userMessages = next.messages.enumerated().compactMap { index, message in
                guard message.role == "user" else { return nil }
                let end = index + 1 < offsets.count ? offsets[index + 1] : messageEnd
                let textWidth: CGFloat
                if let cached = userWidths[message.id], cached.text == message.text { textWidth = cached.width }
                else {
                    // Measure unwrapped text once, not again during every scroll or
                    // streaming update. TextKit still owns the actual wrapped layout.
                    textWidth = (message.text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 15)]).width
                    userWidths[message.id] = (message.text, textWidth)
                }
                let imageWidth = (message.images ?? []).map { 112 + ("  " + $0.name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width }.max() ?? 0
                return UserMessageLayout(range: NSRange(location: offsets[index], length: max(0, end - offsets[index] - 2)), naturalWidth: max(textWidth, imageWidth))
            }
            view.needsDisplay = true
            view.scheduleActionLayout()
            scrollIfFollowing()
        }

        private func render(_ message: ChatMessage, index: Int, parent: NativeConversationView) -> NSAttributedString {
            let result = NSMutableAttributedString(string: "")
            if message.pending == true, message.text.isEmpty { return result }
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
                paragraph.lineSpacing = 4
                paragraph.firstLineHeadIndent = 14
                paragraph.headIndent = 14
                paragraph.tailIndent = -14
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
            // A blank attachment reserves space without selectable button words.
            let spacer = NSTextAttachment()
            spacer.attachmentCell = ActionSpacerCell(title: text)
            let value = NSMutableAttributedString(attachment: spacer)
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

        func textView(_ textView: NSTextView, clickedOn cell: NSTextAttachmentCellProtocol, in cellFrame: NSRect, at charIndex: Int) {
            // AppKit sends attachment clicks through the cell delegate, rather
            // than the ordinary link delegate used by text.
            guard let storage = textView.textStorage, charIndex < storage.length,
                  let link = storage.attribute(.link, at: charIndex, effectiveRange: nil) else { return }
            _ = self.textView(textView, clickedOnLink: link, at: charIndex)
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

struct UserMessageLayout {
    var range: NSRange
    var naturalWidth: CGFloat

    func bubbleWidth(in columnWidth: CGFloat) -> CGFloat {
        min(max(40, ceil(naturalWidth) + 28), max(40, columnWidth * 0.82))
    }
}

final class ChatDocumentView: NSTextView {
    var userMessages: [UserMessageLayout] = [] {
        didSet { applyUserMessageLayout() }
    }
    var onWidthChanged: (() -> Void)?
    var onAction: ((URL) -> Void)?
    private(set) var actionButtons: [URL: ChatActionButton] = [:]
    private var actionLayoutScheduled = false
    private var selectionObserver: NSObjectProtocol?
    private var ownedTextStorage: NSTextStorage?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer? = nil) {
        var container = container
        if container == nil {
            let storage = NSTextStorage()
            let layout = NSLayoutManager()
            let textContainer = NSTextContainer(size: NSSize(width: frameRect.width, height: .greatestFiniteMagnitude))
            storage.addLayoutManager(layout)
            layout.addTextContainer(textContainer)
            ownedTextStorage = storage
            container = textContainer
        }
        super.init(frame: frameRect, textContainer: container)
        if ownedTextStorage != nil {
            isVerticallyResizable = true
            isHorizontallyResizable = false
            minSize = frameRect.size
            maxSize = NSSize(width: frameRect.width, height: .greatestFiniteMagnitude)
            container?.widthTracksTextView = true
        }
        selectedTextAttributes = [.backgroundColor: NSColor(white: 0.32, alpha: 1), .foregroundColor: NSColor.labelColor]
        focusRingType = .none
        selectionObserver = NotificationCenter.default.addObserver(forName: NSTextView.didChangeSelectionNotification, object: self, queue: .main) { [weak self] _ in
            guard let self else { return }
            // Invalidate the whole viewport, including blank paragraph/table
            // regions AppKit can miss when a selection is shortened or cleared.
            self.setNeedsDisplay(self.visibleRect)
            let selecting = self.selectedRanges.contains { $0.rangeValue.length > 0 }
            for button in self.actionButtons.values { button.isHidden = selecting }
            self.window?.invalidateCursorRects(for: self)
            self.scheduleActionLayout()
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let selectionObserver { NotificationCenter.default.removeObserver(selectionObserver) } }

    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard [.string, .rtf, .rtfd].contains(type), let textStorage else { return super.writeSelection(to: pboard, type: type) }
        let content = NSMutableAttributedString(string: "")
        for value in selectedRanges {
            let range = value.rangeValue
            guard range.length > 0, NSMaxRange(range) <= textStorage.length else { continue }
            let selected = NSMutableAttributedString(attributedString: textStorage.attributedSubstring(from: range))
            var actions: [NSRange] = []
            selected.enumerateAttribute(.oblivionAction, in: NSRange(location: 0, length: selected.length)) { value, range, _ in
                if value != nil { actions.append(range) }
            }
            for range in actions.reversed() { selected.deleteCharacters(in: range) }
            if content.length > 0 { content.append(NSAttributedString(string: "\n")) }
            content.append(selected)
        }
        if type == .string { return pboard.setString(content.string, forType: .string) }
        let documentType: NSAttributedString.DocumentType = type == .rtfd ? .rtfd : .rtf
        guard let data = try? content.data(from: NSRange(location: 0, length: content.length), documentAttributes: [.documentType: documentType]) else { return false }
        return pboard.setData(data, forType: type)
    }

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
        applyUserMessageLayout()
        layoutActionButtons()
    }

    var messageColumnWidth: CGFloat { max(1, bounds.width - 2 * textContainerInset.width) }

    private func applyUserMessageLayout() {
        guard let textStorage, messageColumnWidth > 40 else { return }
        var edits: [(NSRange, NSParagraphStyle)] = []
        for message in userMessages where message.range.length > 0 && NSMaxRange(message.range) <= textStorage.length {
            let indent = messageColumnWidth - message.bubbleWidth(in: messageColumnWidth) + 14
            let current = textStorage.attribute(.paragraphStyle, at: message.range.location, effectiveRange: nil) as? NSParagraphStyle
            guard current?.headIndent != indent || current?.tailIndent != -14 else { continue }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            paragraph.firstLineHeadIndent = indent; paragraph.headIndent = indent; paragraph.tailIndent = -14
            edits.append((message.range, paragraph))
        }
        guard !edits.isEmpty else { return }
        textStorage.beginEditing()
        for (range, paragraph) in edits { textStorage.addAttribute(.paragraphStyle, value: paragraph, range: range) }
        textStorage.endEditing()
        needsDisplay = true
        scheduleActionLayout()
    }

    func bubbleRect(for message: UserMessageLayout) -> NSRect {
        guard let layoutManager, let textContainer, message.range.length > 0 else { return .zero }
        let glyphs = layoutManager.glyphRange(forCharacterRange: message.range, actualCharacterRange: nil)
        let bounds = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        let width = message.bubbleWidth(in: messageColumnWidth)
        return NSRect(x: textContainerOrigin.x + messageColumnWidth - width, y: bounds.minY - 10, width: width, height: bounds.height + 20)
    }

    override func accessibilityChildren() -> [Any]? {
        // NSTextView exposes its text links, but not embedded NSButton subviews.
        (super.accessibilityChildren() ?? []) + actionButtons.values.filter { !$0.isHidden }.sorted {
            $0.frame.minY == $1.frame.minY ? $0.frame.minX < $1.frame.minX : $0.frame.minY < $1.frame.minY
        }
    }

    func layoutActionButtons() {
        guard let layoutManager, let textContainer, let textStorage else { return }
        let origin = textContainerOrigin
        let glyphs = layoutManager.glyphRange(forBoundingRect: visibleRect.offsetBy(dx: -origin.x, dy: -origin.y), in: textContainer)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var visible = Set<URL>()
        var geometryChanged = false
        let selecting = selectedRanges.contains { $0.rangeValue.length > 0 }
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
                button.toolTip = url.host == "save" ? "Edit and save this response to Cue cards" : "Copy the full Markdown response"
                button.onPress = { [weak self, weak button] in
                    self?.onAction?(url)
                    if url.host == "copy" { button?.showCopied() }
                }
                actionButtons[url] = button; addSubview(button); geometryChanged = true
            }
            if button.frame != frame { button.frame = frame; geometryChanged = true }
            if button.isHidden != selecting { button.isHidden = selecting; geometryChanged = true }
        }
        for url in Array(actionButtons.keys) where !visible.contains(url) {
            actionButtons.removeValue(forKey: url)?.removeFromSuperview()
            geometryChanged = true
        }
        if geometryChanged { window?.invalidateCursorRects(for: self) }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for button in actionButtons.values where !button.isHidden { addCursorRect(button.frame, cursor: .pointingHand) }
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if actionButtons.values.contains(where: { !$0.isHidden && $0.frame.contains(point) }) { NSCursor.pointingHand.set() }
        else { super.cursorUpdate(with: event) }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = abs(frame.width - newSize.width) > 0.5
        super.setFrameSize(newSize)
        if changed { applyUserMessageLayout(); onWidthChanged?(); scheduleActionLayout() }
    }
    override func draw(_ dirtyRect: NSRect) {
        // NSTextView clips drawBackground(in:) to its text-line regions. A bubble
        // includes padding outside those regions, so paint it at document level.
        drawUserBubbles(in: dirtyRect)
        super.draw(dirtyRect)
    }

    private func drawUserBubbles(in rect: NSRect) {
        guard let layoutManager, let textContainer else { return }
        let origin = textContainerOrigin
        let visibleGlyphs = layoutManager.glyphRange(forBoundingRect: rect.insetBy(dx: 0, dy: -12).offsetBy(dx: -origin.x, dy: -origin.y), in: textContainer)
        let visibleCharacters = layoutManager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
        NSColor(white: 1, alpha: 0.045).setFill()
        for message in userMessages where NSIntersectionRange(message.range, visibleCharacters).length > 0 {
            NSBezierPath(roundedRect: bubbleRect(for: message), xRadius: 16, yRadius: 16).fill()
        }
    }
}

/// Invisible geometry only. AppKit selection cannot reveal a second label.
private final class ActionSpacerCell: NSTextAttachmentCell {
    private let size: NSSize
    init(title: String) {
        size = NSSize(width: max(46, ceil((title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium)]).width) + 18), height: 30)
        super.init(textCell: "")
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func cellSize() -> NSSize { size }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {}
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int, layoutManager: NSLayoutManager) {}
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
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseEntered(with event: NSEvent) { hovering = true; NSCursor.pointingHand.set(); needsDisplay = true }
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

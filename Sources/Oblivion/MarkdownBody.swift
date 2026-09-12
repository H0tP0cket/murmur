import SwiftUI
import AppKit

/// One native text surface per response: selection spans headings, paragraphs,
/// lists, and code, while retaining link handling and inline formatting.
struct MarkdownBody: NSViewRepresentable {
    let text: String
    var fontSize: CGFloat = 15

    func makeNSView(context: Context) -> ResponseTextView {
        let view = ResponseTextView()
        view.isEditable = false; view.isSelectable = true; view.drawsBackground = false
        view.isRichText = true; view.importsGraphics = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize.height = .greatestFiniteMagnitude
        view.isHorizontallyResizable = false; view.isVerticallyResizable = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.linkTextAttributes = [.foregroundColor: NSColor.labelColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        view.selectedTextAttributes = [.backgroundColor: NSColor(white: 0.4, alpha: 0.65), .foregroundColor: NSColor.white]
        return view
    }

    func updateNSView(_ view: ResponseTextView, context: Context) {
        view.appearance = NSAppearance(named: .darkAqua)
        guard view.renderedText != text || view.renderedFontSize != fontSize else { return }
        let ranges = view.selectedRanges
        view.textStorage?.setAttributedString(Self.render(text, fontSize: fontSize))
        let length = view.textStorage?.length ?? 0
        view.selectedRanges = ranges.map { value in
            let range = value.rangeValue, start = min(range.location, length)
            return NSValue(range: NSRange(location: start, length: min(range.length, length - start)))
        }
        view.renderedText = text; view.renderedFontSize = fontSize
        view.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ResponseTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, let attributed = nsView.textStorage else { return nil }
        // SwiftUI probes several widths. Measuring in the displayed text view
        // can leave its container at a rejected width and overlap the controls.
        let storage = NSTextStorage(attributedString: attributed)
        let layout = NSLayoutManager(), container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout); layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        return CGSize(width: width, height: max(1, ceil(layout.usedRect(for: container).height)))
    }

    static func render(_ text: String, fontSize: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        for (index, block) in blocks(text).enumerated() {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = fontSize > 13 ? 6 : 4
            paragraph.lineBreakMode = .byWordWrapping
            if block.kind == .quote { paragraph.headIndent = 12; paragraph.firstLineHeadIndent = 12 }
            let size = block.kind == .heading ? (block.level == 1 ? fontSize + 5 : fontSize + 1) : block.kind == .code ? fontSize - 2 : fontSize
            let base = block.kind == .code ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular) : NSFont.systemFont(ofSize: size, weight: block.kind == .heading ? .semibold : .regular)
            let color = block.kind == .quote ? NSColor.secondaryLabelColor : NSColor.labelColor
            let attributes: [NSAttributedString.Key: Any] = [.font: base, .foregroundColor: color, .paragraphStyle: paragraph]
            if index > 0 { result.append(NSAttributedString(string: "\n\n", attributes: attributes)) }
            if block.kind == .code {
                var codeAttributes = attributes
                codeAttributes[.backgroundColor] = NSColor(white: 0.5, alpha: 0.1)
                result.append(NSAttributedString(string: block.text, attributes: codeAttributes))
            } else if let inline = try? AttributedString(markdown: block.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                for run in inline.runs {
                    var styled = attributes, font = base
                    let intent = run.inlinePresentationIntent ?? []
                    if intent.contains(.code) { font = .monospacedSystemFont(ofSize: size - 1, weight: .regular); styled[.backgroundColor] = NSColor(white: 0.5, alpha: 0.1) }
                    if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                    if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                    if intent.contains(.strikethrough) { styled[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                    if let link = run.link { styled[.link] = link; styled[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                    styled[.font] = font
                    result.append(NSAttributedString(string: String(inline[run.range].characters), attributes: styled))
                }
            } else { result.append(NSAttributedString(string: block.text, attributes: attributes)) }
        }
        return result
    }

    private enum Kind { case text, heading, code, quote }
    private struct Block { var kind: Kind; var text: String; var level = 0 }
    private static func blocks(_ text: String) -> [Block] {
        var result: [Block] = [], paragraph: [String] = [], code: [String] = [], inCode = false
        func flush() { if !paragraph.isEmpty { result.append(Block(kind: .text, text: paragraph.joined(separator: "\n"))); paragraph.removeAll() } }
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                flush()
                if inCode { result.append(Block(kind: .code, text: code.joined(separator: "\n"))); code.removeAll() }
                inCode.toggle(); continue
            }
            if inCode { code.append(line); continue }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { flush(); continue }
            let hashes = line.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), line.dropFirst(hashes).first == " " {
                flush(); result.append(Block(kind: .heading, text: String(line.dropFirst(hashes + 1)), level: hashes)); continue
            }
            if line.hasPrefix("> ") { flush(); result.append(Block(kind: .quote, text: String(line.dropFirst(2)))); continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") { paragraph.append("• " + line.dropFirst(2)) }
            else if line == "---" { flush() }
            else { paragraph.append(line) }
        }
        flush()
        if !code.isEmpty { result.append(Block(kind: .code, text: code.joined(separator: "\n"))) }
        return result
    }
}

final class ResponseTextView: NSTextView {
    var renderedText: String?
    var renderedFontSize: CGFloat = 0
}

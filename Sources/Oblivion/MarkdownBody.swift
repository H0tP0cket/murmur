import SwiftUI
import AppKit

/// A single selectable text surface lets selections cross Markdown blocks.
/// SwiftUI owns wrapping and height, including after sidebar/window resizing.
struct MarkdownBody: View, Equatable {
    let text: String
    var fontSize: CGFloat = 15
    private static let renderedCache: NSCache<NSString, NSAttributedString> = {
        let cache = NSCache<NSString, NSAttributedString>()
        cache.countLimit = 64
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    var body: some View {
        Text(AttributedString(Self.render(text, fontSize: fontSize)))
            .font(.system(size: fontSize))
            .lineSpacing(fontSize > 13 ? 6 : 4)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func render(_ text: String, fontSize: CGFloat) -> NSAttributedString {
        let key = "\(fontSize):\(text)" as NSString
        if let cached = renderedCache.object(forKey: key) { return cached }
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
        let immutable = NSAttributedString(attributedString: result)
        renderedCache.setObject(immutable, forKey: key, cost: max(1, text.utf16.count * 8))
        return immutable
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

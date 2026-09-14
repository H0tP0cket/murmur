import SwiftUI
import AppKit

/// One attributed document preserves selection across paragraphs and table cells.
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
        // SwiftUI Text does not lay out NSTextTable. Compact HUD/notes surfaces
        // use labeled rows; the native conversation gets selectable grid cells.
        Text(AttributedString(Self.render(text, fontSize: fontSize, nativeTables: false)))
            .font(.system(size: fontSize)).lineSpacing(4).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func render(_ text: String, fontSize: CGFloat, nativeTables: Bool = true) -> NSAttributedString {
        let key = "\(fontSize):\(nativeTables):\(text)" as NSString
        if let cached = renderedCache.object(forKey: key) { return cached }
        let result = NSMutableAttributedString(string: "")
        var previous: Kind?
        for block in blocks(text) {
            if previous != nil {
                let adjacent = (previous == .list && block.kind == .list) || (previous == .quote && block.kind == .quote)
                // Tables already end in a paragraph break with cell attributes.
                let separator = previous == .table && nativeTables ? "\n" : adjacent ? "\n" : "\n\n"
                result.append(NSAttributedString(string: separator, attributes: [.font: NSFont.systemFont(ofSize: adjacent ? fontSize : fontSize * 0.5), .paragraphStyle: NSParagraphStyle.default]))
            }
            previous = block.kind
            if block.kind == .table {
                result.append(renderTable(block, fontSize: fontSize, native: nativeTables))
                continue
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            paragraph.lineBreakMode = .byWordWrapping
            if block.kind == .quote { paragraph.headIndent = 12; paragraph.firstLineHeadIndent = 12 }
            if block.kind == .list {
                paragraph.firstLineHeadIndent = CGFloat(block.level) * 16
                paragraph.headIndent = paragraph.firstLineHeadIndent + 18
            }
            let size = block.kind == .heading ? (block.level == 1 ? fontSize + 5 : fontSize + 1) : block.kind == .code ? fontSize - 2 : fontSize
            let font = block.kind == .code ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular) : NSFont.systemFont(ofSize: size, weight: block.kind == .heading ? .semibold : .regular)
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: block.kind == .quote ? NSColor.secondaryLabelColor : NSColor.labelColor, .paragraphStyle: paragraph]
            if block.kind == .code {
                attributes[.backgroundColor] = NSColor(white: 0.5, alpha: 0.1)
                result.append(NSAttributedString(string: block.text, attributes: attributes))
            } else { result.append(inline(block.text, attributes: attributes)) }
        }
        let immutable = NSAttributedString(attributedString: result)
        renderedCache.setObject(immutable, forKey: key, cost: max(1, text.utf16.count * 12))
        return immutable
    }

    private static func inline(_ text: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        guard let parsed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else { return NSAttributedString(string: text, attributes: attributes) }
        let result = NSMutableAttributedString(string: "")
        for run in parsed.runs {
            var styled = attributes
            var font = attributes[.font] as? NSFont ?? .systemFont(ofSize: 15)
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) { font = .monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular); styled[.backgroundColor] = NSColor(white: 0.5, alpha: 0.1) }
            if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            if intent.contains(.strikethrough) { styled[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { styled[.link] = link; styled[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            styled[.font] = font
            result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: styled))
        }
        return result
    }

    private static func renderTable(_ block: Block, fontSize: CGFloat, native: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let columns = block.alignments.count
        let table = NSTextTable()
        table.numberOfColumns = columns
        table.layoutAlgorithm = .fixedLayoutAlgorithm
        table.collapsesBorders = true
        table.setValue(100, type: .percentageValueType, for: .width)
        for (rowIndex, row) in block.rows.enumerated() {
            if !native, rowIndex == 0 { continue }
            if !native, result.length > 0 { result.append(NSAttributedString(string: "\n\n")) }
            for column in 0..<columns {
                let value = column < row.count ? row[column] : ""
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = 3
                paragraph.lineBreakMode = .byWordWrapping
                paragraph.alignment = block.alignments[column]
                if native {
                    let cell = NSTextTableBlock(table: table, startingRow: rowIndex, rowSpan: 1, startingColumn: column, columnSpan: 1)
                    cell.setValue(100 / CGFloat(columns), type: .percentageValueType, for: .width)
                    cell.setWidth(9, type: .absoluteValueType, for: .padding)
                    cell.setWidth(0.5, type: .absoluteValueType, for: .border)
                    cell.setBorderColor(NSColor(white: 0.5, alpha: 0.28))
                    cell.backgroundColor = NSColor(white: 0.5, alpha: rowIndex == 0 ? 0.13 : 0.025)
                    cell.verticalAlignment = .topAlignment
                    paragraph.textBlocks = [cell]
                }
                let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize, weight: rowIndex == 0 ? .semibold : .regular), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
                if !native {
                    if column > 0 { result.append(NSAttributedString(string: "\n", attributes: attributes)) }
                    var heading = attributes
                    heading[.font] = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
                    result.append(inline(block.rows[0][column] + ": ", attributes: heading))
                }
                let content = value.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
                result.append(inline(content, attributes: attributes))
                if native { result.append(NSAttributedString(string: "\n", attributes: attributes)) }
            }
        }
        return result
    }

    private enum Kind { case text, heading, code, quote, list, table }
    private struct Block {
        var kind: Kind
        var text: String = ""
        var level = 0
        var rows: [[String]] = []
        var alignments: [NSTextAlignment] = []
    }

    /// Pipes in inline code and escaped pipes are cell content, not separators.
    private static func cells(_ line: String) -> [String]? {
        let chars = Array(line.trimmingCharacters(in: .whitespaces))
        var cells: [String] = [], cell = "", codeTicks = 0, i = 0, separators = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "\\", i + 1 < chars.count {
                cell.append(ch); cell.append(chars[i + 1]); i += 2; continue
            }
            if ch == "`" {
                var count = 1
                while i + count < chars.count, chars[i + count] == "`" { count += 1 }
                // An unmatched backtick is literal Markdown, not a code span.
                let marker = String(repeating: "`", count: count)
                if codeTicks == count { codeTicks = 0 }
                else if codeTicks == 0, String(chars.dropFirst(i + count)).contains(marker) { codeTicks = count }
                cell += marker; i += count; continue
            }
            if ch == "|", codeTicks == 0 { cells.append(cell); cell = ""; separators += 1 }
            else { cell.append(ch) }
            i += 1
        }
        cells.append(cell)
        guard separators > 0 else { return nil }
        if chars.first == "|", cells.first?.isEmpty == true { cells.removeFirst() }
        if chars.last == "|", cells.last?.isEmpty == true { cells.removeLast() }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func tableAlignment(_ line: String, columns: Int) -> [NSTextAlignment]? {
        guard let parts = cells(line), parts.count == columns, !parts.isEmpty,
              parts.allSatisfy({ $0.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil }) else { return nil }
        return parts.map { $0.hasSuffix(":") ? ($0.hasPrefix(":") ? .center : .right) : .left }
    }

    private static func blocks(_ text: String) -> [Block] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result: [Block] = [], paragraph: [String] = [], i = 0
        func flush() {
            if !paragraph.isEmpty { result.append(Block(kind: .text, text: paragraph.joined(separator: "\n"))); paragraph.removeAll() }
        }
        while i < lines.count {
            let raw = lines[i], line = raw.trimmingCharacters(in: .whitespaces)
            i += 1
            if line.isEmpty { flush(); continue }
            if let marker = line.first, marker == "`" || marker == "~", line.prefix(while: { $0 == marker }).count >= 3 {
                flush()
                let count = line.prefix { $0 == marker }.count
                var code: [String] = []
                while i < lines.count {
                    let next = lines[i].trimmingCharacters(in: .whitespaces)
                    i += 1
                    let closingCount = next.prefix { $0 == marker }.count
                    if closingCount >= count, next.dropFirst(closingCount).trimmingCharacters(in: .whitespaces).isEmpty { break }
                    code.append(lines[i - 1])
                }
                result.append(Block(kind: .code, text: code.joined(separator: "\n"))); continue
            }
            if i < lines.count, let headers = cells(line), let alignment = tableAlignment(lines[i], columns: headers.count) {
                flush(); i += 1
                var rows = [headers]
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).isEmpty, let row = cells(lines[i]) {
                    // GFM pads missing cells and ignores excess cells.
                    rows.append(Array(row.prefix(headers.count))); i += 1
                }
                result.append(Block(kind: .table, rows: rows, alignments: alignment)); continue
            }
            let hashes = line.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), line.dropFirst(hashes).first == " " {
                flush(); result.append(Block(kind: .heading, text: String(line.dropFirst(hashes + 1)), level: hashes)); continue
            }
            if line.range(of: #"^(?:-{3,}|\*{3,}|_{3,})$"#, options: .regularExpression) != nil { flush(); continue }
            if line.hasPrefix(">") { flush(); result.append(Block(kind: .quote, text: String(line.dropFirst()).trimmingCharacters(in: .whitespaces))); continue }
            if let marker = line.range(of: #"^(?:[-*+] |\d+[.)] )"#, options: .regularExpression) {
                flush()
                var body = String(line[marker.upperBound...])
                let prefix = String(line[..<marker.upperBound])
                var bullet = prefix.first?.isNumber == true ? prefix : "• "
                if body.hasPrefix("[ ] ") { bullet = "☐ "; body = String(body.dropFirst(4)) }
                else if body.lowercased().hasPrefix("[x] ") { bullet = "☑ "; body = String(body.dropFirst(4)) }
                let level = raw.prefix(while: { $0 == " " || $0 == "\t" }).reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } / 2
                result.append(Block(kind: .list, text: bullet + body, level: level)); continue
            }
            if raw.first?.isWhitespace == true, result.last?.kind == .list, paragraph.isEmpty {
                result[result.count - 1].text += "\n" + line
            } else { paragraph.append(raw) }
        }
        flush()
        return result
    }
}

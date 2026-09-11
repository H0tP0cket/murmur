import SwiftUI

/// Native block layout for conversational Markdown; links and inline emphasis
/// are rendered by SwiftUI, with no embedded browser or remote resources.
struct MarkdownBody: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block.kind {
                case .heading:
                    Text(.init(block.text)).font(.system(size: block.level == 1 ? 20 : 16, weight: .semibold)).padding(.top, 6).textSelection(.enabled)
                case .code:
                    ScrollView(.horizontal) { Text(block.text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).padding(12) }
                        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                case .quote:
                    Text(.init(block.text)).font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(5).textSelection(.enabled).padding(.leading, 12).overlay(alignment: .leading) { Rectangle().fill(.primary.opacity(0.15)).frame(width: 2) }
                case .text:
                    Text(.init(block.text)).font(.system(size: 15)).lineSpacing(6).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private enum Kind { case text, heading, code, quote }
    private struct Block { var kind: Kind; var text: String; var level = 0 }
    private var blocks: [Block] {
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

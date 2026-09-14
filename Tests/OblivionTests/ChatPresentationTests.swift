import AppKit
import Testing
@testable import Oblivion

@Test func chatBuffersWholeBlocksAndKeepsEveryByteOnStopAndFinalCorrection() {
    var buffer = ChatStreamBuffer()
    let heading = "## A useful answer\n\n"
    let table = "| If they say | Ask |\n|---|---|\n| Slow claims | Who owns the work? |"
    buffer.receive(heading + "| If", at: 0)
    #expect(buffer.takeReady(at: 0.2) == nil)
    #expect(buffer.takeReady(at: 0.8) == heading.trimmingCharacters(in: .newlines))
    buffer.receive(heading + table, at: 1)
    #expect(buffer.takeReady(at: 4) == nil) // No partial table/reflow.
    buffer.receive(heading + table + "\n\nFollowing paragraph", at: 4)
    #expect(buffer.takeReady(at: 4) == heading + table)
    #expect(buffer.finish() == heading + table + "\n\nFollowing paragraph")
    #expect(buffer.finish() == nil)
    #expect(buffer.finish("Corrected final answer.") == "Corrected final answer.")

    var code = ChatStreamBuffer()
    code.receive("```swift\nlet text = 1\n\nlet next", at: 0)
    #expect(code.takeReady(at: 8) == nil) // Blank line inside a fence isn't a boundary.
    code.receive("```swift\nlet text = 1\n\nlet next = 2\n```\n\n", at: 8)
    #expect(code.takeReady(at: 9)?.contains("let next = 2") == true)

    var prose = ChatStreamBuffer()
    let sentence = String(repeating: "Useful grounded context ", count: 8) + "ends here. "
    prose.receive(sentence + "An unfinished **span", at: 0)
    #expect(prose.takeReady(at: 0.8) == nil)
    #expect(prose.takeReady(at: 2.1) == sentence)
    #expect(prose.finish() == sentence + "An unfinished **span")
}

@Test @MainActor func stoppedStreamCannotPublishStaleScheduledUpdates() async throws {
    var outputs: [String] = []
    let stream = ChatResponseStream { outputs.append($0) }
    stream.receive("A complete paragraph.\n\nAn incomplete tail")
    stream.finish()
    stream.receive("Late text must be ignored")
    try await Task.sleep(for: .milliseconds(850))
    #expect(outputs == ["A complete paragraph.\n\nAn incomplete tail"])
}

@Test @MainActor func markdownTablesHaveRealCellsAndKeepFormattingLinksAndSelection() throws {
    let markdown = """
    ## Follow the answer

    | If he says… | Ask… |
    | :--- | ---: |
    | **Claims are slow** | [Who owns the work?](https://example.com) |
    | A \\| B | `left | right`<br>Next line |

    - [x] Ask about ownership
      - Follow up
    1. Summarize

    ~~~text
    | literal | pipes |
    ~~~
    """
    let rendered = MarkdownBody.render(markdown, fontSize: 15)
    #expect(!rendered.string.contains(":---"))
    #expect(rendered.string.contains("A | B"))
    #expect(rendered.string.contains("left | right\nNext line"))
    #expect(rendered.string.contains("☑ Ask about ownership\n• Follow up\n1. Summarize"))
    #expect(rendered.string.contains("| literal | pipes |"))
    func style(_ text: String) throws -> NSParagraphStyle {
        let range = (rendered.string as NSString).range(of: text)
        #expect(range.location != NSNotFound)
        return try #require(rendered.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)
    }
    let header = try #require(try style("If he says…").textBlocks.first as? NSTextTableBlock)
    let question = try #require(try style("Who owns the work?").textBlocks.first as? NSTextTableBlock)
    #expect(header.table === question.table)
    #expect(header.table.numberOfColumns == 2)
    #expect(question.startingRow == 1 && question.startingColumn == 1)
    #expect(try style("Who owns the work?").alignment == .right)
    #expect(try style("Follow up").headIndent > style("Ask about ownership").headIndent)
    let link = (rendered.string as NSString).range(of: "Who owns the work?")
    #expect(rendered.attribute(.link, at: link.location, effectiveRange: nil) as? URL == URL(string: "https://example.com"))
    let strong = (rendered.string as NSString).range(of: "Claims are slow")
    let font = try #require(rendered.attribute(.font, at: strong.location, effectiveRange: nil) as? NSFont)
    #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    let fallback = MarkdownBody.render(markdown, fontSize: 15, nativeTables: false)
    #expect(fallback.string.contains("If he says…\nClaims are slow\nAsk…\nWho owns the work?"))

    let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
    view.isEditable = false; view.isSelectable = true; view.isVerticallyResizable = true
    view.textContainer?.widthTracksTextView = true
    view.textStorage?.setAttributedString(rendered)
    let layout = try #require(view.layoutManager), container = try #require(view.textContainer)
    layout.ensureLayout(for: container)
    let wide = layout.usedRect(for: container)
    #expect(wide.height > 100 && wide.height < 1200)
    #expect(wide.width <= 710)
    view.selectAll(nil)
    #expect(view.selectedRange().length == rendered.length)
    view.setFrameSize(NSSize(width: 340, height: 500))
    layout.ensureLayout(for: container)
    let narrow = layout.usedRect(for: container)
    #expect(narrow.height >= wide.height)
    #expect(narrow.width <= 350)
    #expect(view.string == rendered.string)
}

@Test @MainActor func markdownDoesNotInventTablesFromProseOrCodeAndPadsShortRows() throws {
    let ordinary = "An ordinary A | B comparison\nNot a separator\n\n```\n| Title | Value |\n|---|---|\n```"
    let rendered = MarkdownBody.render(ordinary, fontSize: 15)
    #expect(rendered.string.contains("A | B comparison"))
    #expect(rendered.string.contains("|---|---|"))
    let short = MarkdownBody.render("A | B\n---|---\nOnly one |\n", fontSize: 15)
    #expect(short.string.contains("Only one"))
    #expect(!short.string.contains("---"))
}

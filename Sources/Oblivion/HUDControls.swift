import AppKit
import SwiftUI

struct HUDMenuChoice {
    var title: String
    var selected = false
    var action: () -> Void
}

/// Native controls keep cursor and hit-testing reliable in a non-activating HUD.
struct HUDAction: NSViewRepresentable {
    var title = ""
    var symbol: String? = nil
    var label: String
    var hint: String
    var enabled = true
    var choices: [HUDMenuChoice] = []
    var action: () -> Void = {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> HUDControlButton { HUDControlButton(frame: .zero) }
    func updateNSView(_ view: HUDControlButton, context: Context) {
        view.title = title; view.symbol = symbol; view.isEnabled = enabled
        view.toolTip = hint; view.setAccessibilityLabel(label)
        context.coordinator.choices = choices; context.coordinator.action = action
        view.target = context.coordinator; view.action = #selector(Coordinator.pressed(_:))
        view.invalidateIntrinsicContentSize(); view.needsDisplay = true
        view.window?.invalidateCursorRects(for: view)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HUDControlButton, context: Context) -> CGSize? { nsView.intrinsicContentSize }
    final class Coordinator: NSObject {
        var choices: [HUDMenuChoice] = []
        var action: () -> Void = {}
        @objc func pressed(_ sender: NSButton) {
            guard !choices.isEmpty else { action(); return }
            let menu = NSMenu(); menu.autoenablesItems = false
            for (index, choice) in choices.enumerated() {
                let item = NSMenuItem(title: choice.title, action: #selector(choose(_:)), keyEquivalent: "")
                item.target = self; item.tag = index; item.state = choice.selected ? .on : .off; menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 3), in: sender)
        }
        @objc func choose(_ item: NSMenuItem) { if choices.indices.contains(item.tag) { choices[item.tag].action() } }
    }
}

final class HUDControlButton: NSButton {
    var symbol: String?
    private var hovering = false
    private var tracking: NSTrackingArea?
    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false; setButtonType(.momentaryPushIn)
        font = .systemFont(ofSize: 11)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: NSSize {
        let text = (title as NSString).size(withAttributes: [.font: font!]).width
        return NSSize(width: max(26, ceil(text) + (symbol == nil ? 0 : title.isEmpty ? 13 : 18) + 14), height: 27)
    }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func resetCursorRects() { if isEnabled { addCursorRect(bounds, cursor: .pointingHand) } }
    override func cursorUpdate(with event: NSEvent) { (isEnabled ? NSCursor.pointingHand : NSCursor.arrow).set() }
    override func mouseEntered(with event: NSEvent) { hovering = true; cursorUpdate(with: event); needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let active = isEnabled && (hovering || isHighlighted)
        NSColor(white: 1, alpha: active ? (isHighlighted ? 0.16 : 0.09) : 0).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        let color = isEnabled ? (active ? NSColor.labelColor : NSColor.secondaryLabelColor) : NSColor.tertiaryLabelColor
        var x: CGFloat = 7
        if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 11, weight: .regular).applying(.init(paletteColors: [color]))) {
            let size = image.size
            image.draw(in: NSRect(x: x, y: (bounds.height - size.height) / 2, width: size.width, height: size.height))
            x += title.isEmpty ? 13 : 18
        }
        if !title.isEmpty {
            let text = NSAttributedString(string: title, attributes: [.font: font!, .foregroundColor: color])
            text.draw(at: NSPoint(x: x, y: (bounds.height - text.size().height) / 2))
        }
    }
}

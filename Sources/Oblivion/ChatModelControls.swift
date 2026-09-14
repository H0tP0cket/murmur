import SwiftUI
import AppKit

/// Observe the catalog directly; it loads independently of the conversation.
struct ChatModelControls: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var service: CodexService
    @AppStorage("prepModel") private var defaultModel = ""
    @AppStorage("prepEffort") private var defaultEffort = ""

    private var modelID: String? {
        if let saved = state.selected?.prepModel { return saved }
        if service.models.contains(where: { $0.id == defaultModel }) { return defaultModel }
        return service.model(live: false)
    }
    private var option: ModelOption? { service.models.first { $0.id == modelID } }
    private var explicitModel: String? {
        if let call = state.selected { return call.prepModel }
        return defaultModel.isEmpty ? nil : defaultModel
    }
    private var effort: String? {
        let preference = state.selected == nil ? defaultEffort : state.selected?.prepEffort
        return try? service.turnSelection(modelOverride: modelID, effortOverride: preference).effort
    }
    private func effortName(_ value: String) -> String {
        ["xhigh": "Extra high", "none": "None"][value] ?? value.capitalized
    }

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            ChatChoiceControl(title: option?.name ?? (modelID == nil ? "Connecting…" : "Model unavailable"),
                              accessibilityLabel: "Chat model", enabled: !state.isBusy && !service.models.isEmpty,
                              choices: [ChatChoice(title: "Automatic", selected: explicitModel == nil, action: { setModel(nil) })]
                                + service.models.map { model in ChatChoice(title: model.name, selected: model.id == explicitModel, action: { setModel(model.id) }) })
            if let option, !option.efforts.isEmpty {
                ChatChoiceControl(title: effortName(effort ?? option.defaultEffort), accessibilityLabel: "Reasoning effort", enabled: !state.isBusy,
                                  choices: option.efforts.map { value in ChatChoice(title: effortName(value), selected: value == effort, action: { setEffort(value) }) })
            }
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setModel(_ model: String?) {
        if let id = state.selectedID { state.setChatModel(model, callID: id) }
        else { defaultModel = model ?? ""; defaultEffort = "" }
    }
    private func setEffort(_ effort: String) {
        if let id = state.selectedID { state.modify(id) { $0.prepEffort = effort } }
        else { defaultEffort = effort }
    }
}


struct ChatChoice {
    var title: String
    var selected: Bool
    var action: () -> Void
}

/// Native menu tracking exposes open/close state for clear feedback, including
/// Escape and outside-click dismissal. No second SwiftUI menu indicator.
struct ChatChoiceControl: NSViewRepresentable {
    var title: String
    var accessibilityLabel: String
    var enabled: Bool
    var choices: [ChatChoice]
    func makeNSView(context: Context) -> ChatChoiceButton { ChatChoiceButton(frame: .zero) }
    func updateNSView(_ button: ChatChoiceButton, context: Context) {
        button.title = title; button.choices = choices; button.isEnabled = enabled
        button.setAccessibilityLabel(accessibilityLabel); button.setAccessibilityValue(title)
        button.toolTip = accessibilityLabel
        button.invalidateIntrinsicContentSize(); button.needsDisplay = true
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ChatChoiceButton, context: Context) -> CGSize? { nsView.intrinsicContentSize }
}

final class ChatChoiceButton: NSButton, NSMenuDelegate {
    var choices: [ChatChoice] = []
    private(set) var menuIsOpen = false
    private var hovering = false
    private var tracking: NSTrackingArea?
    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false; font = .systemFont(ofSize: 11, weight: .medium)
        setButtonType(.momentaryPushIn); target = self; action = #selector(showChoices)
        setAccessibilityRole(.popUpButton)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil((title as NSString).size(withAttributes: [.font: font!]).width) + 33, height: 28)
    }
    @objc private func showChoices() {
        guard isEnabled else { return }
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false
        for (index, choice) in choices.enumerated() {
            let item = NSMenuItem(title: choice.title, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self; item.tag = index; item.state = choice.selected ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: isFlipped ? bounds.maxY + 3 : -3), in: self)
    }
    @objc private func choose(_ sender: NSMenuItem) { if choices.indices.contains(sender.tag) { choices[sender.tag].action() } }
    func menuWillOpen(_ menu: NSMenu) { menuIsOpen = true; needsDisplay = true; displayIfNeeded() }
    func menuDidClose(_ menu: NSMenu) { menuIsOpen = false; hovering = false; needsDisplay = true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func resetCursorRects() { if isEnabled { addCursorRect(bounds, cursor: .pointingHand) } }
    override func cursorUpdate(with event: NSEvent) { if isEnabled { NSCursor.pointingHand.set() } }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let active = isEnabled && (hovering || menuIsOpen || isHighlighted)
        let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 1.5), xRadius: 7, yRadius: 7)
        NSColor(white: 1, alpha: active ? 0.10 : 0.025).setFill(); pill.fill()
        if active { NSColor(white: 1, alpha: 0.12).setStroke(); pill.lineWidth = 0.5; pill.stroke() }
        let color = isEnabled ? (active ? NSColor.labelColor : NSColor.secondaryLabelColor) : NSColor.tertiaryLabelColor
        let label = NSAttributedString(string: title, attributes: [.font: font!, .foregroundColor: color])
        label.draw(at: NSPoint(x: 9, y: (bounds.height - label.size().height) / 2))
        let direction: CGFloat = (isFlipped ? 1 : -1) * (menuIsOpen ? -1 : 1)
        let x = bounds.maxX - 16, y = bounds.midY
        let chevron = NSBezierPath()
        chevron.move(to: NSPoint(x: x, y: y - 1.5 * direction))
        chevron.line(to: NSPoint(x: x + 3, y: y + 1.5 * direction))
        chevron.line(to: NSPoint(x: x + 6, y: y - 1.5 * direction))
        color.setStroke(); chevron.lineWidth = 1.2; chevron.lineCapStyle = .round; chevron.lineJoinStyle = .round; chevron.stroke()
    }
}

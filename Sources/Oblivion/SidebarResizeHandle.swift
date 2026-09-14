import SwiftUI
import AppKit

struct SidebarResizeHandle: View {
    @Binding var width: CGFloat
    var maximum: CGFloat
    @State private var startWidth: CGFloat?
    @State private var hovering = false
    var body: some View {
        Rectangle().fill(.primary.opacity(hovering ? 0.18 : 0.07)).frame(width: 1)
            .frame(width: 8).contentShape(Rectangle())
            .onHover { value in
                guard value != hovering else { return }
                hovering = value
                if value { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                if startWidth == nil { startWidth = min(width, maximum) }
                width = min(maximum, max(300, startWidth! - value.translation.width))
            }.onEnded { _ in startWidth = nil })
            .onTapGesture(count: 2) { width = min(360, maximum) }
            .help("Drag to resize. Double-click to reset.")
            .accessibilityLabel("Resize notes and cue cards")
            .accessibilityAdjustableAction { direction in
                width = min(maximum, max(300, width + (direction == .increment ? 40 : -40)))
            }
            .onDisappear { if hovering { NSCursor.pop(); hovering = false } }
    }
}

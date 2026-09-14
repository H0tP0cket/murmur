import SwiftUI
import AppKit

/// A restrained divider matching the chat sidebar, without NSSplitView's bezel.
struct NotesSplitView<Top: View, Bottom: View>: View {
    let expanded: Bool
    @ViewBuilder var top: () -> Top
    @ViewBuilder var bottom: () -> Bottom
    @State private var fraction: CGFloat = 0.58
    @State private var dragStart: CGFloat?
    @State private var hovering = false

    var body: some View {
        GeometryReader { geometry in
            let available = max(0, geometry.size.height - 9)
            let topHeight = expanded ? min(max(120, available * fraction), max(120, available - 150)) : max(0, available - 46)
            VStack(spacing: 0) {
                top().frame(height: topHeight).clipped()
                Rectangle().fill(.primary.opacity(hovering && expanded ? 0.18 : 0.07)).frame(height: 1)
                    .frame(height: 9).frame(maxWidth: .infinity).background(OblivionStyle.canvas).contentShape(Rectangle())
                    .onHover { value in
                        guard expanded, hovering != value else { return }
                        hovering = value
                        if value { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                    }
                    .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                        guard expanded, available > 0 else { return }
                        if dragStart == nil { dragStart = topHeight }
                        fraction = min(0.8, max(0.2, (dragStart! + value.translation.height) / available))
                    }.onEnded { _ in dragStart = nil })
                    .accessibilityLabel("Resize personal and AI notes")
                    .accessibilityAdjustableAction { direction in fraction = min(0.8, max(0.2, fraction + (direction == .increment ? 0.1 : -0.1))) }
                bottom().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).clipped()
            }
        }.onDisappear { if hovering { NSCursor.pop(); hovering = false } }
            .onChange(of: expanded) { _, _ in if hovering { NSCursor.pop(); hovering = false } }
    }
}

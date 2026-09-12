import SwiftUI
import AppKit

enum OblivionStyle {
    // Neutral surfaces sampled from the supplied Codex reference.
    static let canvas = Color(red: 24 / 255, green: 24 / 255, blue: 24 / 255)
    static let sidebar = Color(red: 40 / 255, green: 40 / 255, blue: 40 / 255)
    static let raised = Color(red: 42 / 255, green: 42 / 255, blue: 42 / 255)
    static let accent = Color(white: 0.92)
    static let windowColor = NSColor(srgbRed: 24 / 255, green: 24 / 255, blue: 24 / 255, alpha: 1)
}

struct OblivionMark: View {
    var size: CGFloat = 32
    var body: some View {
        LogoShape().fill(.primary).frame(width: size, height: size).accessibilityHidden(true)
    }
}

private struct LogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(LogoGeometry.path).applying(CGAffineTransform(scaleX: rect.width / 256, y: rect.height / 256).concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}

struct QuietButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.primary.opacity(hovering ? 0.055 : 0), in: RoundedRectangle(cornerRadius: 9))
            .opacity(configuration.isPressed ? 0.65 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: hovering)
            .onHover { hovering = $0 }
    }
}

struct SidebarSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        Group {
            if reduceTransparency { OblivionStyle.sidebar }
            else { SidebarGlass().overlay(OblivionStyle.canvas.opacity(0.6)) }
        }.allowsHitTesting(false)
    }
}

/// Behind-window material lets the desktop softly show through the sidebar,
/// while the reading surfaces stay a consistent charcoal.
private struct SidebarGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

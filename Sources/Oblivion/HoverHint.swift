import SwiftUI

extension View {
    func hoverHint(_ title: String) -> some View { modifier(HoverHint(title: title)) }
}

private struct HoverHint: ViewModifier {
    var title: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    @State private var reveal: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if visible {
                    Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.primary)
                        .padding(.horizontal, 9).padding(.vertical, 6).fixedSize()
                        .background(OblivionStyle.raised, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.12), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                        .offset(y: 36).allowsHitTesting(false).accessibilityHidden(true)
                        .transition(.opacity)
                }
            }
            .onHover { inside in
                dismiss()
                guard inside else { return }
                reveal = Task {
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { visible = true }
                }
            }
            .simultaneousGesture(TapGesture().onEnded { dismiss() })
            .onDisappear { dismiss() }
    }

    private func dismiss() { reveal?.cancel(); reveal = nil; visible = false }
}

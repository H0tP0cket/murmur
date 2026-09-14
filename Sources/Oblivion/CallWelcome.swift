import SwiftUI

struct CallWelcome: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        Text("Let’s prep your call.")
            .font(.system(size: 27, weight: .medium)).tracking(-0.4)
            .opacity(appeared ? 1 : 0).offset(y: appeared || reduceMotion ? 0 : 8)
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) { appeared = true } }
    }
}

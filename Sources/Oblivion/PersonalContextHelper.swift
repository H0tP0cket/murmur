import SwiftUI
import AppKit

struct PersonalContextHelper: View {
    @State private var expanded = false
    @State private var copied = false
    @State private var feedbackTask: Task<Void, Never>?
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Paste this prompt into ChatGPT, then paste its summary into your personal context above.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text(Prompts.personalContext).font(.system(size: 12)).lineSpacing(3).textSelection(.enabled)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                HStack {
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        copied = NSPasteboard.general.setString(Prompts.personalContext, forType: .string)
                        feedbackTask?.cancel()
                        feedbackTask = Task {
                            do { try await Task.sleep(for: .seconds(2)) } catch { return }
                            copied = false
                        }
                    } label: {
                        Label(copied ? "Copied" : "Copy prompt", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }.buttonStyle(.bordered).controlSize(.small).font(.system(size: 11)).accessibilityLabel("Copy personal context prompt")
                }
            }.padding(.top, 8)
        } label: {
            Text("Build your context with ChatGPT").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .onDisappear { feedbackTask?.cancel() }
    }
}

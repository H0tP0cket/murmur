import SwiftUI

/// Edits stay local until Return or focus loss, avoiding library writes on
/// every keystroke. Identity is the call ID so drafts cannot rename another call.
struct EditableCallTitle: View {
    var title: String
    var requestFocus: Bool
    var didFocus: () -> Void
    var save: (String) -> Void
    @State private var draft: String
    @State private var lastSaved: String
    @State private var hovering = false
    @State private var editing = false
    @FocusState private var focused: Bool

    init(title: String, requestFocus: Bool, didFocus: @escaping () -> Void, save: @escaping (String) -> Void) {
        self.title = title; self.requestFocus = requestFocus; self.didFocus = didFocus; self.save = save
        _draft = State(initialValue: title); _lastSaved = State(initialValue: title)
    }

    var body: some View {
        Group {
            if editing {
                TextField("Call name", text: $draft).textFieldStyle(.plain).focused($focused)
                    .task { try? await Task.sleep(for: .milliseconds(50)); if !Task.isCancelled { focused = true } }
            } else {
                Button { beginEditing() } label: {
                    Text(draft).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
            .font(.system(size: 14, weight: .medium)).lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 5)
            .background(.primary.opacity(focused ? 0.055 : hovering ? 0.025 : 0), in: RoundedRectangle(cornerRadius: 6))
            .onHover { hovering = $0 }
            .help("Edit call name").accessibilityLabel("Call name")
            .onSubmit { commit(); editing = false; focused = false }
            .onExitCommand { draft = title; lastSaved = title; editing = false; focused = false }
            .onChange(of: focused) { _, value in
                if !value && editing { commit(); editing = false }
            }
            .onChange(of: title) { _, value in
                lastSaved = value
                if !editing { draft = value }
            }
            .onChange(of: requestFocus) { _, value in if value { beginEditing() } }
            .onAppear { if requestFocus { beginEditing() } }
            .onDisappear { if editing { commit() } }
    }

    private func beginEditing() { draft = title; editing = true; didFocus() }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? "Untitled call" : trimmed
        draft = value
        guard value != lastSaved else { return }
        lastSaved = value
        save(value)
    }
}

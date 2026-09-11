import SwiftUI
import AppKit

struct MainView: View {
    @EnvironmentObject var state: AppState
    @State private var sidebarVisible = true
    @State private var renameID: UUID?
    @State private var renameText = ""
    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible { sidebar.frame(width: 228); Divider() }
            VStack(spacing: 0) {
                header
                if let message = state.error { errorBanner(message) }
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        if let call = state.selected { conversation(call) } else { welcome }
                        composer
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if let detail = state.detail, state.selected != nil { Divider(); DetailView(detail: detail).frame(width: 340) }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .sheet(isPresented: $state.showCallSetup) { CallSetupView().environmentObject(state) }
        .sheet(isPresented: $state.showSettings) { SettingsView().environmentObject(state) }
        .sheet(item: $state.editingStory) { story in StoryEditor(story: story).environmentObject(state) }
        .alert("Rename call", isPresented: Binding(get: { renameID != nil }, set: { if !$0 { renameID = nil } })) {
            TextField("Call name", text: $renameText)
            Button("Save") { if let id = renameID { state.modify(id) { $0.title = renameText.isEmpty ? "Untitled call" : renameText } }; renameID = nil }
            Button("Cancel", role: .cancel) { renameID = nil }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("Oblivion").font(.system(size: 16, weight: .semibold)); Spacer(); Image(systemName: "waveform").foregroundStyle(.secondary) }.padding(.top, 43).padding(.horizontal, 20).padding(.bottom, 22)
            Button { state.newCall() } label: { Label("New call", systemImage: "square.and.pencil").font(.system(size: 14, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading).padding(11).background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10)) }
                .buttonStyle(.plain).padding(.horizontal, 12).accessibilityIdentifier("newCall")
            HStack(spacing: 7) { Image(systemName: "magnifyingglass"); TextField("Search calls", text: $state.sidebarSearch).textFieldStyle(.plain) }.font(.system(size: 12)).foregroundStyle(.secondary).padding(10).padding(.horizontal, 9).padding(.top, 9)
            HStack { Text(state.showArchived ? "ARCHIVED" : "RECENT").font(.system(size: 10, weight: .semibold)).tracking(1); Spacer() }.foregroundStyle(.tertiary).padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 9)
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(state.visibleCalls) { call in
                        CallRow(call: call, selected: call.id == state.selectedID, active: call.id == state.activeCallID, select: { state.selectedID = call.id }, transcript: { state.selectedID = call.id; state.detail = .transcript }, rename: { renameID = call.id; renameText = call.title }, archive: { state.archive(call.id) })
                    }
                }.padding(.horizontal, 10)
            }
            Spacer(minLength: 6)
            if let active = state.activeCall { Button { state.selectedID = active.id; state.windows.showHUD() } label: { Label("Call in progress", systemImage: "waveform").font(.system(size: 12, weight: .medium)).foregroundStyle(.green).padding(12) }.buttonStyle(.plain) }
            HStack {
                Button { state.showSettings = true } label: { Image(systemName: "gearshape").padding(8) }.buttonStyle(.plain).help("Settings")
                Spacer()
                Button { state.showArchived.toggle() } label: { Image(systemName: state.showArchived ? "bubble.left.and.bubble.right" : "archivebox").padding(8) }.buttonStyle(.plain).help(state.showArchived ? "Recent calls" : "Archived calls")
            }.foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 13)
        }.background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { sidebarVisible.toggle() } } label: { Image(systemName: "sidebar.left") }.buttonStyle(.plain).foregroundStyle(.secondary).help("Toggle sidebar")
            Text(state.selected?.title ?? "Oblivion").font(.system(size: 14, weight: .medium)).lineLimit(1)
            Spacer(minLength: 8)
            if state.selected != nil {
                Button { withAnimation { state.detail = state.detail == .notes ? nil : .notes } } label: { Image(systemName: "note.text") }.buttonStyle(.plain).help("Notes")
                Button { withAnimation { state.detail = state.detail == .stories ? nil : .stories } } label: { Image(systemName: "rectangle.stack") }.buttonStyle(.plain).help("Prepared answers")
                if state.activeCallID != nil { Button("End call") { Task { await state.endCall() } }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(state.callEnding) }
                Button { if state.activeCallID != nil { state.windows.showHUD() } else { state.showCallSetup = true } } label: {
                    Label(state.callStarting ? "Starting…" : state.activeCallID == nil ? "Start call" : "Pop out", systemImage: "arrow.up.right")
                        .font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 8).background(.primary.opacity(0.065), in: Capsule())
                }.buttonStyle(.plain).disabled(state.callStarting || state.callEnding)
            }
        }.padding(.horizontal, 22).frame(height: 66)
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "waveform").font(.system(size: 30, weight: .light)).frame(width: 68, height: 68).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 22)).padding(.bottom, 8)
            Text("A little preparation.\nA better conversation.").font(.system(size: 29, weight: .medium)).multilineTextAlignment(.center)
            Text("Talk through your next call. Bring your context,\nyour questions, and what you want to accomplish.").font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            HStack(spacing: 8) {
                starter("Prepare for an interview", icon: "person.crop.rectangle")
                starter("Plan a discovery call", icon: "bubble.left.and.bubble.right")
            }.padding(.top, 15)
            Spacer(); Spacer().frame(height: 15)
        }.frame(maxWidth: .infinity)
    }

    private func starter(_ title: String, icon: String) -> some View {
        Button { state.newCall(); state.composer = title == "Prepare for an interview" ? "I’m preparing for an interview. " : "I’m planning a discovery call. " } label: {
            Label(title, systemImage: icon).font(.system(size: 12)).padding(.horizontal, 13).padding(.vertical, 11).overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.12)))
        }.buttonStyle(.plain)
    }

    private func conversation(_ call: CallRecord) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(call.messages) { message in MessageRow(message: message, save: { state.editingStory = PreparedStory(title: "Prepared answer", body: message.text) }) }
                    if state.isBusy { HStack(spacing: 8) { ProgressView().controlSize(.mini); Text(state.chatStatus).font(.system(size: 12)).foregroundStyle(.secondary) } }
                    Color.clear.frame(height: 1).id("bottom")
                }.frame(maxWidth: 760).padding(.horizontal, 35).padding(.top, 22).padding(.bottom, 20).frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: call.messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            .id(call.id)
        }
    }

    private var composer: some View {
        VStack(spacing: 9) {
            if let call = state.selected, !call.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(call.attachments) { attachment in
                        HStack(spacing: 6) { Image(systemName: "doc.text"); Text(attachment.name).lineLimit(1); Button { state.modify(call.id) { $0.attachments.removeAll { $0.id == attachment.id } } } label: { Image(systemName: "xmark").font(.system(size: 8)) }.buttonStyle(.plain).help("Remove from context") }
                            .font(.system(size: 11)).padding(8).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    } }
                }
            }
            VStack(spacing: 6) {
                ZStack(alignment: .topLeading) {
                    if state.composer.isEmpty { Text("Add context, ask a question, or paste a link…").font(.system(size: 14)).foregroundStyle(.tertiary).padding(.top, 10).padding(.leading, 5).allowsHitTesting(false) }
                    ComposerEditor(text: $state.composer, onSubmit: { state.send() }).frame(minHeight: 55, maxHeight: 100)
                }
                HStack {
                    Button { state.chooseAttachment() } label: { Image(systemName: "plus").font(.system(size: 17)).frame(width: 27, height: 27) }.buttonStyle(.plain).help("Attach PDF or text")
                    Spacer()
                    Text("Codex").font(.system(size: 11)).foregroundStyle(.tertiary)
                    Button { if state.isBusy { state.cancelChat() } else { state.send() } } label: {
                        Image(systemName: state.isBusy ? "stop.fill" : "arrow.up").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(nsColor: .textBackgroundColor)).frame(width: 31, height: 31).background(.primary, in: Circle())
                    }.buttonStyle(.plain).disabled(!state.isBusy && state.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel(state.isBusy ? "Stop response" : "Send message")
                }
            }.padding(13).background(Color(nsColor: .windowBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 23)).overlay(RoundedRectangle(cornerRadius: 23).stroke(.primary.opacity(0.09)))
            Text(state.activeCallID == nil ? "Your context, ready when you need it." : "Listening continues while you’re in the chat.").font(.system(size: 10)).foregroundStyle(.tertiary)
        }.frame(maxWidth: 760).padding(.horizontal, 30).padding(.bottom, 18).padding(.top, 10).frame(maxWidth: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) { Image(systemName: "exclamationmark.circle"); Text(message).textSelection(.enabled); Spacer(); Button { state.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
            .font(.system(size: 12)).padding(13).background(Color.orange.opacity(0.09)).padding(.horizontal, 22).padding(.bottom, 8)
    }
}

struct CallRow: View {
    var call: CallRecord
    var selected: Bool
    var active: Bool
    var select: () -> Void
    var transcript: () -> Void
    var rename: () -> Void
    var archive: () -> Void
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 5) {
            if active { Circle().fill(.green).frame(width: 5, height: 5) }
            Text(call.title).font(.system(size: 13)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            if hovering || selected {
                Button(action: transcript) { Image(systemName: "doc.text").font(.system(size: 11)) }.buttonStyle(.plain).help("View transcript")
                Menu { Button("Rename", action: rename); Button(call.archived ? "Restore" : "Archive", action: archive) } label: { Image(systemName: "ellipsis").font(.system(size: 12)) }.menuStyle(.borderlessButton).fixedSize().frame(width: 18)
            }
        }.padding(.horizontal, 10).padding(.vertical, 11).background(selected ? Color.primary.opacity(0.075) : hovering ? Color.primary.opacity(0.035) : Color.clear, in: RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle()).onTapGesture(perform: select).onHover { hovering = $0 }
            .contextMenu { Button("View transcript", action: transcript); Button("Rename", action: rename); Button(call.archived ? "Restore" : "Archive", action: archive) }
            .accessibilityElement(children: .contain).accessibilityLabel(call.title)
    }
}

struct MessageRow: View {
    var message: ChatMessage
    var save: () -> Void
    var body: some View {
        VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 9) {
            if message.role == "system" { Label(message.text, systemImage: "checkmark.circle").font(.system(size: 12)).foregroundStyle(.secondary) }
            else {
                HStack(alignment: .top) {
                    if message.role == "user" { Spacer(minLength: 50) }
                    Text(.init(message.text.isEmpty ? " " : message.text)).font(.system(size: 15)).lineSpacing(6).textSelection(.enabled)
                        .padding(message.role == "user" ? 15 : 0)
                        .background(message.role == "user" ? Color.primary.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 20))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if message.role != "user" { Spacer(minLength: 0) }
                }
                if message.role == "assistant", !message.text.isEmpty {
                    HStack(spacing: 14) {
                        Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string) } label: { Image(systemName: "doc.on.doc") }.help("Copy response")
                        Button(action: save) { Label("Save answer", systemImage: "rectangle.stack.badge.plus") }
                        if message.interrupted { Text("Stopped").foregroundStyle(.tertiary) }
                    }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ComposerEditor: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        let editor = SubmitTextView(); editor.isRichText = false; editor.drawsBackground = false; editor.font = .systemFont(ofSize: 14); editor.textColor = .labelColor; editor.insertionPointColor = .labelColor
        editor.textContainerInset = NSSize(width: 0, height: 8); editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator; editor.onSubmit = onSubmit; editor.setAccessibilityLabel("Message")
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? SubmitTextView else { return }
        editor.onSubmit = onSubmit
        if editor.string != text { editor.string = text }
    }
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerEditor
        init(_ parent: ComposerEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) { if let view = notification.object as? NSTextView { parent.text = view.string } }
    }
}

final class SubmitTextView: NSTextView {
    var onSubmit: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 && !event.modifierFlags.contains(.shift) && !hasMarkedText() { onSubmit?() }
        else { super.keyDown(with: event) }
    }
}

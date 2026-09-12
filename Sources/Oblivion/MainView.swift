import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO

struct MainView: View {
    @EnvironmentObject var state: AppState
    @State private var sidebarVisible = true
    @State private var renameID: UUID?
    @State private var renameText = ""
    @State private var followChat = true
    @State private var composerHeight: CGFloat = 32
    @State private var composerFocused = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible { sidebar.frame(width: 224) }
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
            .background(OblivionStyle.canvas)
        }
        .ignoresSafeArea(.container, edges: .top)
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
            HStack(spacing: 10) { OblivionMark(size: 27); Text("Oblivion").font(.system(size: 16, weight: .semibold)).tracking(-0.3); Spacer() }.padding(.top, 39).padding(.horizontal, 19).padding(.bottom, 21)
            Button { state.newCall() } label: {
                HStack { Label("New call", systemImage: "square.and.pencil"); Spacer(); Text("⌘N").font(.system(size: 10)).foregroundStyle(.tertiary) }
                    .font(.system(size: 13, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 11)
                    .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(.primary.opacity(0.055), lineWidth: 0.5))
            }.buttonStyle(QuietButtonStyle()).padding(.horizontal, 12).accessibilityIdentifier("newCall")
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
            if let active = state.activeCall { Button { state.selectedID = active.id; state.windows.showHUD() } label: { Label(state.callStarting ? "Preparing audio…" : "Call in progress", systemImage: "waveform").font(.system(size: 12, weight: .medium)).foregroundStyle(.green).padding(12) }.buttonStyle(.plain) }
            HStack {
                Button { state.showSettings = true } label: { Image(systemName: "gearshape").padding(8) }.buttonStyle(.plain).help("Settings")
                Spacer()
                Button { state.showArchived.toggle() } label: { Image(systemName: state.showArchived ? "bubble.left.and.bubble.right" : "archivebox").padding(8) }.buttonStyle(.plain).help(state.showArchived ? "Recent calls" : "Archived calls")
            }.foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 13)
        }.background(SidebarSurface())
            .overlay(alignment: .trailing) { Rectangle().fill(.primary.opacity(0.055)).frame(width: 0.5) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { sidebarVisible.toggle() } } label: { Image(systemName: "sidebar.left") }.buttonStyle(.plain).foregroundStyle(.secondary).help("Toggle sidebar")
            Text(state.selected?.title ?? "Oblivion").font(.system(size: 14, weight: .medium)).lineLimit(1)
            Spacer(minLength: 8)
            if state.selected != nil {
                HStack(spacing: 2) {
                    Button { withAnimation(.easeInOut(duration: 0.2)) { state.detail = state.detail == .notes ? nil : .notes } } label: { Image(systemName: "note.text").frame(width: 30, height: 30).foregroundStyle(state.detail == .notes ? Color.primary : Color.secondary) }.help("Notes")
                    Button { withAnimation(.easeInOut(duration: 0.2)) { state.detail = state.detail == .stories ? nil : .stories } } label: { Image(systemName: "rectangle.stack").frame(width: 30, height: 30).foregroundStyle(state.detail == .stories ? Color.primary : Color.secondary) }.help("Prepared answers")
                }.buttonStyle(QuietButtonStyle())
                if state.activeCallID != nil { Button("End call") { Task { await state.endCall() } }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(state.callEnding) }
                Button { if state.activeCallID != nil { state.windows.showHUD() } else { state.showCallSetup = true } } label: {
                    Label(state.callStarting ? "Starting…" : state.activeCallID == nil ? "Start call" : "Pop out", systemImage: "arrow.up.right")
                        .font(.system(size: 12, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 9)
                        .glassEffect(.regular.interactive(), in: Capsule())
                }.buttonStyle(.plain).disabled(state.callStarting || state.callEnding)
            }
        }.padding(.horizontal, 22).frame(height: 66)
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Spacer()
            OblivionMark(size: 62).padding(.bottom, 8)
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
                VStack(alignment: .leading, spacing: 28) {
                    if call.messages.count == 1, call.messages.first?.role == "assistant" {
                        VStack(alignment: .leading, spacing: 18) {
                            OblivionMark(size: 48)
                            Text("Let’s get you ready.").font(.system(size: 30, weight: .semibold)).tracking(-0.8)
                        }.padding(.top, 60).padding(.bottom, 2)
                    }
                    ForEach(call.messages) { message in MessageRow(message: message, callID: call.id, showActions: call.messages.count > 1, save: { state.editingStory = PreparedStory(title: "Prepared answer", body: message.text) }) }
                    if state.isBusy { HStack(spacing: 8) { Image(systemName: "sparkle").foregroundStyle(.secondary).symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion); Text(state.chatStatus).font(.system(size: 12)).foregroundStyle(.secondary) } }
                    Color.clear.frame(height: 1).id("bottom")
                }.frame(maxWidth: 760).padding(.horizontal, 35).padding(.top, 22).padding(.bottom, 20).frame(maxWidth: .infinity)
            }
            .onScrollPhaseChange { _, phase in if phase == .interacting { followChat = false } }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 25
            } action: { _, atBottom in if atBottom { followChat = true } }
            .onChange(of: call.messages.count) { _, _ in followChat = true; proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: call.messages.last?.text) { _, _ in if followChat { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            .id(call.id)
        }
    }

    private var composer: some View {
        VStack(spacing: 9) {
            if let call = state.selected, !call.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(call.attachments) { attachment in
                        HStack(spacing: 6) {
                            if attachment.isImage { ImageAttachmentView(url: state.library.imageURL(attachment, callID: call.id), name: attachment.name, size: 30) }
                            else { Image(systemName: "doc.text") }
                            Text(attachment.name).lineLimit(1).frame(maxWidth: 150)
                            Button { state.modify(call.id) { $0.attachments.removeAll { $0.id == attachment.id } } } label: { Image(systemName: "xmark").font(.system(size: 8)) }.buttonStyle(.plain).help("Remove from context").accessibilityLabel("Remove \(attachment.name) from context")
                        }
                            .font(.system(size: 11)).padding(8).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    } }
                }.frame(height: call.attachments.contains(where: \.isImage) ? 50 : 36)
            }
            HStack(alignment: .bottom, spacing: 9) {
                Button { state.chooseAttachment() } label: { Image(systemName: "plus").font(.system(size: 17, weight: .regular)).foregroundStyle(.secondary).frame(width: 32, height: 32) }.buttonStyle(QuietButtonStyle()).help("Attach images, PDFs, or text")
                ZStack(alignment: .topLeading) {
                    if state.composer.isEmpty { Text("Ask anything, or add context…").font(.system(size: 14)).foregroundStyle(.secondary.opacity(0.7)).padding(.top, 7).padding(.leading, 5).allowsHitTesting(false) }
                    ComposerEditor(text: $state.composer, height: $composerHeight, focused: $composerFocused, onSubmit: { state.send() }, onImage: state.attachImage, onFiles: { state.attachFiles($0) }).frame(height: composerHeight)
                }
                Button { if state.isBusy { state.cancelChat() } else { state.send() } } label: {
                    Image(systemName: state.isBusy ? "stop.fill" : "arrow.up").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.black).frame(width: 32, height: 32)
                        .background(OblivionStyle.accent, in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                }.buttonStyle(.plain).opacity(state.isBusy || state.canSend ? 1 : 0.3)
                    .disabled(!state.isBusy && !state.canSend).accessibilityLabel(state.isBusy ? "Stop response" : "Send message").help("Send with Codex · Return")
            }.padding(10)
                .background(OblivionStyle.raised, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(composerFocused ? 0.18 : 0.07), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.10), radius: 16, y: 7)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: composerFocused)
            if state.activeCallID != nil { CaptureStatusCaption(audio: state.audio, active: true, starting: state.callStarting, ending: state.callEnding) }
        }.frame(maxWidth: 760).padding(.horizontal, 30).padding(.bottom, 24).padding(.top, 12).frame(maxWidth: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) { Image(systemName: "exclamationmark.circle"); Text(message).textSelection(.enabled); Spacer(); Button { state.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
            .font(.system(size: 12)).padding(13).background(Color.orange.opacity(0.09)).padding(.horizontal, 22).padding(.bottom, 8)
    }
}

private struct CaptureStatusCaption: View {
    @ObservedObject var audio: AudioCapture
    var active: Bool
    var starting: Bool
    var ending: Bool
    var body: some View {
        Text(ending ? "Finishing your transcript…" : starting ? "Waiting for audio setup…" : !active ? "Your context, ready when you need it." : audio.isRunning ? "Listening continues while you’re in the chat." : "Audio interrupted. End and restart the call to resume.")
            .font(.system(size: 10)).foregroundStyle(.tertiary)
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
                Menu { Button("Rename", action: rename); Button(call.archived ? "Restore" : "Archive", action: archive) } label: { Image(systemName: "ellipsis").font(.system(size: 12)) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 18)
            }
        }.padding(.horizontal, 10).padding(.vertical, 11)
            .background(selected ? Color.white.opacity(0.075) : hovering ? Color.white.opacity(0.035) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.white.opacity(0.045) : .clear, lineWidth: 0.5))
            .contentShape(Rectangle()).onTapGesture(perform: select).onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
            .contextMenu { Button("View transcript", action: transcript); Button("Rename", action: rename); Button(call.archived ? "Restore" : "Archive", action: archive) }
            .accessibilityElement(children: .contain).accessibilityLabel(call.title)
    }
}

struct MessageRow: View {
    @EnvironmentObject private var state: AppState
    var message: ChatMessage
    var callID: UUID
    var showActions = true
    var save: () -> Void
    var body: some View {
        VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 9) {
            if message.role == "system" { Label(message.text, systemImage: "checkmark.circle").font(.system(size: 12)).foregroundStyle(.secondary) }
            else {
                if let images = message.images, !images.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(images) { attachment in
                            ImageAttachmentView(url: state.library.imageURL(attachment, callID: callID), name: attachment.name, size: 112)
                        } }
                    }.frame(height: 116)
                }
                HStack(alignment: .top) {
                    if message.role == "user" { Spacer(minLength: 50) }
                    Group {
                        if message.role == "user" { Text(message.text).font(.system(size: 15)).lineSpacing(6).textSelection(.enabled).padding(15).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 20)) }
                        else { MarkdownBody(text: message.text.isEmpty ? " " : message.text) }
                    }.frame(maxWidth: .infinity, alignment: message.role == "user" ? .trailing : .leading)
                    if message.role != "user" { Spacer(minLength: 0) }
                }
                if showActions, message.role == "assistant", !message.text.isEmpty {
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
    @Binding var height: CGFloat
    @Binding var focused: Bool
    var onSubmit: () -> Void
    var onImage: (Data) -> Void
    var onFiles: ([URL]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let editor = SubmitTextView(); editor.isRichText = false; editor.drawsBackground = false; editor.font = .systemFont(ofSize: 14); editor.textColor = .labelColor; editor.insertionPointColor = .labelColor
        editor.textContainerInset = NSSize(width: 0, height: 6); editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize.height = .greatestFiniteMagnitude
        editor.delegate = context.coordinator; editor.onSubmit = onSubmit; editor.setAccessibilityLabel("Message")
        editor.onImage = onImage; editor.onFiles = onFiles
        editor.onLayout = { [weak coordinator = context.coordinator, weak editor] in if let editor { coordinator?.measure(editor) } }
        editor.onFocus = { [weak coordinator = context.coordinator] focus in coordinator?.parent.focused = focus }
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? SubmitTextView else { return }
        editor.appearance = NSAppearance(named: .darkAqua)
        editor.onSubmit = onSubmit
        editor.onImage = onImage; editor.onFiles = onFiles
        if editor.string != text { editor.string = text }
        context.coordinator.measure(editor)
    }
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerEditor
        private var measurementScheduled = false
        init(_ parent: ComposerEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) { if let view = notification.object as? NSTextView { parent.text = view.string; measure(view) } }
        func measure(_ editor: NSTextView) {
            guard !measurementScheduled else { return }
            measurementScheduled = true
            // Measure the laid-out text, including wrapping, outside SwiftUI's
            // update pass. A bounded, change-only write avoids layout feedback.
            DispatchQueue.main.async { [weak self, weak editor] in
                guard let self else { return }
                measurementScheduled = false
                guard let editor, editor.bounds.width > 1, let container = editor.textContainer, let layout = editor.layoutManager else { return }
                layout.ensureLayout(for: container)
                let natural = ceil(layout.usedRect(for: container).height + editor.textContainerInset.height * 2)
                let next = min(132, max(32, natural))
                if abs(parent.height - next) > 0.5 { parent.height = next }
            }
        }
    }
}

final class SubmitTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onLayout: (() -> Void)?
    var onFocus: ((Bool) -> Void)?
    var onImage: ((Data) -> Void)?
    var onFiles: (([URL]) -> Void)?
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { super.readablePasteboardTypes + [.png, .tiff, .fileURL] }
    override func paste(_ sender: Any?) {
        if pasteAttachments(from: .general) { return }
        super.paste(sender)
    }
    @discardableResult func pasteAttachments(from pasteboard: NSPasteboard) -> Bool {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !urls.isEmpty, let onFiles { onFiles(urls); return true }
        // Preview can offer OCR text alongside copied pixels. Prefer the image
        // when present; ordinary chat/text paste falls through to NSTextView.
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff), let onImage {
            onImage(data); return true
        }
        return false
    }
    override func layout() { super.layout(); onLayout?() }
    override func becomeFirstResponder() -> Bool { let accepted = super.becomeFirstResponder(); if accepted { onFocus?(true) }; return accepted }
    override func resignFirstResponder() -> Bool { let accepted = super.resignFirstResponder(); if accepted { onFocus?(false) }; return accepted }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 && !event.modifierFlags.contains(.shift) && !hasMarkedText() { onSubmit?() }
        else { super.keyDown(with: event) }
    }
}

private struct ImageAttachmentView: View {
    var url: URL?
    var name: String
    var size: CGFloat
    @State private var thumbnail: NSImage?
    @State private var preview = false
    var body: some View {
        Button { preview = true } label: {
            Group {
                if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit() }
                else { Image(systemName: "photo").foregroundStyle(.secondary) }
            }.frame(width: size, height: size)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).accessibilityLabel("Preview \(name)").help(name)
            .task(id: url) {
                thumbnail = nil
                if let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                   let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 600] as CFDictionary) {
                    thumbnail = NSImage(cgImage: image, size: .zero)
                }
            }
            .popover(isPresented: $preview) {
                VStack(spacing: 14) {
                    HStack { Text(name).font(.headline).lineLimit(1); Spacer(); Button("Done") { preview = false } }
                    if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit().frame(maxWidth: 520, maxHeight: 420) }
                    if let url { Button("Open full image") { NSWorkspace.shared.open(url) } }
                }.padding(18).frame(width: 556).preferredColorScheme(.dark).tint(OblivionStyle.accent)
            }
    }
}

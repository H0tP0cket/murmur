import SwiftUI
import AppKit
import Carbon

@MainActor
final class WindowCoordinator {
    weak var mainWindow: NSWindow?
    private weak var state: AppState?
    private var panel: NSPanel?
    private var hotkeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    init(state: AppState) { self.state = state }

    func showHUD() {
        guard let state, state.activeCallID != nil else { return }
        if panel == nil {
            let panel = CopilotPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 340), styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable], backing: .buffered, defer: false)
            panel.title = "Oblivion · Call"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
            panel.isFloatingPanel = true; panel.level = .floating; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true; panel.minSize = NSSize(width: 460, height: 230)
            panel.isReleasedWhenClosed = false; panel.backgroundColor = OblivionStyle.windowColor
            panel.appearance = NSAppearance(named: .darkAqua)
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            panel.contentView = NSHostingView(rootView: HUDView().environmentObject(state))
            self.panel = panel
            if let screen = mainWindow?.screen ?? NSScreen.main {
                panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 310, y: screen.visibleFrame.maxY - 390))
            }
        }
        mainWindow?.orderOut(nil)
        resizeHUD(); panel?.orderFrontRegardless(); state.hudVisible = true
    }

    func resizeHUD() {
        guard let panel, let state else { return }
        let width = max(460, panel.frame.width)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 7
        let textHeight = (state.recommendation.answer as NSString).boundingRect(with: NSSize(width: width - 52, height: 1600), options: [.usesLineFragmentOrigin], attributes: [.font: NSFont.systemFont(ofSize: 20, weight: .medium), .paragraphStyle: paragraph]).height
        let screenHeight = panel.screen?.visibleFrame.height ?? 800
        let height = min(screenHeight - 70, max(270, min(screenHeight * 0.8, textHeight + 200)) + (state.showDirectQuestion ? 160 : 0))
        var frame = panel.frame; frame.origin.y += frame.height - height; frame.size.height = height
        panel.setFrame(frame, display: true, animate: false)
    }

    func returnToChat() {
        panel?.orderOut(nil); state?.hudVisible = false
        if mainWindow?.isMiniaturized == true { mainWindow?.deminiaturize(nil) }
        mainWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func toggleHUD() {
        guard let state, state.activeCallID != nil else { return }
        if state.hudVisible { panel?.orderOut(nil); state.hudVisible = false } else { showHUD() }
    }
    func ask() {
        guard let state, state.activeCallID != nil else { return }
        state.showDirectQuestion = true; showHUD(); panel?.makeKeyAndOrderFront(nil)
    }

    func installShortcuts() {
        removeShortcuts()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, data in
            guard let event, let data else { return noErr }
            var key = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            let coordinator = Unmanaged<WindowCoordinator>.fromOpaque(data).takeUnretainedValue()
            Task { @MainActor in
                switch key.id { case 1: coordinator.toggleHUD(); case 2: coordinator.returnToChat(); case 3: coordinator.ask(); default: break }
            }
            return noErr
        }, 1, &spec, userData, &eventHandler)
        for (id, key, modifiers) in [(1, kVK_Space, cmdKey | shiftKey), (2, kVK_ANSI_X, cmdKey | shiftKey), (3, kVK_ANSI_K, cmdKey | optionKey)] {
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(UInt32(key), UInt32(modifiers), EventHotKeyID(signature: 0x4F424C56, id: UInt32(id)), GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference { hotkeys.append(reference) }
            else { state?.captureIssue("A call shortcut is already in use. The on-screen controls remain available.") }
        }
    }
    func removeShortcuts() { hotkeys.forEach { UnregisterEventHotKey($0) }; hotkeys.removeAll(); if let eventHandler { RemoveEventHandler(eventHandler) }; eventHandler = nil }
}

final class CopilotPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct HUDView: View {
    @EnvironmentObject var state: AppState
    @FocusState private var inputFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(state.audio.isRunning ? .green : .orange).frame(width: 5, height: 5)
                Text("LIVE").font(.system(size: 10, weight: .semibold)).tracking(1)
                Text(state.recommendation.coaching).font(.system(size: 12)).lineLimit(2)
                Spacer(minLength: 6)
                Button { state.windows.toggleHUD() } label: { Image(systemName: "eye.slash") }.help("Hide · ⌘⇧Space")
            }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.horizontal, 23).padding(.top, 20).padding(.bottom, 13)
            Divider().opacity(0.5)
            HStack { Text(state.recommendation.kind).font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary); Spacer(); if state.audio.localSpeaking || state.recommendationPinned { Text(state.recommendationPinned ? "Pinned" : "Holding your answer").font(.system(size: 10)).foregroundStyle(.tertiary) } }.padding(.horizontal, 24).padding(.top, 19)
            ScrollView { Text(state.recommendation.answer).font(.system(size: 20, weight: .medium)).lineSpacing(7).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.top, 9).padding(.bottom, 14) }.frame(maxHeight: .infinity)
            if !state.coachingStatus.isEmpty && !state.coachingBusy { Text(state.coachingStatus).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(3).padding(.horizontal, 24).padding(.bottom, 8) }
            if state.showDirectQuestion {
                Divider().opacity(0.5)
                VStack(alignment: .leading, spacing: 9) {
                    HStack { TextField("Ask about this call…", text: $state.directQuestion).textFieldStyle(.plain).focused($inputFocused).onSubmit { state.askDirect() }; Button { state.askDirect() } label: { Image(systemName: "arrow.up.circle.fill") }.disabled(state.directBusy); Button { state.showDirectQuestion = false } label: { Image(systemName: "xmark") } }.buttonStyle(.plain).font(.system(size: 13))
                    if state.directBusy { ProgressView().controlSize(.small) }
                    if !state.directAnswer.isEmpty { ScrollView { Text(.init(state.directAnswer)).font(.system(size: 13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 120) }
                }.padding(.horizontal, 24).padding(.vertical, 13)
            }
            Divider().opacity(0.5)
            HStack(spacing: 17) {
                Button { state.windows.returnToChat() } label: { Label("Chat", systemImage: "arrow.down.left") }.help("Return to chat · ⌘⇧X")
                Button { state.windows.ask() } label: { Label("Ask", systemImage: "sparkle") }.help("Ask copilot · ⌘K")
                Button { state.recommendationPinned = false; state.requestCoaching(force: true) } label: { Image(systemName: "arrow.clockwise") }.disabled(state.coachingBusy).help("Get another recommendation")
                Menu {
                    Button(state.recommendationPinned ? "Unpin answer" : "Pin this answer") { state.recommendationPinned.toggle() }
                    Divider()
                    ForEach(state.activeCall?.stories.filter(\.approved) ?? []) { story in Button(story.title) { state.useStory(story) } }
                } label: { Image(systemName: state.recommendationPinned ? "pin.fill" : "rectangle.stack") }.menuStyle(.borderlessButton).fixedSize().help("Prepared answers · available offline")
                Spacer()
                AudioLevelsView(audio: state.audio)
                Button(state.callEnding ? "Ending…" : "End call") { Task { await state.endCall() } }.disabled(state.callEnding)
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 13)
        }
        .background(OblivionStyle.canvas)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .tint(OblivionStyle.accent)
        .onChange(of: state.recommendation.answer) { _, _ in state.windows.resizeHUD() }
        .onChange(of: state.showDirectQuestion) { _, shown in state.windows.resizeHUD(); inputFocused = shown }
        .onAppear { inputFocused = state.showDirectQuestion }
        .onKeyPress("k", phases: .down) { press in if press.modifiers.contains(.command) { state.windows.ask(); return .handled }; return .ignored }
    }
}

struct AudioLevelsView: View {
    @ObservedObject var audio: AudioCapture
    var body: some View { HStack(spacing: 5) { Image(systemName: "mic"); Capsule().fill(.primary.opacity(0.3)).frame(width: 3, height: max(3, audio.micLevel * 18)); Image(systemName: "speaker.wave.1"); Capsule().fill(.primary.opacity(0.3)).frame(width: 3, height: max(3, audio.meetingLevel * 18)) }.font(.system(size: 9)).frame(height: 18).help(audio.status).accessibilityElement(children: .ignore).accessibilityLabel("Microphone \(Int(audio.micLevel * 100)) percent, meeting audio \(Int(audio.meetingLevel * 100)) percent. \(audio.status)") }
}

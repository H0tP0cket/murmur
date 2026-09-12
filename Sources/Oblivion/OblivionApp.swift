import SwiftUI
import AppKit

@main
struct OblivionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("Oblivion", id: "main") {
            MainView().environmentObject(state)
                .preferredColorScheme(.dark)
                .tint(OblivionStyle.accent)
                .frame(minWidth: 900, minHeight: 600)
                .background(WindowReader { window in
                    window.appearance = NSAppearance(named: .darkAqua)
                    window.titlebarAppearsTransparent = true
                    window.backgroundColor = OblivionStyle.windowColor
                    state.windows.mainWindow = window; delegate.state = state
                })
        }
        .defaultSize(width: 1120, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { Button("New call") { state.newCall(); state.windows.returnToChat() }.keyboardShortcut("n") }
            CommandGroup(replacing: .appSettings) { Button("Settings…") { state.showSettings = true; state.windows.returnToChat() }.keyboardShortcut(",") }
            CommandMenu("Call") {
                Button(state.activeCallID == nil ? "Start call…" : "Pop out") { if state.activeCallID == nil { state.showCallSetup = true } else { state.windows.showHUD() } }.keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Return to chat") { state.windows.returnToChat() }.keyboardShortcut("x", modifiers: [.command, .shift])
                Button("Hide / show call window") { state.windows.toggleHUD() }.keyboardShortcut(.space, modifiers: [.command, .shift])
                Button("Ask copilot") { state.windows.ask() }.keyboardShortcut("k", modifiers: [.command, .option])
                Divider()
                Button("End call") { Task { await state.endCall() } }.disabled(state.activeCallID == nil)
            }
            CommandMenu("Conversation") {
                Button("Attach file…") { state.chooseAttachment() }.keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Import transcript…") { state.importTranscript() }
                Button("Export call…") { state.exportCall() }.keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // In-place development installs can leave the Dock's cached icon stale.
        // Load the bundled artwork once, independently of Launch Services.
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let state, state.activeCallID != nil else { state?.codex.disconnect(); return .terminateNow }
        Task { await state.endCall(summarize: false); state.codex.disconnect(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let state, state.windows.mainWindow != nil else { return true }
        state.windows.returnToChat()
        // We handled the reopen. Default handling may create an extra SwiftUI
        // window because floating NSPanel instances do not count as main windows.
        return false
    }
}

/// Configure each native window once, rather than resetting its appearance
/// and invalidating layout on every published chat/composer update.
struct WindowReader: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.onWindow = onWindow
        return view
    }
    func updateNSView(_ view: WindowAttachmentView, context: Context) { view.onWindow = onWindow }
}

final class WindowAttachmentView: NSView {
    var onWindow: ((NSWindow) -> Void)?
    private weak var configuredWindow: NSWindow?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, window !== configuredWindow else { return }
        configuredWindow = window
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            self.onWindow?(window)
        }
    }
}

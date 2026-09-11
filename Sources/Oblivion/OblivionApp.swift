import SwiftUI
import AppKit

@main
struct OblivionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var state = AppState()
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup("Oblivion", id: "main") {
            MainView().environmentObject(state)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .frame(minWidth: 900, minHeight: 600)
                .background(WindowReader { window in state.windows.mainWindow = window; delegate.state = state })
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
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let state, state.activeCallID != nil else { state?.codex.disconnect(); return .terminateNow }
        Task { await state.endCall(summarize: false); state.codex.disconnect(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { state?.windows.returnToChat(); return true }
}

struct WindowReader: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView { let view = NSView(); DispatchQueue.main.async { if let window = view.window { onWindow(window) } }; return view }
    func updateNSView(_ view: NSView, context: Context) { DispatchQueue.main.async { if let window = view.window { onWindow(window) } } }
}

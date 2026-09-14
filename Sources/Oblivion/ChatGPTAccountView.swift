import SwiftUI
import AppKit

struct ChatGPTAccountView: View {
    @ObservedObject var service: CodexService
    var showSignedIn = false
    var canSignOut = true
    @State private var working = false
    @State private var error: String?
    var body: some View {
        if !service.isConnected || showSignedIn {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: service.isConnected ? "checkmark.circle" : "person.crop.circle").font(.system(size: 19)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.isConnected ? "Connected with ChatGPT" : "Bring your ChatGPT account").font(.system(size: 14, weight: .medium))
                        Text(service.isConnected ? (service.accountEmail ?? "Your own subscription") : "No API key. Your plan’s Codex access and usage limits apply.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if working { ProgressView().controlSize(.small) }
                    if service.isConnected {
                        Button("Sign out") { perform { try await service.signOut() } }.disabled(working || !canSignOut)
                    } else {
                        Button(service.isSigningIn ? "Open browser" : "Sign in with ChatGPT") {
                            perform { let url = try await service.beginLogin(); NSWorkspace.shared.open(url) }
                        }.disabled(working)
                    }
                }.buttonStyle(.bordered).controlSize(.small)
                if service.isSigningIn {
                    HStack { Text("Complete sign-in in your browser, then return here."); Spacer(); Button("Cancel") { Task { await service.cancelLogin() } } }.font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if let message = error ?? service.authenticationError { Text(message).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled) }
                if showSignedIn && service.usesSharedSignIn {
                    Text("This upgraded library shares its existing Codex sign-in. Signing out also signs out that Codex account on this Mac.").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
        }
    }
    private func perform(_ action: @escaping () async throws -> Void) {
        working = true; error = nil
        Task {
            defer { working = false }
            do { try await action() } catch { self.error = error.localizedDescription }
        }
    }
}

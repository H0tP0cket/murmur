import Foundation

@MainActor enum CodexRuntime {
    static func home(for library: LibraryStore) -> URL {
        // Preserve existing thread IDs and sign-in for upgrades. Fresh installs
        // get a private Codex home with no inherited plugins or global settings.
        let marker = library.root.appendingPathComponent("codex-storage.txt")
        let mode: String
        if let saved = try? String(contentsOf: marker, encoding: .utf8) { mode = saved }
        else {
            mode = ((try? library.load()) ?? []).contains { $0.threadID != nil } ? "legacy" : "private"
            try? mode.write(to: marker, atomically: true, encoding: .utf8)
        }
        return mode == "legacy" ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex") : library.root.appendingPathComponent("Codex")
    }

    static func executable(override: URL?) -> URL? {
        let candidates: [String?] = [override?.path, UserDefaults.standard.string(forKey: "codexPath"),
                          Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("codex").path,
                          NSHomeDirectory() + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
                          "/Applications/ChatGPT.app/Contents/Resources/codex"]
        return candidates.compactMap { $0 }.first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
}

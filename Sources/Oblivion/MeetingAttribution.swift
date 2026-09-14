import AppKit
import ApplicationServices

struct MeetingParticipant: Codable, Equatable {
    var id: String
    var name: String
    var isSelf: Bool
}
struct SpeakerEnvelope: Codable {
    var session: String
    var room: String
    var receivedAt: Double
    var participants: [MeetingParticipant]
    var activeIDs: [String]
    var completeRoster: Bool

    func remoteSpeaker() -> String? {
        let active = participants.filter { activeIDs.contains($0.id) && !$0.isSelf }
        if active.count == 1, activeIDs.count == 1 { return active[0].name }
        let remote = participants.filter { !$0.isSelf }
        // A complete two-person roster is unambiguous on the separate meeting channel.
        if activeIDs.isEmpty, completeRoster, remote.count == 1, participants.filter(\.isSelf).count == 1 { return remote[0].name }
        return nil
    }
}

@MainActor
final class MeetingAttribution: ObservableObject {
    @Published var status = "Speaker names are optional."
    @Published var participants: [String] = []
    private var root: URL?
    private var session: UUID?
    private var elapsedTime: () -> Double = { 0 }
    private var timer: Timer?
    private var samples: [(time: Double, name: String?)] = []
    private var boundRoom: String?
    private var scanningZoom = false

    func start(root: URL, session: UUID, source: String, elapsedTime: @escaping () -> Double) {
        stop(); self.root = root; self.session = session; self.elapsedTime = elapsedTime; boundRoom = nil
        status = source == "com.google.Chrome" ? "Connect the Meet companion for names." : source == "us.zoom.xos" ? "Checking Zoom speaker names…" : "Choose Chrome or Zoom audio to attach speaker names."
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(source: source) }
        }
        tick(source: source)
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if let root { try? FileManager.default.removeItem(at: root.appendingPathComponent("bridge-session.json")) }
        session = nil; samples.removeAll(); participants = []; boundRoom = nil
        status = "Speaker names are optional."
    }

    func speaker(start: Double, end: Double) -> String? {
        // Use metadata from when the speech happened, not whoever is speaking
        // when a delayed final transcription result arrives.
        let relevant = samples.filter { $0.time >= max(0, start - 0.5) && $0.time <= end + 0.5 }
        let known = Set(relevant.compactMap(\.name))
        guard known.count == 1, relevant.filter({ $0.name != nil }).count >= max(1, relevant.count / 2) else { return nil }
        return known.first
    }

    private func tick(source: String) {
        guard let root, let session else { return }
        if source == "com.google.Chrome" {
            let heartbeat: [String: Any] = ["session": session.uuidString, "updatedAt": Date().timeIntervalSince1970]
            if let data = try? JSONSerialization.data(withJSONObject: heartbeat) { try? data.write(to: root.appendingPathComponent("bridge-session.json"), options: .atomic) }
            let file = root.appendingPathComponent("meet-speakers.json")
            guard let data = try? Data(contentsOf: file), data.count <= 65536,
                  let envelope = try? JSONDecoder().decode(SpeakerEnvelope.self, from: data),
                  envelope.session == session.uuidString,
                  abs(Date().timeIntervalSince1970 - envelope.receivedAt) < 2 else {
                record(nil); status = "Connect the Meet companion for names."; return
            }
            if boundRoom == nil { boundRoom = envelope.room }
            guard boundRoom == envelope.room else { record(nil); status = "A different Meet is connected. Restart this call to switch."; return }
            participants = envelope.participants.map(\.name)
            let name = envelope.remoteSpeaker(); record(name)
            status = name.map { "Meet · \($0)" } ?? "Meet connected · speaker uncertain"
        } else if source == "us.zoom.xos", !scanningZoom {
            guard AXIsProcessTrusted() else { status = "Allow Accessibility for Zoom speaker names in Settings."; record(nil); return }
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "us.zoom.xos").first else { status = "Zoom isn’t running."; record(nil); return }
            scanningZoom = true
            let pid = app.processIdentifier
            Task {
                let name = await Task.detached(priority: .utility) { ZoomSpeakerReader.speakingName(pid: pid) }.value
                scanningZoom = false
                guard self.session == session else { return }
                record(name); status = name.map { "Zoom · \($0)" } ?? "Zoom connected · speaker uncertain"
            }
        }
    }

    private func record(_ name: String?) {
        samples.append((elapsedTime(), name))
        if samples.count > 16000 { samples.removeFirst(2000) }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func installMeetCompanion(root: URL) throws -> URL {
        guard let resources = Bundle.main.resourceURL else { throw OblivionError.message("Companion resources are missing. Rebuild the app.") }
        let source = resources.appendingPathComponent("Companion")
        let target = root.appendingPathComponent("Companion")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for name in ["Meet", "extension-id.txt"] {
            let destination = target.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.copyItem(at: source.appendingPathComponent(name), to: destination)
        }
        let host = target.appendingPathComponent("MurMurMeetBridge")
        if FileManager.default.fileExists(atPath: host.path) { try FileManager.default.removeItem(at: host) }
        try FileManager.default.copyItem(at: resources.deletingLastPathComponent().appendingPathComponent("MacOS/MurMurMeetBridge"), to: host)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: host.path)
        let manifest: [String: Any] = ["name": "dev.oblivion.meet", "description": "MurMur local speaker names", "path": host.path, "type": "stdio", "allowed_origins": ["chrome-extension://koikkoppmobklaimhplgjgkfljiclnjj/"]]
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted).write(to: folder.appendingPathComponent("dev.oblivion.meet.json"), options: .atomic)
        return target.appendingPathComponent("Meet")
    }
}

/// Read only Zoom's exposed accessibility strings. No window-title or visual
/// border heuristics: absence of an explicit speaking label means unknown.
enum ZoomSpeakerReader {
    static func speakingName(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var queue: [(AXUIElement, Int)] = [(app, 0)], cursor = 0
        var names = Set<String>()
        while cursor < queue.count && cursor < 1600 {
            let (element, depth) = queue[cursor]; cursor += 1
            for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
                   let text = value as? String, let name = explicitName(text) { names.insert(name) }
            }
            if depth < 14 {
                var children: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success, let values = children as? [AXUIElement] { queue.append(contentsOf: values.prefix(150).map { ($0, depth + 1) }) }
            }
        }
        return names.count == 1 ? names.first : nil
    }
    static func explicitName(_ text: String) -> String? {
        let patterns = [#"^(?:Speaking|Talking|Active speaker):\s*(.{1,120})$"#, #"^(.{1,120}) is (?:speaking|talking)\.?$"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 1), in: text) else { continue }
            let name = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !["you", "your microphone", "someone"].contains(name.lowercased()) { return name }
        }
        return nil
    }
}

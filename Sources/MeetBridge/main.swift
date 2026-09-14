import Foundation
import Darwin

// Native Chrome messaging helper. No Python or developer tools required.
let origin = "chrome-extension://koikkoppmobklaimhplgjgkfljiclnjj/"
let root = ProcessInfo.processInfo.environment["MURMUR_LIBRARY_ROOT"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Oblivion")
let input = FileHandle.standardInput, output = FileHandle.standardOutput
umask(0o077)

func readExactly(_ count: Int) -> Data? {
    var data = Data()
    while data.count < count {
        guard let chunk = try? input.read(upToCount: count - data.count), !chunk.isEmpty else { return nil }
        data.append(chunk)
    }
    return data
}
func reply(_ status: String) {
    guard let data = try? JSONSerialization.data(withJSONObject: ["status": status]) else { return }
    var size = UInt32(data.count).littleEndian
    try? withUnsafeBytes(of: &size) { try output.write(contentsOf: Data($0)) }
    try? output.write(contentsOf: data)
}
func sanitize(_ message: [String: Any]) -> [String: Any]? {
    guard let room = message["room"] as? String, room.range(of: "^[a-z]{3}-[a-z]{4}-[a-z]{3}$", options: .regularExpression) != nil else { return nil }
    let people = (message["participants"] as? [[String: Any]] ?? []).prefix(100).compactMap { person -> [String: Any]? in
        guard let id = person["id"] as? String, !id.isEmpty, let name = person["name"] as? String else { return nil }
        let cleaned = String(name.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(120))
        guard !cleaned.isEmpty else { return nil }
        return ["id": String(id.prefix(250)), "name": cleaned, "isSelf": person["isSelf"] as? Bool == true]
    }
    let ids = Set(people.compactMap { $0["id"] as? String })
    let active = Array((message["activeIDs"] as? [String] ?? []).prefix(100)).filter { ids.contains($0) }
    return ["room": room, "participants": people, "activeIDs": active, "completeRoster": message["completeRoster"] as? Bool == true]
}
if CommandLine.arguments.count >= 2 && CommandLine.arguments[1] == origin {
    while let header = readExactly(4) {
        let size = header.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }
        guard size <= 65536, let data = readExactly(Int(size)) else { break }
        do {
            let sessionData = try Data(contentsOf: root.appendingPathComponent("bridge-session.json"))
            guard let session = try JSONSerialization.jsonObject(with: sessionData) as? [String: Any],
                  let timestamp = session["updatedAt"] as? Double,
                  Date().timeIntervalSince1970 - timestamp < 5, let sessionID = session["session"] as? String,
                  let message = try JSONSerialization.jsonObject(with: data) as? [String: Any], var payload = sanitize(message) else {
                reply("Start a call in MurMur to connect speaker names."); continue
            }
            payload["session"] = sessionID; payload["receivedAt"] = Date().timeIntervalSince1970
            try JSONSerialization.data(withJSONObject: payload).write(to: root.appendingPathComponent("meet-speakers.json"), options: .atomic)
            reply("Connected to your active MurMur call.")
        } catch { reply("Start a call in MurMur to connect speaker names.") }
    }
}

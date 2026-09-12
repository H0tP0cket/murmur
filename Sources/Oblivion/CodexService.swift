import Foundation

@MainActor
final class CodexService: ObservableObject {
    @Published var status = "Connecting…"
    @Published var models: [ModelOption] = []
    @Published var isConnected = false
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var sequence = 0
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var turns: [String: TurnWaiter] = [:]
    private var connectTask: Task<Void, Error>?

    private final class TurnWaiter {
        var requestID = UUID()
        var continuation: CheckedContinuation<String, Error>?
        var text = ""
        var turnID: String?
        var cancelled = false
        var queuedEvents: [(String, [String: Any])] = []
        var onText: (String) -> Void
        var onStatus: (String) -> Void
        init(_ continuation: CheckedContinuation<String, Error>, onText: @escaping (String) -> Void, onStatus: @escaping (String) -> Void) {
            self.continuation = continuation; self.onText = onText; self.onStatus = onStatus
        }
    }

    func connect() async throws {
        if isConnected { return }
        if let task = connectTask { return try await task.value }
        let task = Task { do { try await self.start() } catch { self.disconnect(); throw error } }
        connectTask = task
        defer { connectTask = nil }
        try await task.value
    }

    private func start() async throws {
        status = "Connecting…"
        let candidates = [UserDefaults.standard.string(forKey: "codexPath"), NSHomeDirectory() + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/Applications/ChatGPT.app/Contents/Resources/codex"].compactMap { $0 }
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw OblivionError.message("Codex isn’t installed. Set its executable path in Settings.") }
        let proc = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["app-server"]
        proc.standardInput = stdin; proc.standardOutput = stdout; proc.standardError = stderr
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        proc.environment = environment
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            Task { @MainActor in
                guard let self, self.process === proc else { return }
                self.receive(data)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in if handle.availableData.isEmpty { handle.readabilityHandler = nil } }
        proc.terminationHandler = { [weak self] ended in Task { @MainActor in
            guard let self, self.process === ended else { return }; self.disconnected()
        } }
        process = proc; input = stdin.fileHandleForWriting; buffer = Data()
        try proc.run()
        _ = try await request("initialize", ["clientInfo": ["name": "oblivion", "title": "Oblivion", "version": "0.1.0"], "capabilities": ["experimentalApi": true]])
        try send(["method": "initialized"])
        let account = try await request("account/read", [:])
        let type = (account["account"] as? [String: Any])?["type"] as? String
        guard type == "chatgpt" else { throw OblivionError.message("Sign in with ChatGPT using ‘codex login’, then reconnect. Oblivion uses your Codex subscription.") }
        var choices: [ModelOption] = [], cursor: String?
        repeat {
            var params: [String: Any] = ["limit": 100, "includeHidden": false]
            if let cursor { params["cursor"] = cursor }
            let result = try await request("model/list", params)
            choices += (result["data"] as? [[String: Any]] ?? []).compactMap { item in
                guard let model = item["model"] as? String else { return nil }
                return ModelOption(id: model, name: item["displayName"] as? String ?? model, efforts: (item["supportedReasoningEfforts"] as? [[String: Any]] ?? []).compactMap { $0["reasoningEffort"] as? String }, defaultEffort: item["defaultReasoningEffort"] as? String ?? "low", inputModalities: item["inputModalities"] as? [String] ?? ["text", "image"])
            }
            cursor = result["nextCursor"] as? String
        } while cursor != nil
        models = choices; isConnected = true; status = "Connected to Codex"
    }

    func model(live: Bool) -> String? {
        let saved = UserDefaults.standard.string(forKey: live ? "liveModel" : "prepModel")
        if let saved, models.contains(where: { $0.id == saved }) { return saved }
        let preferences = live ? ["gpt-5.6-luna", "gpt-5.6-sol", "gpt-5.6-terra"] : ["gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-terra"]
        return preferences.first(where: { name in models.contains { $0.id == name } }) ?? models.first?.id
    }

    func thread(cwd: URL, existing: String? = nil, live: Bool = false, ephemeral: Bool = false) async throws -> String {
        try await connect()
        try Task.checkCancellation()
        if let existing {
            _ = try await request("thread/resume", ["threadId": existing, "cwd": cwd.path])
            try Task.checkCancellation()
            return existing
        }
        var params: [String: Any] = ["cwd": cwd.path, "approvalPolicy": "never", "sandbox": "workspace-write", "baseInstructions": live ? Prompts.coach : Prompts.assistant, "ephemeral": live || ephemeral, "config": ["web_search": live ? "disabled" : "live", "project_doc_max_bytes": 0]]
        if let model = model(live: live) { params["model"] = model }
        let result = try await request("thread/start", params)
        guard let id = (result["thread"] as? [String: Any])?["id"] as? String else { throw OblivionError.message("Codex didn’t return a conversation.") }
        try Task.checkCancellation()
        return id
    }

    func run(threadID: String, text: String, images: [URL] = [], live: Bool = false, schema: [String: Any]? = nil, onText: @escaping (String) -> Void = { _ in }, onStatus: @escaping (String) -> Void = { _ in }) async throws -> String {
        try Task.checkCancellation()
        guard turns[threadID] == nil else { throw OblivionError.message("This conversation is still responding.") }
        if !images.isEmpty, let selected = model(live: live), let option = models.first(where: { $0.id == selected }), !option.inputModalities.contains("image") {
            throw OblivionError.message("\(option.name) doesn’t accept images. Choose an image-capable model in Settings.")
        }
        guard images.allSatisfy({ $0.isFileURL && FileManager.default.isReadableFile(atPath: $0.path) }) else {
            throw OblivionError.message("An attached image is missing. Remove it and attach it again.")
        }
        let requestID = UUID()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let waiter = TurnWaiter(continuation, onText: onText, onStatus: onStatus)
                waiter.requestID = requestID
                turns[threadID] = waiter
                Task {
                    do {
                        let inputs: [[String: Any]] = [["type": "text", "text": text]] + images.map { ["type": "localImage", "path": $0.path] }
                        var params: [String: Any] = ["threadId": threadID, "input": inputs]
                        if let model = model(live: live) {
                            params["model"] = model
                            if let option = models.first(where: { $0.id == model }) {
                                params["effort"] = live ? (["none", "low"].first(where: option.efforts.contains) ?? option.defaultEffort) : (option.efforts.contains("medium") ? "medium" : option.defaultEffort)
                            }
                        }
                        if let schema { params["outputSchema"] = schema }
                        let result = try await request("turn/start", params)
                        guard turns[threadID] === waiter else { return }
                        waiter.turnID = (result["turn"] as? [String: Any])?["id"] as? String
                        guard waiter.turnID != nil else { throw OblivionError.message("Codex didn’t identify this response.") }
                        let queued = waiter.queuedEvents; waiter.queuedEvents = []
                        for (method, params) in queued { handleNotification(method, params: params, threadID: threadID, waiter: waiter) }
                        if waiter.cancelled { await cancel(threadID: threadID) }
                    } catch { if turns[threadID] === waiter { finish(threadID, .failure(error)) } }
                }
                Task {
                    try? await Task.sleep(for: .seconds(live ? 60 : 240))
                    if turns[threadID] === waiter {
                        await cancel(threadID: threadID)
                        if turns[threadID] === waiter { finish(threadID, .failure(OblivionError.message("Codex took too long. Your context is saved; try again."))) }
                    }
                }
            }
        }, onCancel: { Task { @MainActor in await self.cancel(threadID: threadID, requestID: requestID) } })
    }

    func cancel(threadID: String, requestID: UUID? = nil) async {
        guard let waiter = turns[threadID], requestID == nil || waiter.requestID == requestID else { return }
        waiter.cancelled = true
        if let turnID = waiter.turnID {
            _ = try? await request("turn/interrupt", ["threadId": threadID, "turnId": turnID])
            if turns[threadID] === waiter { finish(threadID, .failure(CancellationError())) }
        }
    }

    func disconnect() {
        process?.terminate(); process = nil; input = nil
        disconnected()
    }

    private func disconnected() {
        isConnected = false; status = "Codex disconnected"
        let requests = pending; pending.removeAll()
        for continuation in requests.values { continuation.resume(throwing: OblivionError.message("Codex disconnected. Your local call is saved.")) }
        for thread in Array(turns.keys) { finish(thread, .failure(OblivionError.message("Codex disconnected. Reconnect to continue."))) }
    }

    private func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        sequence += 1; let id = sequence
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try send(["id": id, "method": method, "params": params]) }
            catch { pending.removeValue(forKey: id)?.resume(throwing: error) }
            Task {
                try? await Task.sleep(for: .seconds(35))
                pending.removeValue(forKey: id)?.resume(throwing: OblivionError.message("Codex connection timed out (\(method))."))
            }
        }
    }

    private func send(_ value: [String: Any]) throws {
        guard let input else { throw OblivionError.message("Codex isn’t connected.") }
        var data = try JSONSerialization.data(withJSONObject: value)
        data.append(10); try input.write(contentsOf: data)
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        while let end = buffer.firstIndex(of: 10) {
            let line = buffer[..<end]; buffer.removeSubrange(...end)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let id = message["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
                if let error = message["error"] as? [String: Any] { continuation.resume(throwing: OblivionError.message(error["message"] as? String ?? "Codex request failed.")) }
                else { continuation.resume(returning: message["result"] as? [String: Any] ?? [:]) }
                continue
            }
            guard let method = message["method"] as? String else { continue }
            let params = message["params"] as? [String: Any] ?? [:]
            if let id = message["id"] {
                // Never leave a server request hanging. Our threads use noninteractive tool policies.
                let result: [String: Any] = method.contains("requestApproval") ? ["decision": "decline"] : method.contains("requestUserInput") ? ["answers": [:]] : ["success": false, "contentItems": [["type": "inputText", "text": "This action is unavailable. Continue in the chat and ask the user if needed."]]]
                try? send(["id": id, "result": result]); continue
            }
            guard let threadID = params["threadId"] as? String, let waiter = turns[threadID] else { continue }
            if waiter.turnID == nil { waiter.queuedEvents.append((method, params)); continue }
            handleNotification(method, params: params, threadID: threadID, waiter: waiter)
        }
    }

    private func handleNotification(_ method: String, params: [String: Any], threadID: String, waiter: TurnWaiter) {
        let eventTurnID = params["turnId"] as? String ?? (params["turn"] as? [String: Any])?["id"] as? String
        guard turns[threadID] === waiter, let eventTurnID, eventTurnID == waiter.turnID else { return }
        if method == "item/agentMessage/delta", let delta = params["delta"] as? String {
                waiter.text += delta; waiter.onText(waiter.text)
            } else if method == "item/started", let item = params["item"] as? [String: Any], let type = item["type"] as? String, type != "agentMessage", type != "reasoning" {
                waiter.onStatus(type == "webSearch" ? "Researching…" : "Working with your context…")
            } else if method == "turn/completed" {
                let turn = params["turn"] as? [String: Any] ?? [:]
                let items = turn["items"] as? [[String: Any]] ?? []
                let replies = items.filter { ($0["type"] as? String) == "agentMessage" }
                let finals = replies.filter { ($0["phase"] as? String) == "final_answer" }
                let text = (finals.isEmpty ? replies : finals).compactMap { $0["text"] as? String }.joined(separator: "\n\n")
                if let error = turn["error"] as? [String: Any] { finish(threadID, .failure(OblivionError.message(error["message"] as? String ?? "Codex couldn’t finish this response."))) }
                else if (turn["status"] as? String) == "interrupted" || waiter.cancelled { finish(threadID, .failure(CancellationError())) }
                else { finish(threadID, .success(text.isEmpty ? waiter.text : text)) }
            }
    }

    private func finish(_ thread: String, _ result: Result<String, Error>) {
        guard let waiter = turns.removeValue(forKey: thread), let continuation = waiter.continuation else { return }
        waiter.continuation = nil; continuation.resume(with: result)
    }
}

import Foundation

@MainActor
final class CodexService: ObservableObject {
    @Published var status = "Connecting…"
    @Published var models: [ModelOption] = []
    @Published var isConnected = false
    @Published private(set) var isSigningIn = false
    @Published private(set) var accountEmail: String?
    @Published private(set) var loginURL: URL?
    @Published private(set) var authenticationError: String?
    private let executableURL: URL?
    private let homeURL: URL?
    private var loginID: String?
    private var loginResults: [String: [String: Any]] = [:]
    private var ignoredLoginIDs = Set<String>()
    var usesSharedSignIn: Bool { homeURL?.lastPathComponent == ".codex" }
    init(executableURL: URL? = nil, homeURL: URL? = nil) { self.executableURL = executableURL; self.homeURL = homeURL }
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var sequence = 0
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var turns: [String: TurnWaiter] = [:]
    private var requestTimeouts: [Int: Task<Void, Never>] = [:]
    private var connectTask: Task<Void, Error>?

    private final class TurnWaiter {
        var requestID = UUID()
        var continuation: CheckedContinuation<String, Error>?
        var text = ""
        var messageOrder: [String] = []
        var messageText: [String: String] = [:]
        var messagePhase: [String: String] = [:]
        var turnID: String?
        var cancelled = false
        var queuedEvents: [(String, [String: Any])] = []
        var timeout: Task<Void, Never>?
        var onText: (String) -> Void
        var onStatus: (String) -> Void
        init(_ continuation: CheckedContinuation<String, Error>, onText: @escaping (String) -> Void, onStatus: @escaping (String) -> Void) {
            self.continuation = continuation; self.onText = onText; self.onStatus = onStatus
        }
    }

    func connect() async throws {
        if isConnected { return }
        if process?.isRunning == true, connectTask == nil { return try await refreshAccount() }
        if let task = connectTask { return try await task.value }
        let task = Task { do { try await self.start() } catch { self.disconnect(); throw error } }
        connectTask = task
        defer { connectTask = nil }
        try await task.value
    }

    private func start() async throws {
        status = "Connecting…"
        guard let executable = CodexRuntime.executable(override: executableURL) else { throw OblivionError.message("The bundled Codex runtime is missing. Reinstall MurMur or choose a Codex executable in Settings.") }
        let proc = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        proc.executableURL = executable
        proc.arguments = ["app-server"]
        proc.standardInput = stdin; proc.standardOutput = stdout; proc.standardError = stderr
        var environment = ProcessInfo.processInfo.environment
        if let homeURL {
            try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            environment["CODEX_HOME"] = homeURL.path
            proc.currentDirectoryURL = homeURL
        }
        // This product uses subscription authentication only, never an inherited API key.
        for key in ["OPENAI_API_KEY", "CODEX_API_KEY"] { environment.removeValue(forKey: key) }
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
        _ = try await request("initialize", ["clientInfo": ["name": "murmur", "title": "MurMur", "version": "0.2.0"], "capabilities": ["experimentalApi": true]])
        try send(["method": "initialized"])
        try await refreshAccount()
    }

    func refreshAccount() async throws {
        let result = try await request("account/read", ["refreshToken": true])
        let account = result["account"] as? [String: Any]
        guard account?["type"] as? String == "chatgpt" else {
            isConnected = false; models = []; accountEmail = nil
            status = "Sign in with ChatGPT"; return
        }
        accountEmail = account?["email"] as? String
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

    @discardableResult func beginLogin() async throws -> URL {
        authenticationError = nil
        try await connect()
        if let loginURL, isSigningIn { return loginURL }
        isSigningIn = true; status = "Finish signing in in your browser"
        do {
            let result = try await request("account/login/start", ["type": "chatgpt"])
            guard let id = result["loginId"] as? String, let string = result["authUrl"] as? String,
                  let url = URL(string: string), url.scheme == "https", url.host == "auth.openai.com" else {
                throw OblivionError.message("Codex couldn’t open ChatGPT sign-in. Please try again.")
            }
            loginID = id; loginURL = url
            if let completed = loginResults.removeValue(forKey: id) { completeLogin(completed) }
            return url
        } catch {
            isSigningIn = false; authenticationError = error.localizedDescription; status = "Sign-in needs attention"; throw error
        }
    }

    func cancelLogin() async {
        guard let id = loginID else { return }
        ignoredLoginIDs.insert(id); loginID = nil; loginURL = nil; isSigningIn = false
        _ = try? await request("account/login/cancel", ["loginId": id])
        status = "Sign in with ChatGPT"
    }

    func signOut() async throws {
        guard turns.isEmpty else { throw OblivionError.message("Finish the current response and end your call before signing out.") }
        await cancelLogin()
        _ = try await request("account/logout", [:])
        isConnected = false; models = []; accountEmail = nil; authenticationError = nil; status = "Sign in with ChatGPT"
    }

    private func completeLogin(_ params: [String: Any]) {
        guard let id = params["loginId"] as? String, !ignoredLoginIDs.contains(id) else { return }
        guard id == loginID else { if isSigningIn { loginResults[id] = params }; return }
        loginID = nil; loginURL = nil; isSigningIn = false
        if params["success"] as? Bool == true {
            Task { do { try await refreshAccount() } catch { authenticationError = error.localizedDescription; status = "Connection needs attention" } }
        } else {
            authenticationError = params["error"] as? String ?? "Sign-in wasn’t completed. Try again when you’re ready."
            status = "Sign in with ChatGPT"
        }
    }

    func model(live: Bool) -> String? {
        let saved = UserDefaults.standard.string(forKey: live ? "liveModel" : "prepModel")
        if let saved, models.contains(where: { $0.id == saved }) { return saved }
        let preferences = live ? ["gpt-5.6-luna", "gpt-5.6-sol", "gpt-5.6-terra"] : ["gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-terra"]
        return preferences.first(where: { name in models.contains { $0.id == name } }) ?? models.first?.id
    }

    /// Resolve against the server's catalog, once per turn. Explicit choices must
    /// never silently run on another model or send an unsupported effort.
    func turnSelection(live: Bool = false, modelOverride: String? = nil, effortOverride: String? = nil) throws -> (model: String?, effort: String?) {
        let selected = modelOverride ?? model(live: live)
        guard let selected, let option = models.first(where: { $0.id == selected }) else {
            if modelOverride != nil { throw OblivionError.message("This model is unavailable. Choose another model in the chat.") }
            return (nil, nil)
        }
        let fallback = live ? (["none", "low"].first(where: option.efforts.contains) ?? option.defaultEffort)
                            : (option.efforts.contains("medium") ? "medium" : option.defaultEffort)
        let effort = effortOverride.flatMap { option.efforts.contains($0) ? $0 : nil } ?? fallback
        return (selected, option.efforts.contains(effort) ? effort : option.efforts.first)
    }

    func thread(cwd: URL, existing: String? = nil, live: Bool = false, ephemeral: Bool = false, instructions: String? = nil, modelOverride: String? = nil) async throws -> String {
        try await connect()
        guard isConnected else { throw OblivionError.message("Sign in with ChatGPT to start preparing your call.") }
        try Task.checkCancellation()
        if let existing {
            _ = try await request("thread/resume", ["threadId": existing, "cwd": cwd.path, "developerInstructions": Prompts.outputStyle])
            try Task.checkCancellation()
            return existing
        }
        var params: [String: Any] = ["cwd": cwd.path, "approvalPolicy": "never", "sandbox": "workspace-write", "baseInstructions": instructions ?? (live ? Prompts.coach : Prompts.assistant), "developerInstructions": Prompts.outputStyle, "ephemeral": live || ephemeral, "config": ["web_search": live ? "disabled" : "live", "project_doc_max_bytes": 0]]
        if let model = try turnSelection(live: live, modelOverride: modelOverride).model { params["model"] = model }
        let result = try await request("thread/start", params)
        guard let id = (result["thread"] as? [String: Any])?["id"] as? String else { throw OblivionError.message("Codex didn’t return a conversation.") }
        try Task.checkCancellation()
        return id
    }

    func run(threadID: String, text: String, images: [URL] = [], live: Bool = false, modelOverride: String? = nil, effortOverride: String? = nil, schema: [String: Any]? = nil, onText: @escaping (String) -> Void = { _ in }, onStatus: @escaping (String) -> Void = { _ in }) async throws -> String {
        try Task.checkCancellation()
        guard turns[threadID] == nil else { throw OblivionError.message("This conversation is still responding.") }
        let selection = try turnSelection(live: live, modelOverride: modelOverride, effortOverride: effortOverride)
        if !images.isEmpty, let selected = selection.model, let option = models.first(where: { $0.id == selected }), !option.inputModalities.contains("image") {
            throw OblivionError.message("\(option.name) doesn’t accept images. Choose an image-capable model in the chat.")
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
                        if let model = selection.model { params["model"] = model }
                        if let effort = selection.effort { params["effort"] = effort }
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
                waiter.timeout = Task { [weak self, weak waiter] in
                    do { try await Task.sleep(for: .seconds(live ? 60 : (["high", "xhigh", "max", "ultra"].contains(selection.effort ?? "") ? 900 : 240))) } catch { return }
                    guard let self, let waiter else { return }
                    if self.turns[threadID] === waiter {
                        await self.cancel(threadID: threadID)
                        if self.turns[threadID] === waiter { self.finish(threadID, .failure(OblivionError.message("Codex took too long. Your context is saved; try again."))) }
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
        isConnected = false; isSigningIn = false; loginID = nil; loginURL = nil; loginResults = [:]; accountEmail = nil; models = []; status = "Codex disconnected"
        buffer.removeAll(keepingCapacity: false)
        requestTimeouts.values.forEach { $0.cancel() }; requestTimeouts.removeAll()
        let requests = pending; pending.removeAll()
        for continuation in requests.values { continuation.resume(throwing: OblivionError.message("Codex disconnected. Your local call is saved.")) }
        for thread in Array(turns.keys) { finish(thread, .failure(OblivionError.message("Codex disconnected. Reconnect to continue."))) }
    }

    private func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        sequence += 1; let id = sequence
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try send(["id": id, "method": method, "params": params]) }
            catch { pending.removeValue(forKey: id)?.resume(throwing: error); return }
            requestTimeouts[id] = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(35)) } catch { return }
                guard let self else { return }
                self.requestTimeouts.removeValue(forKey: id)
                self.pending.removeValue(forKey: id)?.resume(throwing: OblivionError.message("Codex connection timed out (\(method))."))
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
                requestTimeouts.removeValue(forKey: id)?.cancel()
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
            if method == "account/login/completed" { completeLogin(params); continue }
            if method == "account/updated", params["authMode"] is NSNull {
                isConnected = false; models = []; accountEmail = nil; status = "Sign in with ChatGPT"; continue
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
                let itemID = params["itemId"] as? String ?? "legacy"
                if !waiter.messageOrder.contains(itemID) { waiter.messageOrder.append(itemID) }
                waiter.messageText[itemID, default: ""] += delta
                publishMessages(waiter)
            } else if method == "item/started" || method == "item/completed",
                      let item = params["item"] as? [String: Any], let type = item["type"] as? String {
                if type == "agentMessage", let itemID = item["id"] as? String {
                    if !waiter.messageOrder.contains(itemID) { waiter.messageOrder.append(itemID) }
                    waiter.messagePhase[itemID] = item["phase"] as? String
                    if let text = item["text"] as? String { waiter.messageText[itemID] = text }
                    publishMessages(waiter)
                } else if method == "item/started", type != "reasoning" {
                    waiter.onStatus(type == "webSearch" ? "Researching…" : "Working with your context…")
                }
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

    private func publishMessages(_ waiter: TurnWaiter) {
        // Commentary is progress, not part of the answer. Keep separate final
        // message items separated so headings, tables and paragraphs don't join.
        let visible = waiter.messageOrder.filter { waiter.messagePhase[$0] != "commentary" }
        let text = visible.compactMap { waiter.messageText[$0] }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard !text.isEmpty, text != waiter.text else { return }
        waiter.text = text; waiter.onText(text)
    }

    private func finish(_ thread: String, _ result: Result<String, Error>) {
        guard let waiter = turns.removeValue(forKey: thread), let continuation = waiter.continuation else { return }
        waiter.timeout?.cancel(); waiter.timeout = nil
        waiter.continuation = nil; continuation.resume(with: result)
    }
}

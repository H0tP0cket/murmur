import AppKit
import Testing
@testable import Oblivion

@Test @MainActor func chatModelAndEffortArePerCallValidatedAndBackwardCompatible() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("oblivion-models-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let state = AppState(root: root, connect: false)
    state.codex.models = [
        ModelOption(id: "model-a", name: "Model A", efforts: ["low", "medium", "high"], defaultEffort: "low"),
        ModelOption(id: "model-b", name: "Model B", efforts: ["none", "low"], defaultEffort: "none")
    ]
    let first = state.newCall()
    state.setChatModel("model-a", callID: first)
    state.modify(first) { $0.prepEffort = "high" }
    let selected = try state.codex.turnSelection(modelOverride: state.selected?.prepModel, effortOverride: state.selected?.prepEffort)
    #expect(selected.model == "model-a" && selected.effort == "high")
    let second = state.newCall()
    state.setChatModel("model-b", callID: second)
    let fallback = try state.codex.turnSelection(modelOverride: "model-b", effortOverride: "high")
    #expect(fallback.effort == "none")
    #expect(throws: (any Error).self) { try state.codex.turnSelection(modelOverride: "unavailable") }
    state.selectedID = first
    #expect(state.selected?.prepEffort == "high")
    let restored = AppState(root: root, connect: false)
    #expect(restored.calls.first { $0.id == first }?.prepModel == "model-a")
    #expect(restored.calls.first { $0.id == first }?.prepEffort == "high")
    #expect(restored.calls.first { $0.id == second }?.prepModel == "model-b")
    state.setChatModel("model-b", callID: first)
    #expect(state.selected?.prepEffort == nil)
    var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state.selected!)) as? [String: Any])
    legacy.removeValue(forKey: "prepModel"); legacy.removeValue(forKey: "prepEffort")
    let old = try JSONDecoder().decode(CallRecord.self, from: JSONSerialization.data(withJSONObject: legacy))
    #expect(old.prepModel == nil && old.prepEffort == nil)
}

/// Local JSON-RPC fixture exercises the real send/resume/stream/cancel path
/// without generating provider conversations or using an API/model account.
@Test @MainActor func chatSendsSelectedConfigurationClearsImagesAndPreservesCancelledText() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("oblivion-rpc-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let executable = root.appendingPathComponent("server.py")
    let script = #"""
    #!/usr/bin/env python3
    import json, sys, pathlib, threading, time
    root = pathlib.Path(__file__).parent
    lock = threading.Lock()
    def emit(data):
        with lock:
            print(json.dumps(data), flush=True)
    def event(method, tid, **kw):
        emit(dict(method=method, params=dict(threadId='test-thread', turnId=tid, **kw)))
    def stream(tid, text):
        event('item/started', tid, item=dict(id='comment',type='agentMessage',phase='commentary',text=''))
        event('item/agentMessage/delta',tid,itemId='comment',delta='Internal progress, not the reply.')
        event('item/started',tid,item=dict(id='answer',type='agentMessage',phase='final_answer',text=''))
        if 'CANCEL_ME' in text:
            event('item/agentMessage/delta',tid,itemId='answer',delta='Partial reply kept on stop')
            (root/'partial-received').write_text('yes')
            return
        for chunk in ['## Result\n\n', 'This is the ', '**complete answer**.']:
            event('item/agentMessage/delta',tid,itemId='answer',delta=chunk)
            time.sleep(0.15)
        event('turn/completed',tid,turn=dict(id=tid,status='completed',items=[dict(type='agentMessage',phase='final_answer',text='## Result\n\nThis is the **complete answer**.')]))
    n=0
    for raw in sys.stdin:
        message=json.loads(raw); method=message.get('method'); rid=message.get('id'); params=message.get('params',{})
        if rid is None: continue
        with (root/'requests.jsonl').open('a') as log: log.write(json.dumps(message)+'\n')
        result={}
        if method=='account/read': result={'account':{'type':'chatgpt'}}
        elif method=='model/list': result={'data':[dict(model=m, displayName=m, supportedReasoningEfforts=[dict(reasoningEffort=e) for e in ['low','medium','high']],defaultReasoningEffort='medium',inputModalities=['text','image']) for m in ['model-a','model-b']]}
        elif method in ['thread/start','thread/resume']: result={'thread':{'id':'test-thread'}}
        elif method=='turn/start':
            n+=1; tid='turn-'+str(n); result={'turn':{'id':tid}}
            emit(dict(id=rid,result=result))
            threading.Thread(target=stream,args=(tid,params['input'][0]['text']),daemon=True).start()
            continue
        emit(dict(id=rid,result=result))
    """#
    try script.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let service = CodexService(executableURL: executable)
    defer { service.disconnect() }
    let state = AppState(root: root.appendingPathComponent("library"), connect: false, codex: service)
    try await service.connect()
    let id = state.newCall()
    state.modify(id) { $0.automaticTitlePending = false; $0.prepModel = "model-a"; $0.prepEffort = "high" }
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 10, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    state.attachImage(png)
    let sent = try #require(state.selected?.unsentImages.first)
    #expect(state.selected?.composerAttachments.count == 1)
    state.composer = "Explain the image"
    state.send()
    #expect(state.selected?.composerAttachments.isEmpty == true) // Synchronous on send.
    #expect(state.selected?.messages.first { $0.role == "user" }?.images == [sent])
    state.attachImage(png) // This belongs to the NEXT turn, even before the task starts.
    let draft = try #require(state.selected?.unsentImages.first)
    #expect(state.selected?.composerAttachments == [draft])
    state.removeComposerAttachment(draft.id, callID: id)
    #expect(state.selected?.composerAttachments.isEmpty == true)
    #expect(state.selected?.attachments == [sent])
    state.removeComposerAttachment(sent.id, callID: id)
    #expect(state.selected?.attachments == [sent]) // Can't remove a sent message via stale chip.
    for _ in 0..<150 where state.isBusy { try await Task.sleep(for: .milliseconds(30)) }
    #expect(!state.isBusy)
    #expect(state.error == nil)
    #expect(state.selected?.messages.last?.text == "## Result\n\nThis is the **complete answer**.")
    #expect(state.selected?.messages.last?.pending == false)
    #expect(state.selected?.threadID == "test-thread")

    state.setChatModel("model-b", callID: id)
    state.modify(id) { $0.prepEffort = "low" }
    state.composer = "CANCEL_ME"
    state.send()
    for _ in 0..<150 where !FileManager.default.fileExists(atPath: root.appendingPathComponent("partial-received").path) { try await Task.sleep(for: .milliseconds(20)) }
    try await Task.sleep(for: .milliseconds(80))
    state.cancelChat()
    for _ in 0..<150 where state.isBusy { try await Task.sleep(for: .milliseconds(20)) }
    #expect(!state.isBusy)
    #expect(state.selected?.messages.last?.text == "Partial reply kept on stop")
    #expect(state.selected?.messages.last?.interrupted == true)
    let requests = try String(contentsOf: root.appendingPathComponent("requests.jsonl"), encoding: .utf8).split(separator: "\n").map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
    let turns = requests.filter { $0["method"] as? String == "turn/start" }.compactMap { $0["params"] as? [String: Any] }
    #expect(turns.count == 2)
    let first = try #require(turns.first), last = try #require(turns.last)
    #expect(first["model"] as? String == "model-a" && first["effort"] as? String == "high")
    #expect(last["model"] as? String == "model-b" && last["effort"] as? String == "low")
    #expect(requests.contains { $0["method"] as? String == "thread/resume" })
    let inputs = try #require(first["input"] as? [[String: Any]])
    #expect(inputs.filter { $0["type"] as? String == "localImage" }.count == 1)
    #expect(inputs.last?["path"] as? String == state.library.imageURL(sent, callID: id)?.path)
    let loaded = try #require(state.library.load().first)
    #expect(loaded.composerAttachments.isEmpty)
    #expect(loaded.messages.first { $0.role == "user" }?.images == [sent])
    #expect(loaded.messages.last?.text == "Partial reply kept on stop")
}

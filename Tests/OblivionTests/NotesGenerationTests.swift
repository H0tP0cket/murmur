import Foundation
import Testing
@testable import Oblivion

@Test func notesSourcesTrackCorrectionsButIgnoreGeneratedOutput() {
    var call = CallRecord()
    #expect(!NotesGeneration.hasMaterial(call))
    call.messages = [ChatMessage(role: "user", text: "Prepare for a pilot discussion")]
    #expect(NotesGeneration.hasMaterial(call))
    #expect(NotesGeneration.prompt(call).contains("default meeting notes"))
    let first = NotesGeneration.signature(call)
    call.generatedNotes = "Previously generated text"
    #expect(NotesGeneration.signature(call) == first)
    call.notes = "Focus on the decision deadline"
    #expect(NotesGeneration.signature(call) != first)
    #expect(NotesGeneration.prompt(call).contains("written notes as your outline"))
    #expect(NotesGeneration.prompt(call).contains(call.notes))
}

@Test @MainActor func aiNotesRefreshChangedSourcesAndPreserveBothKindsOfUserEdits() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("oblivion-ai-notes-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let executable = root.appendingPathComponent("server.py")
    try #"""
    #!/usr/bin/env python3
    import json, sys, pathlib
    root = pathlib.Path(__file__).parent
    n = 0
    def emit(message): print(json.dumps(message), flush=True)
    for line in sys.stdin:
        msg = json.loads(line)
        if 'id' not in msg: continue
        method = msg.get('method'); result = {}
        if method == 'account/read': result = {'account':{'type':'chatgpt'}}
        elif method == 'model/list': result = {'data':[{'model':'fixture','displayName':'Fixture','supportedReasoningEfforts':[{'reasoningEffort':'low'}],'defaultReasoningEffort':'low'}]}
        elif method == 'thread/start': result = {'thread':{'id':'notes-thread'}}
        elif method == 'turn/start':
            n += 1
            text = msg['params']['input'][0]['text']
            with (root/'prompts.jsonl').open('a') as log: log.write(json.dumps(text)+'\n')
            turn = 'notes-'+str(n)
            emit({'id':msg['id'],'result':{'turn':{'id':turn}}})
            answer = 'Guided notes' if 'written notes as your outline' in text else 'Default notes'
            emit({'method':'turn/completed','params':{'threadId':'notes-thread','turn':{'id':turn,'status':'completed','items':[{'type':'agentMessage','phase':'final_answer','text':answer}]}}})
            continue
        emit({'id':msg['id'],'result':result})
    """#.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let service = CodexService(executableURL: executable)
    defer { service.disconnect() }
    let state = AppState(root: root.appendingPathComponent("library"), connect: false, codex: service)
    let id = state.newCall()
    state.modify(id) { $0.messages = [ChatMessage(role: "user", text: "A fictional pilot discussion")] }
    func finishNotes() async throws {
        for _ in 0..<200 where state.notesBusy.contains(id) { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!state.notesBusy.contains(id))
        #expect(state.error == nil)
    }
    state.updateNotes(callID: id, ifNeeded: true)
    try await finishNotes()
    #expect(state.selected?.generatedNotes == "Default notes")
    state.updateNotes(callID: id, ifNeeded: true)
    #expect(!state.notesBusy.contains(id))
    state.editNotes(callID: id, text: "Focus on the deadline")
    state.updateNotes(callID: id, ifNeeded: true)
    try await finishNotes()
    #expect(state.selected?.generatedNotes == "Guided notes")
    #expect(state.selected?.notes == "Focus on the deadline")
    state.editNotes(callID: id, text: "My edited AI wording", generated: true)
    state.editNotes(callID: id, text: "Focus on the deadline and owner")
    state.updateNotes(callID: id, ifNeeded: true)
    try await finishNotes()
    #expect(state.selected?.generatedNotes == "My edited AI wording")
    #expect(state.selected?.suggestedNotes == "Guided notes")
    #expect(state.selected?.notes == "Focus on the deadline and owner")
    state.updateNotes(callID: id, ifNeeded: true)
    #expect(!state.notesBusy.contains(id))
    let prompts = try String(contentsOf: root.appendingPathComponent("prompts.jsonl"), encoding: .utf8).split(separator: "\n")
    #expect(prompts.count == 3)
    state.flushNoteEdits()
    let stored = try #require(state.library.load().first)
    #expect(stored.generatedNotesSource != nil && stored.suggestedNotesSource != nil)
    #expect(stored.notes == "Focus on the deadline and owner")
}

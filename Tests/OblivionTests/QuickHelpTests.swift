import Foundation
import Testing
@testable import Oblivion

@Test @MainActor func quickHelpUsesCurrentContextAndCannotReappearAfterDismissal() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-quick-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let executable = root.appendingPathComponent("server.py")
    let script = #"""
    #!/usr/bin/env python3
    import json, sys, pathlib, threading, time
    root=pathlib.Path(__file__).parent
    lock=threading.Lock()
    def emit(data):
        with lock: print(json.dumps(data),flush=True)
    def result(rid,result): emit(dict(id=rid,result=result))
    def start(rid,params,tid):
        time.sleep(.18) # Dismiss while turn/start hasn't even acknowledged yet.
        result(rid,dict(turn=dict(id=tid)))
        time.sleep(.18) # Also send completion after interruption, like an in-flight event.
        emit(dict(method='turn/completed',params=dict(threadId=params['threadId'],turnId=tid,turn=dict(id=tid,status='completed',items=[dict(type='agentMessage',phase='final_answer',text=json.dumps(dict(answer='Ask why the forty screens still need a separate paper form.')))]))))
    n=0
    for line in sys.stdin:
        m=json.loads(line); method=m.get('method'); rid=m.get('id'); p=m.get('params',{})
        if rid is None: continue
        with (root/'requests.jsonl').open('a') as f: f.write(json.dumps(m)+'\n')
        r={}
        if method=='account/read': r={'account':{'type':'chatgpt'}}
        elif method=='model/list': r={'data':[dict(model='quick-test',displayName='Quick',supportedReasoningEfforts=[dict(reasoningEffort='none'),dict(reasoningEffort='low')],defaultReasoningEffort='none',inputModalities=['text'])]}
        elif method=='thread/start':
            n+=1; time.sleep(.08); r={'thread':{'id':'thread-'+str(n)}}
        elif method=='turn/start':
            n+=1
            threading.Thread(target=start,args=(rid,p,'turn-'+str(n)),daemon=True).start()
            continue
        result(rid,r)
    """#
    try script.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let service = CodexService(executableURL: executable)
    defer { service.disconnect() }
    try await service.connect()
    let state = AppState(root: root.appendingPathComponent("library"), connect: false, codex: service)
    let id = state.newCall(); state.beginLiveSession(callID: id); state.callStarting = false
    state.modify(id) { $0.notes = "Learn the work behind the screens, not a sales pitch." }
    state.openDirectQuestion()
    state.directQuestion = "What should I ask next?"; state.askDirect()
    // New speech arrives during warm-up. It must be in the eventual request.
    state.receiveSpeech(SpeechUpdate(source: "meeting", text: "Forty screens still require a paper form", start: 10, end: 14, isFinal: true))
    for _ in 0..<150 where state.directBusy { try await Task.sleep(for: .milliseconds(10)) }
    #expect(state.directAnswer.contains("forty screens"))
    state.dismissDirectQuestion()
    #expect(!state.showDirectQuestion && state.directAnswer.isEmpty)
    state.openDirectQuestion()
    #expect(state.directAnswer.isEmpty && state.directQuestion.isEmpty)
    state.directQuestion = "Cancel this one"; state.askDirect()
    try await Task.sleep(for: .milliseconds(120))
    state.dismissDirectQuestion()
    try await Task.sleep(for: .milliseconds(700))
    #expect(!state.showDirectQuestion && !state.directBusy && state.directAnswer.isEmpty)
    state.openDirectQuestion(); state.directQuestion = "Fresh request"; state.askDirect()
    for _ in 0..<150 where state.directBusy { try await Task.sleep(for: .milliseconds(10)) }
    #expect(state.directAnswer.contains("paper form"))
    state.dismissDirectQuestion()
    #expect(!FileManager.default.fileExists(atPath: state.library.directory(id).appendingPathComponent("guidance.jsonl").path)) // No saved Ask history.
    let requests = try String(contentsOf: root.appendingPathComponent("requests.jsonl"), encoding: .utf8).split(separator: "\n").map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
    let threads = requests.filter { $0["method"] as? String == "thread/start" }.compactMap { $0["params"] as? [String: Any] }
    #expect(threads.allSatisfy { $0["ephemeral"] as? Bool == true && $0["baseInstructions"] as? String == LiveContext.quickInstructions })
    #expect(threads.allSatisfy { ($0["config"] as? [String: Any])?["web_search"] as? String == "disabled" })
    let turns = requests.filter { $0["method"] as? String == "turn/start" }.compactMap { $0["params"] as? [String: Any] }
    #expect(turns.count == 3)
    #expect(turns.allSatisfy { ($0["input"] as? [[String: Any]])?.count == 1 && $0["effort"] as? String == "none" })
    #expect((turns.first?["input"] as? [[String: Any]])?.first?["text"] as? String != nil)
    let input = try #require((turns.first?["input"] as? [[String: Any]])?.first?["text"] as? String)
    #expect(input.contains("Forty screens still require a paper form"))
    #expect(input.contains("not a sales pitch"))
    #expect(requests.contains { $0["method"] as? String == "turn/interrupt" })
    // A deadline must return promptly even before the server acknowledges a turn.
    let thread = try await service.thread(cwd: root, live: true)
    let began = Date()
    do { _ = try await service.run(threadID: thread, text: "deadline", live: true, timeoutSeconds: 0.025); Issue.record("Expected a deadline error") }
    catch { #expect(!(error is CancellationError)); #expect(Date().timeIntervalSince(began) < 0.15) }
    try await Task.sleep(for: .milliseconds(450))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MURMUR_LIVE_QUALITY_TEST"] == "1"))
@MainActor func realLiveCoachUsesConcreteEvidenceAndQuickHelpStaysShort() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-live-eval-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let service = CodexService()
    defer { service.disconnect() }
    try await service.connect()
    let session = UUID()
    let cases: [(String, String, [String])] = [
        ("Learning how an insurance adviser works. They do not own claims operations. Avoid pitching.", "I copy the policy details from forty screens onto the paper proposal because our back office still requires that form.", ["paper", "form", "screens", "back office", "copy", "copies", "copied", "policy"]),
        ("Their company adopted automation last year. Who owns cleanup is already answered: claims operations. Learn a concrete example.", "Claims operations owns all cleanup. Yesterday an address mismatch made us reopen a claim and contact the customer twice.", ["address", "mismatch", "reopen", "twice", "yesterday", "customer"]),
        ("This is a learning and referral call with a life insurance salesperson, not a claims buyer. They cannot speak to internal claims metrics.", "I don't work in claims, but my former colleague Priya handles motor claims and offered to speak with you.", ["priya", "colleague", "introduc", "connect", "motor"])
    ]
    for (goal, speech, terms) in cases {
        let segment = TranscriptSegment(sessionID: session, source: "meeting", speaker: "Morgan", start: 10, end: 20, original: speech)
        let thread = try await service.thread(cwd: root, live: true, instructions: LiveContext.coachInstructions)
        let began = Date()
        let raw = try await service.run(threadID: thread, text: "GOAL\n\(goal)\nRECENT CONFIRMED SPEECH\n\(TranscriptQuality.text([segment], includeIDs: true))\nThe counterpart has finished their thought. Choose the most useful specific follow-up.", live: true, effortOverride: "low", schema: LiveCoachingResult.schema)
        let response = try JSONDecoder().decode(LiveCoachingResult.self, from: Data(raw.utf8))
        #expect(response.grounded(in: [segment]))
        #expect(terms.contains { response.recommendation.answer.lowercased().contains($0) })
        #expect(response.recommendation.kind != "LISTEN")
        print("Live coaching \(String(format: "%.2f", Date().timeIntervalSince(began)))s · \(response.recommendation.answer)")
    }
    let thread = try await service.thread(cwd: root, live: true, instructions: LiveContext.quickInstructions)
    let began = Date()
    let raw = try await service.run(threadID: thread, text: "QUESTION\nWhat is the best follow-up right now?\nGOAL\nLearn their workflow, no pitch.\nRECENT SPEECH\nMorgan: We copy the same policy details from forty screens to a paper form because the back office still needs paper.", live: true, timeoutSeconds: 12, schema: LiveContext.quickSchema)
    let json = try #require(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: String])
    let answer = try #require(json["answer"])
    #expect(answer.split(whereSeparator: \.isWhitespace).count <= 55)
    #expect(answer.localizedCaseInsensitiveContains("paper") || answer.localizedCaseInsensitiveContains("screens") || answer.localizedCaseInsensitiveContains("back office"))
    print("Quick help \(String(format: "%.2f", Date().timeIntervalSince(began)))s · \(answer)")
}

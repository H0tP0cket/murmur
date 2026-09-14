import Foundation
import Testing
@testable import Oblivion

@Test @MainActor func chatGPTLoginHandlesSignedOutCancelFailureSuccessAndLogout() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-login-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let executable = root.appendingPathComponent("server.py")
    let fixture = #"""
    #!/usr/bin/env python3
    import json,sys,threading,time
    signed=False
    count=0
    cancelled=set()
    lock=threading.Lock()
    def emit(m):
      with lock: print(json.dumps(m),flush=True)
    def finish(i):
      global signed
      time.sleep(.2)
      if i=='3': signed=True
      emit({'method':'account/login/completed','params':{'loginId':i,'success':i!='2','error':'Cancelled in browser' if i=='2' else None}})
    for raw in sys.stdin:
      m=json.loads(raw); method=m.get('method'); rid=m.get('id'); p=m.get('params',{})
      if rid is None: continue
      result={}
      if method=='account/read': result={'account':{'type':'chatgpt','email':'fixture@example.invalid'} if signed else None}
      elif method=='model/list': result={'data':[{'model':'test-model','displayName':'Test','supportedReasoningEfforts':[{'reasoningEffort':'low'}]}]}
      elif method=='account/login/start':
        count+=1;i=str(count);result={'loginId':i,'authUrl':'https://auth.openai.com/authorize?fixture='+i}
        emit({'id':rid,'result':result});threading.Thread(target=finish,args=(i,),daemon=True).start();continue
      elif method=='account/login/cancel': cancelled.add(p['loginId'])
      elif method=='account/logout': signed=False
      emit({'id':rid,'result':result})
    """#
    try fixture.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let service = CodexService(executableURL: executable, homeURL: root.appendingPathComponent("Codex"))
    defer { service.disconnect() }
    try await service.connect()
    #expect(!service.isConnected && service.models.isEmpty)
    let url = try await service.beginLogin()
    #expect(url.host == "auth.openai.com" && service.isSigningIn)
    await service.cancelLogin()
    try await Task.sleep(for: .milliseconds(350))
    #expect(!service.isConnected && !service.isSigningIn && service.loginURL == nil)
    try await service.beginLogin()
    try await Task.sleep(for: .milliseconds(350))
    #expect(!service.isConnected && service.authenticationError == "Cancelled in browser")
    try await service.beginLogin()
    for _ in 0..<30 where !service.isConnected { try await Task.sleep(for: .milliseconds(50)) }
    #expect(service.isConnected && service.accountEmail == "fixture@example.invalid" && service.models.count == 1)
    try await service.signOut()
    #expect(!service.isConnected && service.accountEmail == nil && service.models.isEmpty)
}

@Test @MainActor func freshLibrariesIsolateCodexAndUpgradesKeepExistingThreads() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-homes-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let fresh = try LibraryStore(root: root.appendingPathComponent("fresh"))
    #expect(CodexRuntime.home(for: fresh) == fresh.root.appendingPathComponent("Codex"))
    try fresh.save(CallRecord(threadID: "created-in-private-home"))
    #expect(CodexRuntime.home(for: fresh) == fresh.root.appendingPathComponent("Codex"))
    let upgrade = try LibraryStore(root: root.appendingPathComponent("legacy"))
    try upgrade.save(CallRecord(title: "Existing call", threadID: "keep-this-thread"))
    #expect(CodexRuntime.home(for: upgrade) == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"))
    #expect(try upgrade.load().first?.threadID == "keep-this-thread")
}

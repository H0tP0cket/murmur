import Foundation
@preconcurrency import AVFoundation
import ScreenCaptureKit
import Speech
import CoreMedia

struct SpeechUpdate {
    var source: String
    var text: String
    var start: Double
    var end: Double
    var isFinal: Bool
}

@MainActor
final class SpeechPipeline {
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var format: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private var nextInputTime: CMTime?
    private(set) var processedDuration = 0.0
    let source: String
    var onResult: (SpeechUpdate) -> Void
    var onError: (String) -> Void

    init(source: String, onResult: @escaping (SpeechUpdate) -> Void, onError: @escaping (String) -> Void) {
        self.source = source; self.onResult = onResult; self.onError = onError
    }

    func start() async throws {
        guard SpeechTranscriber.isAvailable else { throw OblivionError.message("On-device transcription isn’t available on this Mac.") }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else { throw OblivionError.message("English transcription is unavailable.") }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: [.audioTimeRange])
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) { try await installation.downloadAndInstall() }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { throw OblivionError.message("No compatible transcription audio format.") }
        self.format = format
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(500))
        self.continuation = continuation
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self, !Task.isCancelled else { return }
                    self.onResult(SpeechUpdate(source: source, text: String(result.text.characters), start: result.range.start.seconds, end: CMTimeRangeGetEnd(result.range).seconds, isFinal: result.isFinal))
                }
            } catch { if !Task.isCancelled { self?.onError("Transcription interrupted: \(error.localizedDescription)") } }
        }
        try await analyzer.prepareToAnalyze(in: format)
        try await analyzer.start(inputSequence: stream)
    }

    func append(_ buffer: AVAudioPCMBuffer, time: CMTime) {
        guard let format, let continuation else { return }
        let converted: AVAudioPCMBuffer
        if buffer.format == format { converted = buffer }
        else {
            if sourceFormat != buffer.format {
                sourceFormat = buffer.format
                converter = AVAudioConverter(from: buffer.format, to: format)
                converter?.primeMethod = .none
            }
            guard let converter,
                  let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(ceil(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate)) + 256) else { return }
            var consumed = false
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                if consumed { inputStatus.pointee = .noDataNow; return nil }
                consumed = true; inputStatus.pointee = .haveData; return buffer
            }
            guard status != .error, error == nil, output.frameLength > 0 else {
                if let error { onError("Audio conversion failed: \(error.localizedDescription)") }
                return
            }
            converted = output
        }
        processedDuration += Double(converted.frameLength) / format.sampleRate
        // Resampling may round a buffer by one sample. SpeechAnalyzer rejects
        // even a fractional overlap, so use a monotonic clock in its sample rate.
        let scale = Int32(format.sampleRate)
        let requested = CMTimeConvertScale(time, timescale: scale, method: .roundHalfAwayFromZero)
        // Tiny timestamp gaps cause SpeechAnalyzer to finalize mid-word. Snap
        // ordinary resampling/capture jitter to continuity; preserve real gaps.
        let actual = nextInputTime.map { CMTimeSubtract(requested, $0).seconds > 0.08 ? requested : $0 } ?? requested
        nextInputTime = CMTimeAdd(actual, CMTime(value: Int64(converted.frameLength), timescale: scale))
        if case .dropped = continuation.yield(AnalyzerInput(buffer: converted, bufferStartTime: actual)) {
            onError("Transcription fell behind. A short section of audio was dropped.")
        }
    }

    func stop() async {
        continuation?.finish(); continuation = nil
        if let analyzer { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
        if let resultsTask { await resultsTask.value }
        self.resultsTask = nil; analyzer = nil; converter = nil; sourceFormat = nil; nextInputTime = nil
    }
}

@MainActor
final class AudioCapture: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    @Published var status = "Not listening"
    @Published var micLevel: Double = 0
    @Published var meetingLevel: Double = 0
    @Published var isRunning = false
    @Published var localSpeaking = false
    @Published var applications: [(id: String, name: String)] = []
    var onResult: (SpeechUpdate) -> Void = { _ in }
    var onIssue: (String) -> Void = { _ in }
    var onSpeakingChanged: (Bool) -> Void = { _ in }
    private var stream: SCStream?
    private var startID: UUID?
    private var microphone: SpeechPipeline?
    private var meeting: SpeechPipeline?
    private var hostStart = CMTime.zero
    private var lastLocalVoice = Date.distantPast
    private var levelTimer: Timer?
    private var lastLevelUpdate: [String: Date] = [:]
    private var lastIssue = Date.distantPast
    private let audioQueue = DispatchQueue(label: "dev.oblivion.capture", qos: .userInitiated)

    func start(applicationID: String?) async throws {
        guard !isRunning else { return }
        let generation = UUID(); startID = generation
        status = "Allow microphone access if prompted…"
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw OblivionError.message("Allow microphone access in System Settings → Privacy & Security → Microphone, then try again.") }
        try ensureCurrent(generation)
        status = "Allow Screen & System Audio Recording if prompted…"
        let content: SCShareableContent
        do { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) }
        catch { throw OblivionError.message("Allow Screen & System Audio Recording for Oblivion in System Settings, then try again. \(error.localizedDescription)") }
        try ensureCurrent(generation)
        guard let display = content.displays.first else { throw OblivionError.message("No display is available for meeting audio capture.") }
        applications = content.applications.filter { !$0.applicationName.isEmpty && $0.bundleIdentifier != Bundle.main.bundleIdentifier }.map { ($0.bundleIdentifier, $0.applicationName) }.sorted { $0.name < $1.name }
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter: SCContentFilter
        if let applicationID, !applicationID.isEmpty {
            guard let app = content.applications.first(where: { $0.bundleIdentifier == applicationID }) else { throw OblivionError.message("The selected meeting app is not running. Open it, or choose another audio source.") }
            filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        } else { filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: []) }
        let microphone = SpeechPipeline(source: "microphone", onResult: { [weak self] in self?.onResult($0) }, onError: { [weak self] in self?.issue($0) })
        let meeting = SpeechPipeline(source: "meeting", onResult: { [weak self] in self?.onResult($0) }, onError: { [weak self] in self?.issue($0) })
        self.microphone = microphone; self.meeting = meeting
        do {
            status = "Preparing on-device transcription…"
            try await microphone.start()
            try ensureCurrent(generation)
            try await meeting.start()
            try ensureCurrent(generation)
            let configuration = SCStreamConfiguration()
            configuration.width = 2; configuration.height = 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            configuration.queueDepth = 3
            configuration.capturesAudio = true; configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 48000; configuration.channelCount = 1
            configuration.captureMicrophone = true
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: audioQueue)
            self.stream = stream
            hostStart = CMClockGetTime(CMClockGetHostTimeClock())
            try await stream.startCapture()
            try ensureCurrent(generation)
            isRunning = true; status = "Listening on this Mac"
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    let speaking = Date().timeIntervalSince(self.lastLocalVoice) < 0.9
                    if speaking != self.localSpeaking { self.localSpeaking = speaking; self.onSpeakingChanged(speaking) }
                    if Date().timeIntervalSince(self.lastLevelUpdate["microphone"] ?? .distantPast) > 1 { self.micLevel = 0 }
                    if Date().timeIntervalSince(self.lastLevelUpdate["meeting"] ?? .distantPast) > 1 { self.meetingLevel = 0 }
                }
            }
        } catch {
            if startID == generation { await stop() }; throw error
        }
    }

    private func ensureCurrent(_ generation: UUID) throws {
        guard startID == generation, !Task.isCancelled else { throw CancellationError() }
    }

    func stop() async {
        startID = nil
        status = "Finishing transcript…"
        levelTimer?.invalidate(); levelTimer = nil
        if let stream { try? await stream.stopCapture() }
        self.stream = nil
        await microphone?.stop(); await meeting?.stop()
        microphone = nil; meeting = nil
        isRunning = false; localSpeaking = false; micLevel = 0; meetingLevel = 0
        status = "Not listening"
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio || type == .microphone, sampleBuffer.isValid,
              let description = sampleBuffer.formatDescription else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleBuffer.numSamples)) else { return }
        buffer.frameLength = AVAudioFrameCount(sampleBuffer.numSamples)
        let result = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(sampleBuffer.numSamples), into: buffer.mutableAudioBufferList)
        guard result == noErr else { return }
        let pts = sampleBuffer.presentationTimeStamp
        Task { @MainActor [weak self] in self?.consume(buffer, pts: pts, source: type == .microphone ? "microphone" : "meeting") }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.isRunning = false; self?.status = "Audio interrupted"
            self?.issue("Audio capture stopped: \(error.localizedDescription). End and restart the call to reconnect.")
        }
    }

    private func consume(_ buffer: AVAudioPCMBuffer, pts: CMTime, source: String) {
        var level = 0.0
        if let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 {
            var sum: Float = 0
            for index in 0..<Int(buffer.frameLength) { sum += channel[index] * channel[index] }
            level = Double(sqrt(sum / Float(buffer.frameLength)))
        } else if let channel = buffer.int16ChannelData?[0], buffer.frameLength > 0 {
            var sum = 0.0
            for index in 0..<Int(buffer.frameLength) { let v = Double(channel[index]) / 32768; sum += v * v }
            level = sqrt(sum / Double(buffer.frameLength))
        }
        if source == "microphone", level > 0.009 { lastLocalVoice = Date() }
        if Date().timeIntervalSince(lastLevelUpdate[source] ?? .distantPast) > 0.12 {
            lastLevelUpdate[source] = Date()
            if source == "microphone" { micLevel = min(1, level * 8) } else { meetingLevel = min(1, level * 8) }
        }
        let elapsed = CMTimeSubtract(pts, hostStart)
        let time = elapsed.seconds >= 0 && elapsed.seconds.isFinite ? elapsed : .zero
        (source == "microphone" ? microphone : meeting)?.append(buffer, time: time)
    }

    private func issue(_ message: String) {
        guard Date().timeIntervalSince(lastIssue) > 5 else { return }
        lastIssue = Date(); onIssue(message)
    }
}

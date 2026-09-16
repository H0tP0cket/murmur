import AVFoundation
import CSpeexDSP

/// Speex's adaptive filter handles double talk instead of muting one speaker.
/// Serialized by CaptureAudioProcessor. Neither input nor output is saved to disk.
final class AcousticEchoCanceller {
    static let rate = 16000
    static let frameSize = 160
    private let state: OpaquePointer?
    init() {
        state = speex_echo_state_init(Int32(Self.frameSize), 4096)
        var rate = Int32(Self.rate)
        if let state { speex_echo_ctl(state, Int32(SPEEX_ECHO_SET_SAMPLING_RATE), &rate) }
    }
    deinit { if let state { speex_echo_state_destroy(state) } }
    func reset() { if let state { speex_echo_state_reset(state) } }
    func process(microphone: [Int16], reference: [Int16]) -> [Int16] {
        guard let state, microphone.count == Self.frameSize, reference.count == Self.frameSize else { return microphone }
        var output = [Int16](repeating: 0, count: Self.frameSize)
        speex_echo_cancellation(state, microphone, reference, &output)
        return output
    }
}

private struct AudioTimeline {
    // Three seconds of transient, timestamped reference samples. Timestamp tags
    // prevent stale samples being reused after silence, device changes or gaps.
    private var samples = [Int16](repeating: 0, count: 48000)
    private var stamps = [Int64](repeating: .min, count: 48000)
    var end: Int64 = 0
    mutating func append(_ values: [Int16], at start: Int64) {
        for (offset, value) in values.enumerated() {
            let stamp = start + Int64(offset), index = Int(stamp % 48000)
            guard index >= 0 else { continue }
            samples[index] = value; stamps[index] = stamp
        }
        end = max(end, start + Int64(values.count))
    }
    func read(at start: Int64, count: Int) -> [Int16] {
        (0..<count).map { offset in
            let stamp = start + Int64(offset), index = Int(stamp % 48000)
            return index >= 0 && stamps[index] == stamp ? samples[index] : 0
        }
    }
}

private final class CaptureResampler {
    let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var nextTime: Int64?
    func convert(_ input: AVAudioPCMBuffer, pts: CMTime) -> (samples: [Int16], start: Int64, discontinuity: Bool)? {
        guard pts.seconds.isFinite, pts.seconds >= 0 else { return nil }
        let changed = inputFormat != nil && inputFormat != input.format
        if inputFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: format)
            converter?.primeMethod = .none; inputFormat = input.format
        }
        guard let converter,
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(ceil(Double(input.frameLength) * 16000 / input.format.sampleRate)) + 128) else { return nil }
        var consumed = false; var error: NSError?
        let result = converter.convert(to: output, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true; status.pointee = .haveData; return input
        }
        guard result != .error, error == nil, let channel = output.floatChannelData?[0], output.frameLength > 0 else { return nil }
        let requested = Int64((pts.seconds * 16000).rounded())
        let gap = nextTime.map { abs(requested - $0) > 1280 } ?? false
        let start = (gap || changed) ? requested : (nextTime ?? requested)
        let samples = (0..<Int(output.frameLength)).map { i -> Int16 in
            let value = channel[i].isFinite ? channel[i] : 0
            return Int16(max(-32767, min(32767, value * 32767)))
        }
        nextTime = start + Int64(samples.count)
        return (samples, start, gap || changed)
    }
}

struct CapturedAudioFrame {
    var buffer: AVAudioPCMBuffer
    var pts: CMTime
    var source: String
}

/// Runs conversion and echo cancellation on the capture queue, outside the UI.
/// A bounded 120 ms reorder window aligns independently delivered source buffers.
final class CaptureAudioProcessor: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UUID?
    private var streamID: ObjectIdentifier?
    private var microphone = CaptureResampler()
    private var meeting = CaptureResampler()
    private var canceller = AcousticEchoCanceller()
    private var reference = AudioTimeline()
    private var near = AudioTimeline()
    private var pendingStart: Int64?
    private var latestTime: Int64 = 0

    func begin(_ generation: UUID, streamID: ObjectIdentifier? = nil) {
        lock.lock(); defer { lock.unlock() }
        self.generation = generation; self.streamID = streamID
        microphone = CaptureResampler(); meeting = CaptureResampler()
        canceller = AcousticEchoCanceller(); reference = AudioTimeline(); near = AudioTimeline()
        pendingStart = nil; latestTime = 0
    }
    func consume(_ input: AVAudioPCMBuffer, pts: CMTime, source: String, streamID: ObjectIdentifier? = nil) -> [CapturedAudioFrame] {
        lock.lock(); defer { lock.unlock() }
        guard generation != nil, self.streamID == streamID,
              let chunk = (source == "microphone" ? microphone : meeting).convert(input, pts: pts) else { return [] }
        var frames: [CapturedAudioFrame] = []
        latestTime = max(latestTime, chunk.start + Int64(chunk.samples.count))
        if chunk.discontinuity { canceller.reset() }
        if source == "meeting" {
            reference.append(chunk.samples, at: chunk.start)
            if let frame = frame(chunk.samples, start: chunk.start, source: source) { frames.append(frame) }
        } else {
            if chunk.discontinuity { frames += drain(force: true); pendingStart = nil; near = AudioTimeline() }
            if pendingStart == nil { pendingStart = chunk.start }
            near.append(chunk.samples, at: chunk.start)
        }
        frames += drain(force: false)
        return frames
    }
    func finish(_ generation: UUID) -> [CapturedAudioFrame] {
        lock.lock(); defer { lock.unlock() }
        guard self.generation == generation else { return [] }
        let frames = drain(force: true)
        self.generation = nil
        return frames
    }
    private func drain(force: Bool) -> [CapturedAudioFrame] {
        var frames: [CapturedAudioFrame] = []
        let size = Int64(AcousticEchoCanceller.frameSize)
        guard var start = pendingStart else { return [] }
        // A discontinuity must never allocate or loop over an unbounded gap.
        if near.end - start > 32000 { start = near.end - 32000; canceller.reset() }
        while start < near.end {
            let remaining = Int(near.end - start)
            guard force || remaining >= Int(size) else { break }
            guard force || reference.end >= start + size || latestTime - start >= 1920 else { break }
            let mic = near.read(at: start, count: Int(size))
            let far = reference.read(at: start, count: Int(size))
            let cleaned = canceller.process(microphone: mic, reference: far)
            if let frame = frame(Array(cleaned.prefix(min(remaining, Int(size)))), start: start, source: "microphone") { frames.append(frame) }
            start += size
        }
        pendingStart = start
        return frames
    }
    private func frame(_ samples: [Int16], start: Int64, source: String) -> CapturedAudioFrame? {
        guard !samples.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: microphone.format, frameCapacity: AVAudioFrameCount(samples.count)), let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for i in samples.indices { channel[i] = Float(samples[i]) / 32767 }
        return CapturedAudioFrame(buffer: buffer, pts: CMTime(value: start, timescale: 16000), source: source)
    }
}

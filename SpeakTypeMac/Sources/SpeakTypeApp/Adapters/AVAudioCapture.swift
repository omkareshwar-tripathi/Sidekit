// @preconcurrency: AVFAudio predates strict concurrency; the converter input block runs
// synchronously inside convert(), so capturing the buffer there is safe.
@preconcurrency import AVFoundation
import SpeakTypeCore

/// Microphone capture via `AVAudioEngine`. Installs a tap on the input node, converts each
/// buffer to 16 kHz mono Float32 with `AVAudioConverter`, accumulates the samples, and runs
/// the RMS silence gate on stop. Buffer access is lock-guarded because the tap runs on a
/// real-time audio thread while start/stop run on the main thread — hence `@unchecked Sendable`.
final class AVAudioCapture: AudioCapturing, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let targetFormat: AVAudioFormat
    private let lock = NSLock()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private var running = false
    private var tapCallbacks = 0 // diagnostic: how many tap buffers arrived this cycle

    /// Live 0…1 mic level for the recording waveform, delivered on the main actor a few times a
    /// second while recording. Set once before `start()`. Additive — the buffer/gate are
    /// unaffected (same unlocked read pattern as `converter`).
    var onLevel: (@MainActor (Float) -> Void)?

    init() {
        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(16000),
            channels: 1,
            interleaved: false
        )!
    }

    func start() {
        lock.lock(); samples.removeAll(); tapCallbacks = 0; lock.unlock()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        let auth = AVCaptureDevice.authorizationStatus(for: .audio)
        Diag.log("mic.start: authStatus=\(auth.rawValue) inputFormat=\(inputFormat.sampleRate)Hz ch=\(inputFormat.channelCount)")

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
            running = true
        } catch {
            running = false
            Diag.log("mic.start: engine.start FAILED: \(error)")
        }
    }

    func stop() -> CapturedAudio {
        if running {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            running = false
        }
        lock.lock(); let captured = samples; samples.removeAll(); let taps = tapCallbacks; lock.unlock()
        let speech = AudioMath.hasSpeech(captured)
        var peak: Float = 0
        for s in captured { peak = max(peak, abs(s)) }
        Diag.log("mic.stop: taps=\(taps) samples=\(captured.count) peak=\(peak) hasSpeech=\(speech)")
        return CapturedAudio(samples: captured, hasSpeech: speech)
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        lock.lock(); tapCallbacks += 1; lock.unlock()
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        // The whole input buffer is offered once, then "no more data" — a captured `let`
        // box holds the one-shot flag (a captured `var` would warn under strict concurrency).
        let supplied = OneShot()
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied.fired { status.pointee = .noDataNow; return nil }
            supplied.fired = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = out.floatChannelData else { return }

        let frames = Int(out.frameLength)
        let frameSamples = Array(UnsafeBufferPointer(start: channel[0], count: frames))
        lock.lock()
        samples.append(contentsOf: frameSamples)
        lock.unlock()

        // Live waveform meter — peak of this buffer, hopped to the main actor for the UI.
        if let onLevel {
            let level = AudioMath.level(frameSamples)
            Task { @MainActor in onLevel(level) }
        }
    }
}

/// One-shot flag for the converter input block. @unchecked Sendable: the block runs
/// synchronously inside `convert()` on one thread, so the flag is never raced.
private final class OneShot: @unchecked Sendable {
    var fired = false
}

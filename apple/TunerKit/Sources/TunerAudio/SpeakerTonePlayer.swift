import AVFoundation
import TunerCore

/// Plucked-string-like tone: a few harmonics with exponential decay, on its own engine so the
/// microphone graph is untouched.
@MainActor
public final class SpeakerTonePlayer: TonePlayer {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?

    public init() {}

    public func play(hz: Float, seconds: Double) {
        stop()
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord {
            try? session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try? session.setActive(true)
        }
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard sampleRate > 0, let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        else { return }
        let source = Self.makeSource(hz: Double(hz), sampleRate: sampleRate, frames: Int(seconds * sampleRate))
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: mono)
        node = source
        engine.prepare()
        try? engine.start()
    }

    private func stop() {
        if engine.isRunning { engine.stop() }
        if let node {
            engine.detach(node)
            self.node = nil
        }
    }

    /// Nonisolated for the same reason as the microphone sink: the render block runs on the audio thread.
    private nonisolated static func makeSource(hz: Double, sampleRate: Double, frames: Int) -> AVAudioSourceNode {
        let state = ToneState(hz: hz, sampleRate: sampleRate, frames: frames)
        return AVAudioSourceNode { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let data = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            state.render(into: data, count: Int(frameCount))
            return noErr
        }
    }
}

/// Touched only by the render thread after creation.
private final class ToneState: @unchecked Sendable {
    private let step: Double
    private let decay: Double
    private let frames: Int
    private var phase = 0.0
    private var frame = 0

    private static let harmonics: [(Double, Double)] = [(1, 0.6), (2, 0.25), (3, 0.12), (4, 0.06)]

    init(hz: Double, sampleRate: Double, frames: Int) {
        step = 2 * Double.pi * hz / sampleRate
        decay = log(0.001) / Double(max(frames, 1))
        self.frames = frames
    }

    func render(into out: UnsafeMutablePointer<Float>, count: Int) {
        for i in 0..<count {
            guard frame < frames else {
                out[i] = 0
                continue
            }
            let attack = min(1, Double(frame) / 240)
            let envelope = attack * exp(decay * Double(frame))
            var sample = 0.0
            for (multiple, gain) in Self.harmonics {
                sample += gain * sin(phase * multiple)
            }
            out[i] = Float(sample * envelope * 0.5)
            phase += step
            if phase > 2 * Double.pi * 4 { phase -= 2 * Double.pi * 4 }
            frame += 1
        }
    }
}

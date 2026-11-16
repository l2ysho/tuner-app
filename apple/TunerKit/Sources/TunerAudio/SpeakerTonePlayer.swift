import AVFoundation
import TunerCore
import os

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
        do {
            try engine.start()
            Self.log.info(
                "tone \(hz) Hz, mode \(session.mode.rawValue), out \(session.currentRoute.outputs.map(\.portType.rawValue))"
            )
        } catch {
            Self.log.error("tone engine failed: \(error)")
        }
    }

    private static let log = Logger(subsystem: "sk.riviatech.freetuner", category: "tone")

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
/// Phone speakers barely play below ~300 Hz, so the low strings are heard through their harmonics:
/// a sawtooth-like series up to 4 kHz, upper harmonics fading faster like a plucked string.
private final class ToneState: @unchecked Sendable {
    private let step: Double
    private let frames: Int
    private var gains: [Double]
    private let fades: [Double]
    private var phase = 0.0
    private var frame = 0

    private static let topHz = 4000.0
    private static let level = 0.45

    init(hz: Double, sampleRate: Double, frames: Int) {
        step = 2 * Double.pi * hz / sampleRate
        self.frames = frames
        let count = max(1, Int(Self.topHz / hz))
        let baseDecay = log(0.001) / Double(max(frames, 1))
        gains = (1...count).map { Self.level / Double($0) }
        fades = (1...count).map { exp(baseDecay * (1 + 0.15 * Double($0 - 1))) }
    }

    func render(into out: UnsafeMutablePointer<Float>, count: Int) {
        gains.withUnsafeMutableBufferPointer { gains in
            fades.withUnsafeBufferPointer { fades in
                for i in 0..<count {
                    guard frame < frames else {
                        out[i] = 0
                        continue
                    }
                    let attack = min(1, Double(frame) / 240)
                    var sample = 0.0
                    for n in 0..<gains.count {
                        sample += gains[n] * sin(phase * Double(n + 1))
                        gains[n] *= fades[n]
                    }
                    out[i] = Float(sample * attack)
                    phase += step
                    if phase > 2 * Double.pi { phase -= 2 * Double.pi }
                    frame += 1
                }
            }
        }
    }
}

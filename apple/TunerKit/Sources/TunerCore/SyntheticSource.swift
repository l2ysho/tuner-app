import Foundation
import TunerCore

/// Synthetic input for the simulator, screenshots and UI checks. Launch with `-demo <name>`.
struct DemoSignal: Sendable {
    var hz: Double
    /// Peak detune of a slow sine sweep, in cents (0 = steady).
    var sweepCents: Double = 0
    var sweepPeriod: Double = 8
    var silent = false

    static func named(_ name: String, a4: Float = 440) -> DemoSignal? {
        func note(_ midi: Int, _ cents: Double) -> Double {
            Double(midiToHz(midi, a4: a4)) * pow(2, cents / 1200)
        }
        switch name {
        case "flat": return DemoSignal(hz: note(45, -12))
        case "sharp": return DemoSignal(hz: note(55, 18))
        case "intune": return DemoSignal(hz: note(50, 1))
        case "idle": return DemoSignal(hz: 0, silent: true)
        case "sweep": return DemoSignal(hz: note(40, 0), sweepCents: 30)
        default: return nil
        }
    }
}

/// Writes a saw-like tone into the ring at real-time pace. Confined to the analysis queue.
final class DemoGenerator: @unchecked Sendable {
    private let signal: DemoSignal
    private let sampleRate: Double
    private let start = DispatchTime.now().uptimeNanoseconds
    private var produced = 0
    private var phase = 0.0
    private var buffer = [Float](repeating: 0, count: 4800)

    init(signal: DemoSignal, sampleRate: Double) {
        self.signal = signal
        self.sampleRate = sampleRate
    }

    func fill(_ ring: SampleRing) {
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        let count = min(Int(elapsed * sampleRate) - produced, buffer.count)
        guard count > 0 else { return }
        for i in 0..<count {
            let t = Double(produced + i) / sampleRate
            let detune = signal.sweepCents * sin(2 * .pi * t / signal.sweepPeriod)
            let hz = signal.hz * pow(2, detune / 1200)
            phase += 2 * .pi * hz / sampleRate
            if phase > 2 * .pi { phase -= 2 * .pi }
            var sample = 0.0
            if !signal.silent {
                for k in 1...8 { sample += sin(Double(k) * phase) / Double(k) }
            }
            buffer[i] = Float(0.1 * sample)
        }
        produced += count
        buffer.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: count) }
    }
}

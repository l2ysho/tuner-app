import Foundation

/// Synthetic input for the simulator, screenshots and UI checks. Launch with `-demo <name>`.
public struct DemoSignal: Sendable, Equatable {
    public var hz: Double
    /// Peak detune of a slow sine sweep, in cents (0 = steady).
    public var sweepCents: Double = 0
    public var sweepPeriod: Double = 8
    public var silent = false

    public init(hz: Double, sweepCents: Double = 0, sweepPeriod: Double = 8, silent: Bool = false) {
        self.hz = hz
        self.sweepCents = sweepCents
        self.sweepPeriod = sweepPeriod
        self.silent = silent
    }

    public static let names = ["flat", "sharp", "intune", "idle", "sweep"]

    public static func named(_ name: String, a4: Float = 440) -> DemoSignal? {
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

    /// Reads `-demo <name>` from launch arguments.
    public static func fromArguments(_ arguments: [String], a4: Float = 440) -> DemoSignal? {
        guard let i = arguments.firstIndex(of: "-demo"), i + 1 < arguments.count else { return nil }
        return named(arguments[i + 1], a4: a4)
    }
}

/// Pull-based source: writes a saw-like tone at real-time pace whenever the engine pumps it.
@MainActor
public final class SyntheticSource: AudioSource {
    public static let sampleRate = 48_000.0
    public var onEvent: (@MainActor (AudioSourceEvent) -> Void)?
    private let generator: Generator

    public init(_ signal: DemoSignal) {
        generator = Generator(signal: signal, sampleRate: Self.sampleRate)
    }

    public func start(into ring: SampleRing) throws -> Double {
        generator.restart()
        return Self.sampleRate
    }

    public func stop() {}

    public nonisolated func pump(into ring: SampleRing) { generator.fill(ring) }

    /// Confined to the analysis queue once started; `restart` runs before the queue sees it.
    private final class Generator: @unchecked Sendable {
        private let signal: DemoSignal
        private let sampleRate: Double
        private var start = DispatchTime.now().uptimeNanoseconds
        private var produced = 0
        private var phase = 0.0
        private var buffer = [Float](repeating: 0, count: 4800)

        init(signal: DemoSignal, sampleRate: Double) {
            self.signal = signal
            self.sampleRate = sampleRate
        }

        func restart() {
            start = DispatchTime.now().uptimeNanoseconds
            produced = 0
            phase = 0
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
}

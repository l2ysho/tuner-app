internal import TunerCoreCxx

/// One analysed hop: the tuner state plus the raw level, ready for the UI.
public struct TunerReading: Sendable, Equatable {
    public var midi: Int
    /// Index into the active tuning, or -1 in chromatic mode.
    public var stringIndex: Int
    public var hz: Float
    public var cents: Float
    public var voiced: Bool
    public var locked: Bool
    public var idle: Bool
    public var rmsDb: Float

    public init(
        midi: Int, stringIndex: Int, hz: Float, cents: Float, voiced: Bool, locked: Bool, idle: Bool,
        rmsDb: Float
    ) {
        self.midi = midi
        self.stringIndex = stringIndex
        self.hz = hz
        self.cents = cents
        self.voiced = voiced
        self.locked = locked
        self.idle = idle
        self.rmsDb = rmsDb
    }

    public static let idle = TunerReading(
        midi: -1, stringIndex: -1, hz: 0, cents: 0, voiced: false, locked: false, idle: true,
        rmsDb: -120)
}

/// Detector + tuner state machine. Not thread-safe: keep every call on one queue.
public final class PitchPipeline {
    public static let windowSize = 4096

    public let sampleRate: Double
    public private(set) var minHz: Float
    public private(set) var gateDb: Float
    private var detector: tuner.PitchDetector
    private var stateMachine: tuner.Tuner

    public init(sampleRate: Double, minHz: Float = 50, gateDb: Float = -50) {
        self.sampleRate = sampleRate
        self.minHz = minHz
        self.gateDb = gateDb
        detector = tuner.PitchDetector(
            Self.config(sampleRate: sampleRate, minHz: minHz, gateDb: gateDb))
        stateMachine = tuner.Tuner(tuner.TunerConfig())
    }

    private static func config(sampleRate: Double, minHz: Float, gateDb: Float)
        -> tuner.DetectorConfig
    {
        var cfg = tuner.DetectorConfig()
        cfg.sampleRate = Float(sampleRate)
        cfg.window = Int32(windowSize)
        cfg.minHz = minHz
        cfg.gateDb = gateDb
        return cfg
    }

    /// Allocates a new detector; call off the real-time thread.
    public func configureDetector(minHz: Float, gateDb: Float) {
        guard minHz != self.minHz || gateDb != self.gateDb else { return }
        self.minHz = minHz
        self.gateDb = gateDb
        detector = tuner.PitchDetector(
            Self.config(sampleRate: sampleRate, minHz: minHz, gateDb: gateDb))
    }

    public func setStrings(_ hz: [Float]) {
        hz.withUnsafeBufferPointer { buffer in
            stateMachine.setTuning(buffer.baseAddress, buffer.count)
        }
    }

    public func setReference(_ a4Hz: Float) { stateMachine.setReference(a4Hz) }
    public func setTolerance(_ cents: Float) { stateMachine.setTolerance(cents) }
    /// -1 = auto string detection.
    public func setManualString(_ index: Int) { stateMachine.setManualString(Int32(index)) }
    public func reset() { stateMachine.reset() }

    public func process(_ window: UnsafeBufferPointer<Float>, timestamp: Double) -> TunerReading {
        guard let base = window.baseAddress else { return .idle }
        let pitch = detector.process(base, window.count)
        let state = stateMachine.push(pitch, timestamp)
        return TunerReading(
            midi: Int(state.midi), stringIndex: Int(state.stringIndex), hz: state.hz,
            cents: state.cents, voiced: state.voiced, locked: state.locked, idle: state.idle,
            rmsDb: pitch.rmsDb)
    }
}

import TunerDSPC

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

public enum PitchAlgorithm: Sendable {
    case mpm, yin

    var c: tdsp_algorithm { self == .mpm ? TDSP_ALGORITHM_MPM : TDSP_ALGORITHM_YIN }
}

public struct PitchEstimate: Sendable, Equatable {
    public var hz: Float
    public var clarity: Float
    public var rmsDb: Float
    public var voiced: Bool
}

/// Owns one C detector. `process` does not allocate, so it is safe on the audio thread.
public final class PitchDetector {
    public let sampleRate: Double
    private let handle: OpaquePointer

    public init(
        algorithm: PitchAlgorithm = .mpm, sampleRate: Double, window: Int = PitchPipeline.windowSize,
        minHz: Float = 50, gateDb: Float = PitchPipeline.gateDb
    ) {
        var config = tdsp_detector_config_default()
        config.sample_rate = Float(sampleRate)
        config.window = Int32(window)
        config.min_hz = minHz
        config.gate_db = gateDb
        guard let handle = tdsp_detector_create(algorithm.c, &config) else {
            fatalError("tdsp_detector_create failed: out of memory")
        }
        self.sampleRate = sampleRate
        self.handle = handle
    }

    deinit { tdsp_detector_destroy(handle) }

    public func process(_ samples: UnsafeBufferPointer<Float>) -> PitchEstimate {
        let p = tdsp_detector_process(handle, samples.baseAddress, samples.count)
        return PitchEstimate(hz: p.hz, clarity: p.clarity, rmsDb: p.rms_db, voiced: p.voiced)
    }
}

/// Detector + tuner state machine. Not thread-safe: keep every call on one queue.
public final class PitchPipeline {
    public static let windowSize = 4096
    /// Only drops near-silence; noise is rejected by the detector's clarity threshold, not by level.
    public static let gateDb: Float = -80

    public let sampleRate: Double
    public private(set) var minHz: Float
    private var detector: PitchDetector
    private let tuner: OpaquePointer

    public init(sampleRate: Double, minHz: Float = 50) {
        self.sampleRate = sampleRate
        self.minHz = minHz
        detector = PitchDetector(sampleRate: sampleRate, minHz: minHz, gateDb: Self.gateDb)
        guard let tuner = tdsp_tuner_create(nil) else {
            fatalError("tdsp_tuner_create failed: out of memory")
        }
        self.tuner = tuner
    }

    deinit { tdsp_tuner_destroy(tuner) }

    /// Allocates a new detector; call off the real-time thread.
    public func configureDetector(minHz: Float) {
        guard minHz != self.minHz else { return }
        self.minHz = minHz
        detector = PitchDetector(sampleRate: sampleRate, minHz: minHz, gateDb: Self.gateDb)
    }

    public func setStrings(_ hz: [Float]) {
        hz.withUnsafeBufferPointer { tdsp_tuner_set_tuning(tuner, $0.baseAddress, $0.count) }
    }

    public func setReference(_ a4Hz: Float) { tdsp_tuner_set_reference(tuner, a4Hz) }
    public func setTolerance(_ cents: Float) { tdsp_tuner_set_tolerance(tuner, cents) }
    /// -1 = auto string detection.
    public func setManualString(_ index: Int) { tdsp_tuner_set_manual_string(tuner, Int32(index)) }
    public func reset() { tdsp_tuner_reset(tuner) }

    public func process(_ window: UnsafeBufferPointer<Float>, timestamp: Double) -> TunerReading {
        guard window.baseAddress != nil else { return .idle }
        let pitch = detector.process(window)
        let state = tdsp_tuner_push(
            tuner, tdsp_pitch(hz: pitch.hz, clarity: pitch.clarity, rms_db: pitch.rmsDb, voiced: pitch.voiced),
            timestamp)
        return TunerReading(
            midi: Int(state.midi), stringIndex: Int(state.string_index), hz: state.hz,
            cents: state.cents, voiced: state.voiced, locked: state.locked, idle: state.idle,
            rmsDb: pitch.rmsDb)
    }
}

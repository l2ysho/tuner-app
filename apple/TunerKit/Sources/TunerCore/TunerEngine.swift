import Foundation

public struct PipelineConfig: Sendable, Equatable {
    public var strings: [Float]
    public var a4: Float
    public var tolerance: Float
    public var manualString: Int
    public var minHz: Float

    public init(
        strings: [Float], a4: Float, tolerance: Float, manualString: Int, minHz: Float
    ) {
        self.strings = strings
        self.a4 = a4
        self.tolerance = tolerance
        self.manualString = manualString
        self.minHz = minHz
    }
}

/// Audio source → lock-free ring → analysis queue → `onReading`.
///
/// Everything under `queue` (pipeline, timer, pumping) is confined to that serial queue.
/// Sources are started and stopped from the main actor.
public final class TunerEngine: @unchecked Sendable {
    public static let hop = 512

    private let queue = DispatchQueue(label: "tuner.analysis", qos: .userInteractive)
    private let onReading: @Sendable (TunerReading, UInt64) -> Void

    // Main actor.
    @MainActor private var source: (any AudioSource)?
    /// Bumped by `stop()`; readings tagged with an older session are stale and must be dropped.
    @MainActor public private(set) var session: UInt64 = 0

    // Analysis queue.
    private var analyzer: Analyzer?
    private var config: PipelineConfig?
    private var timer: DispatchSourceTimer?
    private var pumped: (any AudioSource)?
    private var lastSent: TunerReading?
    private var sessionTag: UInt64?

    public init(onReading: @escaping @Sendable (TunerReading, UInt64) -> Void) {
        self.onReading = onReading
    }

    @MainActor
    public func start(_ source: any AudioSource) throws {
        stop()
        let ring = SampleRing(capacity: 1 << 15)
        let sampleRate = try source.start(into: ring)
        self.source = source
        let session = session
        queue.async { [self] in
            sessionTag = session
            pumped = source
            let pipeline = PitchPipeline(sampleRate: sampleRate, minHz: config?.minHz ?? 50)
            if let config { Self.configure(pipeline, from: nil, to: config) }
            analyzer = Analyzer(ring: ring, pipeline: pipeline, hop: Self.hop)

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(5), leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            self.timer = timer
        }
    }

    @MainActor
    public func stop() {
        session &+= 1
        source?.stop()
        source = nil
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            analyzer = nil
            pumped = nil
            lastSent = nil
            sessionTag = nil
        }
    }

    public func apply(_ newConfig: PipelineConfig) {
        queue.async { [self] in
            let old = config
            config = newConfig
            if let pipeline = analyzer?.pipeline {
                Self.configure(pipeline, from: old, to: newConfig)
            }
        }
    }

    /// Drops the smoothing history so the next note does not start from the last one.
    public func resetSmoothing() {
        queue.async { [self] in analyzer?.pipeline.reset() }
    }

    private func tick() {
        guard let analyzer, let sessionTag else { return }
        pumped?.pump(into: analyzer.ring)
        guard let reading = analyzer.poll(), reading != lastSent else { return }
        lastSent = reading
        onReading(reading, sessionTag)
    }

    private static func configure(_ p: PitchPipeline, from old: PipelineConfig?, to new: PipelineConfig) {
        p.configureDetector(minHz: new.minHz)
        if old?.a4 != new.a4 { p.setReference(new.a4) }
        if old?.strings != new.strings { p.setStrings(new.strings) }
        if old?.tolerance != new.tolerance { p.setTolerance(new.tolerance) }
        if old?.manualString != new.manualString || old?.strings != new.strings {
            p.setManualString(new.manualString)
        }
    }
}

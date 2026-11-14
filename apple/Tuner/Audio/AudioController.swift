import AVFoundation
import TunerCore

struct PipelineConfig: Sendable, Equatable {
    var strings: [Float]
    var a4: Float
    var tolerance: Float
    var manualString: Int
    var minHz: Float
    var gateDb: Float
}

/// Microphone → lock-free ring → analysis queue → `onReading`.
///
/// Threads: the sink node block runs on the real-time audio thread and only writes into the ring.
/// Everything else under `queue` (pipeline, timer, demo generator) is confined to that serial queue.
/// The engine itself is driven from the main actor.
final class AudioController: @unchecked Sendable {
    static let hop = 512

    private let queue = DispatchQueue(label: "tuner.analysis", qos: .userInteractive)
    private let onReading: @Sendable (TunerReading, UInt64) -> Void
    private let onMicrophoneLost: @MainActor () -> Void

    // Main actor.
    private var engine = AVAudioEngine()
    private var sinkNode: AVAudioSinkNode?
    private var observers: [NSObjectProtocol] = []
    /// Bumped by `stop()`; readings tagged with an older session are stale and must be dropped.
    @MainActor private(set) var session: UInt64 = 0

    // Analysis queue.
    private var analyzer: Analyzer?
    private var config: PipelineConfig?
    private var timer: DispatchSourceTimer?
    private var demo: DemoGenerator?
    private var lastSent: TunerReading?
    private var sessionTag: UInt64?

    /// `onMicrophoneLost` fires when the running microphone path was torn down by the system
    /// (route or format change, media services reset) and needs `startMicrophone()` again.
    @MainActor
    init(
        onReading: @escaping @Sendable (TunerReading, UInt64) -> Void,
        onMicrophoneLost: @escaping @MainActor () -> Void
    ) {
        self.onReading = onReading
        self.onMicrophoneLost = onMicrophoneLost
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) {
                [weak self] note in
                let source = note.object.map { ObjectIdentifier($0 as AnyObject) }
                MainActor.assumeIsolated { self?.engineConfigurationChanged(source: source) }
            },
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.mediaServicesWereReset() }
            },
        ]
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    @MainActor
    private func engineConfigurationChanged(source: ObjectIdentifier?) {
        // The engine stops itself on a format change; a running engine means we already restarted.
        guard source == ObjectIdentifier(engine), sinkNode != nil, !engine.isRunning else { return }
        onMicrophoneLost()
    }

    @MainActor
    private func mediaServicesWereReset() {
        let wasRunning = sinkNode != nil
        stop()
        // Every audio object from before the reset is orphaned.
        engine = AVAudioEngine()
        if wasRunning { onMicrophoneLost() }
    }

    @MainActor
    func startMicrophone() throws {
        stop()
        let session = AVAudioSession.sharedInstance()
        // .measurement turns off the input processing (AGC, noise suppression) that skews pitch.
        try session.setCategory(.record, mode: .measurement)
        try? session.setPreferredSampleRate(48_000)
        try? session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)

        let input = engine.inputNode
        let sampleRate = input.inputFormat(forBus: 0).sampleRate
        guard sampleRate > 0,
            let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        else { throw AudioError.noInput }

        let ring = SampleRing(capacity: 1 << 15)
        let sink = AVAudioSinkNode { _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
            if let data = buffers.first?.mData {
                ring.write(data.assumingMemoryBound(to: Float.self), count: Int(frameCount))
            }
            return noErr
        }
        engine.attach(sink)
        engine.connect(input, to: sink, format: mono)
        sinkNode = sink
        engine.prepare()
        try engine.start()
        startAnalysis(ring: ring, sampleRate: sampleRate, demo: nil, session: self.session)
    }

    @MainActor
    func startDemo(_ signal: DemoSignal) {
        stop()
        let sampleRate = 48_000.0
        startAnalysis(
            ring: SampleRing(capacity: 1 << 15), sampleRate: sampleRate,
            demo: DemoGenerator(signal: signal, sampleRate: sampleRate), session: session)
    }

    @MainActor
    func stop() {
        session &+= 1
        if engine.isRunning { engine.stop() }
        if let sinkNode {
            engine.disconnectNodeInput(sinkNode)
            engine.detach(sinkNode)
            self.sinkNode = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            analyzer = nil
            demo = nil
            lastSent = nil
            sessionTag = nil
        }
    }

    func apply(_ newConfig: PipelineConfig) {
        queue.async { [self] in
            let old = config
            config = newConfig
            if let pipeline = analyzer?.pipeline {
                Self.configure(pipeline, from: old, to: newConfig)
            }
        }
    }

    private func startAnalysis(ring: SampleRing, sampleRate: Double, demo: DemoGenerator?, session: UInt64) {
        queue.async { [self] in
            sessionTag = session
            let pipeline = PitchPipeline(
                sampleRate: sampleRate, minHz: config?.minHz ?? 50, gateDb: config?.gateDb ?? -50)
            if let config { Self.configure(pipeline, from: nil, to: config) }
            analyzer = Analyzer(ring: ring, pipeline: pipeline, hop: Self.hop)
            self.demo = demo

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(5), leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            self.timer = timer
        }
    }

    private func tick() {
        guard let analyzer, let sessionTag else { return }
        demo?.fill(analyzer.ring)
        guard let reading = analyzer.poll(), reading != lastSent else { return }
        lastSent = reading
        onReading(reading, sessionTag)
    }

    private static func configure(_ p: PitchPipeline, from old: PipelineConfig?, to new: PipelineConfig) {
        p.configureDetector(minHz: new.minHz, gateDb: new.gateDb)
        if old?.a4 != new.a4 { p.setReference(new.a4) }
        if old?.strings != new.strings { p.setStrings(new.strings) }
        if old?.tolerance != new.tolerance { p.setTolerance(new.tolerance) }
        if old?.manualString != new.manualString || old?.strings != new.strings {
            p.setManualString(new.manualString)
        }
    }

    enum AudioError: Error {
        case noInput
    }
}

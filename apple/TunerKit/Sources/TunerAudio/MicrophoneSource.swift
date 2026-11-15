import AVFoundation
import TunerCore

/// Microphone input through AVAudioEngine. The sink block runs on the real-time audio thread and
/// only writes into the ring: no allocation, no locks, no Objective-C messaging there.
@MainActor
public final class MicrophoneSource: AudioSource {
    public var onEvent: (@MainActor (AudioSourceEvent) -> Void)?

    private var engine = AVAudioEngine()
    private var sinkNode: AVAudioSinkNode?
    private var observers: [NSObjectProtocol] = []

    public enum Failure: Error { case noInput }

    public init() {
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
            center.addObserver(
                forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
            ) { [weak self] note in
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let ended = raw == AVAudioSession.InterruptionType.ended.rawValue
                MainActor.assumeIsolated { self?.onEvent?(ended ? .resumed : .interrupted) }
            },
        ]
    }

    isolated deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    public func start(into ring: SampleRing) throws -> Double {
        stop()
        let session = AVAudioSession.sharedInstance()
        // .measurement turns off the input processing (AGC, noise suppression) that skews pitch.
        // .playAndRecord so the reference tone can play without a category switch, which would
        // restart this engine.
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try? session.setPreferredSampleRate(48_000)
        try? session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)

        let input = engine.inputNode
        let sampleRate = input.inputFormat(forBus: 0).sampleRate
        guard sampleRate > 0,
            let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        else { throw Failure.noInput }

        let sink = Self.makeSink(writingTo: ring)
        engine.attach(sink)
        engine.connect(input, to: sink, format: mono)
        sinkNode = sink
        engine.prepare()
        try engine.start()
        return sampleRate
    }

    public func stop() {
        if engine.isRunning { engine.stop() }
        if let sinkNode {
            engine.disconnectNodeInput(sinkNode)
            engine.detach(sinkNode)
            self.sinkNode = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    public nonisolated func pump(into ring: SampleRing) {}

    /// Must stay nonisolated: a block formed inside a @MainActor method inherits that isolation,
    /// and Swift 6 traps when the real-time audio thread calls it.
    private nonisolated static func makeSink(writingTo ring: SampleRing) -> AVAudioSinkNode {
        AVAudioSinkNode { _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
            if let data = buffers.first?.mData {
                ring.write(data.assumingMemoryBound(to: Float.self), count: Int(frameCount))
            }
            return noErr
        }
    }

    private func engineConfigurationChanged(source: ObjectIdentifier?) {
        // The engine stops itself on a format change; a running engine means we already restarted.
        guard source == ObjectIdentifier(engine), sinkNode != nil, !engine.isRunning else { return }
        onEvent?(.lost)
    }

    private func mediaServicesWereReset() {
        let wasRunning = sinkNode != nil
        stop()
        // Every audio object from before the reset is orphaned.
        engine = AVAudioEngine()
        if wasRunning { onEvent?(.lost) }
    }
}

@MainActor
public final class SystemMicrophonePermission: MicrophonePermission {
    public init() {}

    public var status: MicrophonePermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        default: .undetermined
        }
    }

    public func request() async -> Bool { await AVAudioApplication.requestRecordPermission() }
}

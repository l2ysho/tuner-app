/// Pulls hops from a `SampleRing` and runs the pipeline over the latest window.
/// Not thread-safe: call `poll()` and touch `pipeline` from one queue only.
public final class Analyzer {
    public let ring: SampleRing
    public let pipeline: PitchPipeline
    public let hop: Int
    private let window: UnsafeMutablePointer<Float>
    private var processedEnd = 0

    /// If the reader falls this many hops behind, it skips to the newest audio.
    private let maxBacklogHops = 4

    public init(ring: SampleRing, pipeline: PitchPipeline, hop: Int = 512) {
        precondition(ring.capacity >= PitchPipeline.windowSize * 2)
        self.ring = ring
        self.pipeline = pipeline
        self.hop = hop
        window = .allocate(capacity: PitchPipeline.windowSize)
    }

    deinit { window.deallocate() }

    /// Processes every complete hop that is available and returns the newest reading.
    public func poll() -> TunerReading? {
        let written = ring.totalWritten
        if written - processedEnd > maxBacklogHops * hop {
            processedEnd = max(0, written - hop)
        }
        var latest: TunerReading?
        while processedEnd + hop <= written {
            processedEnd += hop
            guard processedEnd >= PitchPipeline.windowSize,
                ring.read(endingAt: processedEnd, count: PitchPipeline.windowSize, into: window)
            else { continue }
            latest = pipeline.process(
                UnsafeBufferPointer(start: window, count: PitchPipeline.windowSize),
                timestamp: Double(processedEnd) / pipeline.sampleRate)
        }
        return latest
    }
}

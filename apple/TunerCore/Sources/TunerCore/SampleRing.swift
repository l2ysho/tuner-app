import Foundation
import Synchronization

/// Single-producer / single-consumer ring of mono samples.
/// `write` is real-time safe: no locks, no allocation.
public final class SampleRing: @unchecked Sendable {
    public let capacity: Int
    private let mask: Int
    private let storage: UnsafeMutablePointer<Float>
    /// Total samples ever written. Positions are absolute, so readers can detect overruns.
    private let written = Atomic<Int>(0)

    public init(capacity: Int) {
        precondition(capacity > 0 && capacity & (capacity - 1) == 0, "capacity must be 2^n")
        self.capacity = capacity
        mask = capacity - 1
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit { storage.deallocate() }

    public var totalWritten: Int { written.load(ordering: .acquiring) }

    public func write(_ source: UnsafePointer<Float>, count: Int) {
        let start = written.load(ordering: .relaxed)
        var done = 0
        while done < count {
            let at = (start + done) & mask
            let chunk = min(count - done, capacity - at)
            (storage + at).update(from: source + done, count: chunk)
            done += chunk
        }
        written.store(start + count, ordering: .releasing)
    }

    /// Copies `count` samples ending at absolute position `end`.
    /// Returns false when they are not written yet or were already overwritten.
    public func read(endingAt end: Int, count: Int, into destination: UnsafeMutablePointer<Float>)
        -> Bool
    {
        let begin = end - count
        guard count <= capacity, begin >= 0, end <= totalWritten,
            totalWritten - begin <= capacity
        else { return false }
        var done = 0
        while done < count {
            let at = (begin + done) & mask
            let chunk = min(count - done, capacity - at)
            (destination + done).update(from: storage + at, count: chunk)
            done += chunk
        }
        return totalWritten - begin <= capacity
    }
}

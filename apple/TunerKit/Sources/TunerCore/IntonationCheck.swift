import Foundation

/// 12th-fret intonation check: capture the harmonic, then the fretted note, and compare.
/// A fretted note sharp of the harmonic means the speaking length is too short.
public struct IntonationCheck: Sendable {
    public enum Step: Sendable, Equatable { case harmonic, fretted, done }

    public enum Verdict: Sendable, Equatable {
        case ok
        /// Fretted note is sharp: lengthen the string, saddle away from the neck.
        case moveSaddleBack
        /// Fretted note is flat: shorten the string, saddle toward the neck.
        case moveSaddleForward
    }

    /// What the screen shows; changes a few times per capture, not on every reading.
    public struct Status: Sendable, Equatable {
        public var step: Step
        public var harmonicCents: Float?
        public var frettedCents: Float?
        /// 0…1 in tenths while a note is being captured.
        public var progress: Double
        /// After a capture the string has to go quiet before the next one starts.
        public var waitingForSilence: Bool

        public var difference: Float? {
            guard let harmonicCents, let frettedCents else { return nil }
            return frettedCents - harmonicCents
        }

        public var verdict: Verdict? {
            guard let difference else { return nil }
            if abs(difference) <= IntonationCheck.okCents { return .ok }
            return difference > 0 ? .moveSaddleBack : .moveSaddleForward
        }
    }

    public static let settleSec = 0.3
    public static let captureSec = 0.6
    public static let okCents: Float = 2

    public private(set) var status = Status(
        step: .harmonic, harmonicCents: nil, frettedCents: nil, progress: 0, waitingForSilence: false)

    private var voicedSince: Double?
    private var sum: Float = 0
    private var count = 0

    public init() {}

    public mutating func push(cents: Float, voiced: Bool, time: Double) {
        guard status.step != .done else { return }
        guard voiced else {
            status.waitingForSilence = false
            resetCapture()
            return
        }
        if status.waitingForSilence { return }
        let since = voicedSince ?? time
        voicedSince = since
        let elapsed = time - since - Self.settleSec
        guard elapsed >= 0 else { return }
        sum += cents
        count += 1
        status.progress = min(1, (elapsed / Self.captureSec * 10).rounded(.down) / 10)
        guard elapsed >= Self.captureSec else { return }

        let mean = sum / Float(count)
        if status.step == .harmonic {
            status.harmonicCents = mean
            status.step = .fretted
            status.waitingForSilence = true
        } else {
            status.frettedCents = mean
            status.step = .done
        }
        resetCapture()
    }

    public mutating func restart() { self = IntonationCheck() }

    private mutating func resetCapture() {
        voicedSince = nil
        sum = 0
        count = 0
        status.progress = 0
    }
}

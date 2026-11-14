public enum TuneState: Sendable, Equatable {
    case idle, flat, sharp, inTune
}

/// Everything the main screen shows, derived from one reading. Pure, so it is unit-tested.
public struct TunerDisplay: Sendable, Equatable {
    public static let tickCount = 21
    public static let centsPerTick: Float = 5
    public static let degreesPerTick: Double = 8

    public struct Tick: Sendable, Equatable {
        public let index: Int  // -10 ... 10
        public let lit: Bool
        public var isCentre: Bool { index == 0 }
        public var degrees: Double { Double(index) * TunerDisplay.degreesPerTick }
    }

    public let state: TuneState
    public let letter: String
    public let octave: String
    public let cents: Int
    public let status: String
    public let ticks: [Tick]
    public let activeString: Int?
    public let accessibilityLabel: String

    public init(reading: TunerReading, tuning: Tuning, accidentals: Accidentals, manualString: Int?) {
        let idle = reading.idle || reading.midi < 0
        let c = max(-50, min(50, reading.cents))
        let rounded = Int(c.rounded())
        cents = idle ? 0 : rounded

        if idle {
            state = .idle
        } else if reading.locked {
            state = .inTune
        } else {
            state = c < 0 ? .flat : .sharp
        }

        if idle {
            letter = "–"
            octave = ""
        } else {
            let name = NoteName(midi: reading.midi, accidentals: accidentals)
            letter = name.letter
            octave = String(name.octave)
        }

        let magnitude = abs(rounded)
        switch state {
        case .idle: status = "PLAY A STRING"
        case .inTune: status = "IN TUNE"
        case .flat: status = "−\(magnitude)¢  ▲"
        case .sharp: status = "+\(magnitude)¢  ▼"
        }

        let locked = state == .inTune
        ticks = (-10...10).map { i in
            let v = Float(i) * Self.centsPerTick
            let lit: Bool
            if idle {
                lit = false
            } else if i == 0 {
                lit = locked
            } else {
                lit = !locked && ((c < 0 && v < 0 && v >= c - 2) || (c > 0 && v > 0 && v <= c + 2))
            }
            return Tick(index: i, lit: lit)
        }

        if let manualString {
            activeString = manualString
        } else if !idle, reading.stringIndex >= 0, reading.stringIndex < tuning.notes.count {
            activeString = reading.stringIndex
        } else {
            activeString = nil
        }

        switch state {
        case .idle: accessibilityLabel = "No note. Play a string."
        case .inTune: accessibilityLabel = "\(letter) \(octave), in tune"
        case .flat: accessibilityLabel = "\(letter) \(octave), \(magnitude) cents flat, tune up"
        case .sharp: accessibilityLabel = "\(letter) \(octave), \(magnitude) cents sharp, tune down"
        }
    }
}

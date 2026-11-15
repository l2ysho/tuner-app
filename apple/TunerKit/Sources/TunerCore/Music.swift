import Foundation

public enum Accidentals: String, CaseIterable, Sendable {
    case sharps, flats
}

public struct NoteName: Equatable, Sendable {
    /// Letter plus accidental, e.g. "C♯" or "E♭".
    public let letter: String
    public let octave: Int

    private static let sharpNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    private static let flatNames = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]

    public init(midi: Int, accidentals: Accidentals) {
        let pitchClass = ((midi % 12) + 12) % 12
        let names = accidentals == .sharps ? Self.sharpNames : Self.flatNames
        letter = names[pitchClass]
        octave = Int((Double(midi) / 12).rounded(.down)) - 1
    }
}

public func midiToHz(_ midi: Int, a4: Float = 440) -> Float {
    a4 * Float(pow(2.0, Double(midi - 69) / 12.0))
}

public enum Instrument: String, CaseIterable, Identifiable, Sendable {
    case guitar, bass, ukulele, chromatic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .guitar: "Guitar"
        case .bass: "Bass"
        case .ukulele: "Ukulele"
        case .chromatic: "Chromatic"
        }
    }

    /// Lowest pitch the detector looks for. Bass needs a longer lag range; chromatic covers both.
    public var minHz: Float { self == .bass || self == .chromatic ? 28 : 50 }
}

public struct Tuning: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let instrument: Instrument
    /// MIDI notes, lowest-pitched string first (re-entrant ukulele keeps playing order).
    public let notes: [Int]
    /// Flat names read more naturally for down-tuned presets.
    public let accidentals: Accidentals

    public init(
        id: String, name: String, instrument: Instrument, notes: [Int],
        accidentals: Accidentals = .sharps
    ) {
        self.id = id
        self.name = name
        self.instrument = instrument
        self.notes = notes
        self.accidentals = accidentals
    }

    /// No strings: the tuner names the nearest note instead of matching a string.
    public var isChromatic: Bool { notes.isEmpty }

    public func frequencies(a4: Float) -> [Float] { notes.map { midiToHz($0, a4: a4) } }

    public func noteNames(_ accidentals: Accidentals? = nil) -> [NoteName] {
        notes.map { NoteName(midi: $0, accidentals: accidentals ?? self.accidentals) }
    }

    /// "E A D G B E" style label.
    public var spacedLetters: String { noteNames().map(\.letter).joined(separator: " ") }
    /// "EADGBE" style label.
    public var compactLetters: String { noteNames().map(\.letter).joined() }
}

extension Tuning {
    public static let standard = Tuning(
        id: "guitar.standard", name: "Standard", instrument: .guitar,
        notes: [40, 45, 50, 55, 59, 64])

    public static let all: [Tuning] = [
        standard,
        Tuning(id: "guitar.dropD", name: "Drop D", instrument: .guitar, notes: [38, 45, 50, 55, 59, 64]),
        Tuning(
            id: "guitar.halfDown", name: "Half Step Down", instrument: .guitar,
            notes: [39, 44, 49, 54, 58, 63], accidentals: .flats),
        Tuning(id: "guitar.fullDown", name: "Full Step Down", instrument: .guitar, notes: [38, 43, 48, 53, 57, 62]),
        Tuning(id: "guitar.dropC", name: "Drop C", instrument: .guitar, notes: [36, 43, 48, 53, 57, 62]),
        Tuning(id: "guitar.dadgad", name: "DADGAD", instrument: .guitar, notes: [38, 45, 50, 55, 57, 62]),
        Tuning(id: "guitar.openG", name: "Open G", instrument: .guitar, notes: [38, 43, 50, 55, 59, 62]),

        Tuning(id: "bass.standard", name: "Standard", instrument: .bass, notes: [28, 33, 38, 43]),
        Tuning(id: "bass.dropD", name: "Drop D", instrument: .bass, notes: [26, 33, 38, 43]),
        Tuning(
            id: "bass.halfDown", name: "Half Step Down", instrument: .bass, notes: [27, 32, 37, 42],
            accidentals: .flats),
        Tuning(id: "bass.fiveString", name: "5-String", instrument: .bass, notes: [23, 28, 33, 38, 43]),

        Tuning(id: "ukulele.standard", name: "Standard", instrument: .ukulele, notes: [67, 60, 64, 69]),
        Tuning(id: "ukulele.lowG", name: "Low G", instrument: .ukulele, notes: [55, 60, 64, 69]),
        Tuning(id: "ukulele.baritone", name: "Baritone", instrument: .ukulele, notes: [50, 55, 59, 64]),

        chromatic,
    ]

    public static let chromatic = Tuning(id: "chromatic", name: "Chromatic", instrument: .chromatic, notes: [])

    public static func presets(for instrument: Instrument) -> [Tuning] {
        all.filter { $0.instrument == instrument }
    }

    public static func with(id: String) -> Tuning? { all.first { $0.id == id } }
}

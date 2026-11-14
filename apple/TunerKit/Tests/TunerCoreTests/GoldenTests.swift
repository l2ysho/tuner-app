import Foundation
import Testing

@testable import TunerCore

private let sampleRate = 48_000.0
private let window = PitchPipeline.windowSize

private func cents(_ hz: Float, _ reference: Double) -> Double { 1200 * log2(Double(hz) / reference) }

private func tone(_ hz: Double, harmonics: Int, noiseDb: Double? = nil) -> [Float] {
    var rng = SystemRandomNumberGenerator()
    let noiseAmp = noiseDb.map { pow(10, $0 / 20) * sqrt(3.0) } ?? 0
    return (0..<window).map { i in
        let t = Double(i) / sampleRate
        var s = 0.0
        for k in 1...harmonics { s += sin(2 * .pi * hz * Double(k) * t + 0.7 * Double(k)) / Double(k) }
        s *= 0.1
        if noiseAmp > 0 { s += Double.random(in: -noiseAmp...noiseAmp, using: &rng) }
        return Float(s)
    }
}

/// Standard EADGBE, drop D's low D2 and the 7-string low B1.
private let goldenStrings: [(name: String, hz: Double)] = [
    ("E2", 82.4069), ("A2", 110.0), ("D3", 146.832), ("G3", 195.998), ("B3", 246.942),
    ("E4", 329.628), ("D2", 73.4162), ("B1", 61.7354),
]

@Test(arguments: [PitchAlgorithm.mpm, .yin])
func goldenStringsThroughTheCAPI(_ algorithm: PitchAlgorithm) {
    let detector = PitchDetector(algorithm: algorithm, sampleRate: sampleRate)
    for string in goldenStrings {
        for harmonics in [1, 8] {
            // -60 dBFS noise under a -20 dBFS tone: 40 dB SNR, the C++ golden threshold.
            let samples = tone(string.hz, harmonics: harmonics, noiseDb: harmonics > 1 ? -60 : nil)
            let p = samples.withUnsafeBufferPointer { detector.process($0) }
            #expect(p.voiced, "\(string.name) harmonics=\(harmonics) not voiced")
            #expect(
                abs(cents(p.hz, string.hz)) <= 0.5,
                "\(string.name) harmonics=\(harmonics): \(p.hz) Hz is \(cents(p.hz, string.hz)) c off")
        }
    }
}

@Test(arguments: [PitchAlgorithm.mpm, .yin])
func silenceHasLowConfidence(_ algorithm: PitchAlgorithm) {
    let detector = PitchDetector(algorithm: algorithm, sampleRate: sampleRate)
    let silence = [Float](repeating: 0, count: window)
    let p = silence.withUnsafeBufferPointer { detector.process($0) }
    #expect(!p.voiced)
    #expect(p.clarity < 0.5)
}

// MARK: - Recorded fixtures

/// WAV files in /fixtures named `<note>_<anything>.wav`, e.g. `E2_clean.wav`, `A2_distorted.wav`.
/// The test is skipped while the folder has no recordings.
enum Fixtures {
    static let folder = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "fixtures")

    static var files: [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.pathExtension.lowercased() == "wav" }.sorted { $0.path < $1.path }
    }

    static func expectedHz(_ file: URL) -> Double? {
        let name = file.deletingPathExtension().lastPathComponent.split(separator: "_").first.map(String.init) ?? ""
        let letters = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        guard let first = name.first, let base = letters[String(first)], let octave = Int(String(name.last!)) else {
            return nil
        }
        let accidental = name.contains("#") ? 1 : (name.dropFirst().contains("b") ? -1 : 0)
        let midi = 12 * (octave + 1) + base + accidental
        return 440 * pow(2, Double(midi - 69) / 12)
    }
}

@Test(.enabled(if: !Fixtures.files.isEmpty, "no recordings in /fixtures yet"))
func recordedFixturesAreWithinTwoCents() throws {
    for file in Fixtures.files {
        let expected = try #require(Fixtures.expectedHz(file), "cannot read a note from \(file.lastPathComponent)")
        let wav = try WAV(contentsOf: file)
        let detector = PitchDetector(sampleRate: wav.sampleRate)
        // Skip the attack: analyse a window 0.5 s into the note.
        let start = min(Int(wav.sampleRate * 0.5), max(0, wav.samples.count - window))
        let slice = Array(wav.samples[start..<min(start + window, wav.samples.count)])
        let p = slice.withUnsafeBufferPointer { detector.process($0) }
        #expect(p.voiced, "\(file.lastPathComponent) not voiced")
        #expect(abs(cents(p.hz, expected)) <= 2, "\(file.lastPathComponent): \(p.hz) Hz vs \(expected) Hz")
    }
}

/// Minimal reader: PCM 16/24/32-bit integer or 32-bit float, first channel only.
struct WAV {
    let sampleRate: Double
    let samples: [Float]

    struct Unsupported: Error { let reason: String }

    init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        func u32(_ o: Int) -> UInt32 { data[o..<o + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } }
        func u16(_ o: Int) -> UInt16 { data[o..<o + 2].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) } }
        guard data.count > 12, String(bytes: data[0..<4], encoding: .ascii) == "RIFF" else {
            throw Unsupported(reason: "not RIFF")
        }
        var offset = 12
        var format: (tag: UInt16, channels: Int, rate: Double, bits: Int)?
        var body: Range<Int>?
        while offset + 8 <= data.count {
            let id = String(bytes: data[offset..<offset + 4], encoding: .ascii)
            let size = Int(u32(offset + 4))
            let payload = offset + 8
            if id == "fmt " {
                format = (u16(payload), Int(u16(payload + 2)), Double(u32(payload + 4)), Int(u16(payload + 14)))
            } else if id == "data" {
                body = payload..<min(payload + size, data.count)
            }
            offset = payload + size + (size & 1)
        }
        guard let format, let body else { throw Unsupported(reason: "missing fmt or data chunk") }
        let bytes = format.bits / 8
        let frame = bytes * format.channels
        var out: [Float] = []
        out.reserveCapacity(body.count / frame)
        var i = body.lowerBound
        while i + bytes <= body.upperBound {
            switch (format.tag, format.bits) {
            case (3, 32):
                out.append(data[i..<i + 4].withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
            case (_, 16):
                out.append(Float(Int16(bitPattern: u16(i))) / 32768)
            case (_, 24):
                let v = Int32(data[i]) | Int32(data[i + 1]) << 8 | Int32(Int8(bitPattern: data[i + 2])) << 16
                out.append(Float(v) / 8_388_608)
            case (_, 32):
                out.append(Float(Int32(bitPattern: u32(i))) / 2_147_483_648)
            default:
                throw Unsupported(reason: "format \(format.tag) / \(format.bits) bit")
            }
            i += frame
        }
        sampleRate = format.rate
        samples = out
    }
}

@Test func wavReaderRoundTripsSixteenBitPCM() throws {
    let samples = tone(110, harmonics: 4)
    var data = Data()
    func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    data.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + samples.count * 2))
    data.append(contentsOf: Array("WAVEfmt ".utf8)); put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
    put(UInt32(48_000)); put(UInt32(96_000)); put(UInt16(2)); put(UInt16(16))
    data.append(contentsOf: Array("data".utf8)); put(UInt32(samples.count * 2))
    for s in samples { put(Int16(max(-1, min(1, s)) * 32767)) }
    let url = FileManager.default.temporaryDirectory.appending(path: "A2_roundtrip.wav")
    try data.write(to: url)

    let wav = try WAV(contentsOf: url)
    #expect(wav.sampleRate == 48_000)
    #expect(wav.samples.count == samples.count)
    #expect(Fixtures.expectedHz(url).map { abs($0 - 110) < 0.001 } == true)
    let p = wav.samples.withUnsafeBufferPointer { PitchDetector(sampleRate: wav.sampleRate).process($0) }
    #expect(abs(cents(p.hz, 110)) <= 0.5)
}

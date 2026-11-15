import Foundation
import Testing

@testable import TunerCore

private func sine(_ hz: Double, sampleRate: Double, count: Int, start: Int = 0) -> [Float] {
    (0..<count).map { Float(0.3 * sin(2 * .pi * hz * Double(start + $0) / sampleRate)) }
}

@Test func noteNamesUseSharpsOrFlats() {
    #expect(NoteName(midi: 69, accidentals: .sharps) == NoteName(midi: 69, accidentals: .flats))
    #expect(NoteName(midi: 61, accidentals: .sharps).letter == "C♯")
    #expect(NoteName(midi: 61, accidentals: .flats).letter == "D♭")
    #expect(NoteName(midi: 40, accidentals: .sharps).octave == 2)
    #expect(NoteName(midi: 23, accidentals: .sharps).octave == 0)
}

@Test func presetsCoverEveryInstrument() {
    for instrument in Instrument.allCases {
        #expect(!Tuning.presets(for: instrument).isEmpty)
    }
    #expect(Set(Tuning.all.map(\.id)).count == Tuning.all.count)
    #expect(Tuning.standard.compactLetters == "EADGBE")
    #expect(Tuning.with(id: "guitar.halfDown")?.spacedLetters == "E♭ A♭ D♭ G♭ B♭ E♭")
}

@Test func frequenciesFollowReference() {
    let hz = Tuning.standard.frequencies(a4: 440)
    #expect(abs(hz[0] - 82.4069) < 0.001)
    #expect(abs(Tuning.standard.frequencies(a4: 432)[5] - 329.628 * 432 / 440) < 0.01)
}

@Test func pipelineDetectsAString() {
    let pipeline = PitchPipeline(sampleRate: 48000)
    pipeline.setStrings(Tuning.standard.frequencies(a4: 440))
    let samples = sine(110 * pow(2, -10.0 / 1200), sampleRate: 48000, count: PitchPipeline.windowSize)
    let reading = samples.withUnsafeBufferPointer { pipeline.process($0, timestamp: 0) }
    #expect(reading.voiced)
    #expect(reading.stringIndex == 1)
    #expect(reading.midi == 45)
    #expect(abs(reading.cents + 10) < 0.5)
}

@Test func silenceIsUnvoiced() {
    let pipeline = PitchPipeline(sampleRate: 48000)
    let samples = [Float](repeating: 0, count: PitchPipeline.windowSize)
    let reading = samples.withUnsafeBufferPointer { pipeline.process($0, timestamp: 0) }
    #expect(!reading.voiced)
    #expect(reading.idle)
}

@Test func ringWrapsAndDetectsOverrun() {
    let ring = SampleRing(capacity: 8)
    let data: [Float] = (0..<12).map(Float.init)
    data.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: 12) }
    var out = [Float](repeating: -1, count: 4)
    let ok = out.withUnsafeMutableBufferPointer { ring.read(endingAt: 12, count: 4, into: $0.baseAddress!) }
    #expect(ok)
    #expect(out == [8, 9, 10, 11])
    let stale = out.withUnsafeMutableBufferPointer { ring.read(endingAt: 6, count: 4, into: $0.baseAddress!) }
    #expect(!stale)
    let future = out.withUnsafeMutableBufferPointer { ring.read(endingAt: 13, count: 4, into: $0.baseAddress!) }
    #expect(!future)
}

@Test func analyzerReadsHopsFromTheRing() {
    let ring = SampleRing(capacity: 16384)
    let pipeline = PitchPipeline(sampleRate: 48000)
    let analyzer = Analyzer(ring: ring, pipeline: pipeline, hop: 512)
    #expect(analyzer.poll() == nil)

    var position = 0
    var readings: [TunerReading] = []
    for _ in 0..<12 {
        let block = sine(196, sampleRate: 48000, count: 512, start: position)
        position += 512
        block.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: 512) }
        if let r = analyzer.poll() { readings.append(r) }
    }
    #expect(readings.count == 12 - PitchPipeline.windowSize / 512 + 1)
    #expect(readings.last?.voiced == true)
    #expect(readings.last?.midi == 55)
}

@Test func analyzerSkipsAheadWhenBehind() {
    let ring = SampleRing(capacity: 16384)
    let analyzer = Analyzer(ring: ring, pipeline: PitchPipeline(sampleRate: 48000), hop: 512)
    let block = sine(196, sampleRate: 48000, count: 12000)
    block.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: 12000) }
    #expect(analyzer.poll()?.voiced == true)
    #expect(analyzer.poll() == nil)
}

@Test func customTuningRoundTripsThroughJSON() throws {
    let tuning = Tuning.custom(name: "Open D", instrument: .guitar, notes: [38, 45, 50, 54, 57, 62])
    #expect(tuning.isCustom)
    #expect(!Tuning.standard.isCustom)
    let decoded = try JSONDecoder().decode([Tuning].self, from: JSONEncoder().encode([tuning]))
    #expect(decoded == [tuning])
    #expect(decoded[0].spacedLetters == "D A D F♯ A D")
}

import Testing

@testable import TunerCore

private let hop = 0.01

private func play(_ check: inout IntonationCheck, cents: Float, seconds: Double, from start: Double) -> Double {
    var t = start
    while t < start + seconds {
        check.push(cents: cents, voiced: true, time: t)
        t += hop
    }
    return t
}

private func silence(_ check: inout IntonationCheck, at t: Double) -> Double {
    check.push(cents: 0, voiced: false, time: t)
    return t + hop
}

@Test func capturesHarmonicThenFrettedAndCompares() {
    var check = IntonationCheck()
    var t = play(&check, cents: 1, seconds: 1.0, from: 0)
    #expect(check.status.step == .fretted)
    #expect(abs((check.status.harmonicCents ?? 99) - 1) < 0.01)

    t = silence(&check, at: t)
    _ = play(&check, cents: 6, seconds: 1.0, from: t)
    #expect(check.status.step == .done)
    #expect(abs((check.status.difference ?? 0) - 5) < 0.01)
    #expect(check.status.verdict == .moveSaddleBack)
}

@Test func ringingHarmonicIsNotTakenAsTheFrettedNote() {
    var check = IntonationCheck()
    _ = play(&check, cents: 0, seconds: 3.0, from: 0)
    #expect(check.status.step == .fretted)
    #expect(check.status.frettedCents == nil)
    #expect(check.status.waitingForSilence)
}

@Test func flatFrettedNoteMovesTheSaddleForward() {
    var check = IntonationCheck()
    var t = play(&check, cents: 0, seconds: 1.0, from: 0)
    t = silence(&check, at: t)
    _ = play(&check, cents: -4, seconds: 1.0, from: t)
    #expect(check.status.verdict == .moveSaddleForward)
}

@Test func smallDifferenceIsOk() {
    var check = IntonationCheck()
    var t = play(&check, cents: 0, seconds: 1.0, from: 0)
    t = silence(&check, at: t)
    _ = play(&check, cents: 1.5, seconds: 1.0, from: t)
    #expect(check.status.verdict == .ok)
}

@Test func aShortNoteDoesNotCapture() {
    var check = IntonationCheck()
    var t = play(&check, cents: 0, seconds: 0.5, from: 0)
    t = silence(&check, at: t)
    #expect(check.status.step == .harmonic)
    #expect(check.status.progress == 0)
}

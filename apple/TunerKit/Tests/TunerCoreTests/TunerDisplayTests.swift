import Testing

@testable import TunerCore

private func reading(midi: Int = 45, string: Int = 1, cents: Float, locked: Bool = false) -> TunerReading {
    TunerReading(
        midi: midi, stringIndex: string, hz: 110, cents: cents, voiced: true, locked: locked, idle: false,
        rmsDb: -20)
}

private func display(_ r: TunerReading, manual: Int? = nil, accidentals: Accidentals = .sharps) -> TunerDisplay {
    TunerDisplay(reading: r, tuning: .standard, accidentals: accidentals, manualString: manual)
}

@Test func idleShowsDashAndNoLitTicks() {
    let d = display(.idle)
    #expect(d.state == .idle)
    #expect(d.letter == "–")
    #expect(d.octave.isEmpty)
    #expect(d.status == "PLAY A STRING")
    #expect(d.ticks.allSatisfy { !$0.lit })
    #expect(d.activeString == nil)
}

@Test func flatLightsTicksFromCentreToReading() {
    let d = display(reading(cents: -12))
    #expect(d.state == .flat)
    #expect(d.letter == "A")
    #expect(d.octave == "2")
    #expect(d.status == "−12¢  ▲")
    #expect(d.ticks.filter(\.lit).map(\.index) == [-2, -1])
    #expect(d.activeString == 1)
}

@Test func sharpLightsTicksOnTheRight() {
    let d = display(reading(cents: 18))
    #expect(d.state == .sharp)
    #expect(d.status == "+18¢  ▼")
    #expect(d.ticks.filter(\.lit).map(\.index) == [1, 2, 3, 4])
}

@Test func lockedLightsOnlyTheCentre() {
    let d = display(reading(cents: 1, locked: true))
    #expect(d.state == .inTune)
    #expect(d.status == "IN TUNE")
    #expect(d.ticks.filter(\.lit).map(\.index) == [0])
}

@Test func centsAreClampedToTheDial() {
    let d = display(reading(cents: -80))
    #expect(d.ticks.filter(\.lit).count == 10)
    #expect(d.status == "−50¢  ▲")
}

@Test func manualStringStaysActiveWhenIdle() {
    #expect(display(.idle, manual: 4).activeString == 4)
}

@Test func flatsSettingRenamesNotes() {
    #expect(display(reading(midi: 46, cents: 5), accidentals: .flats).letter == "B♭")
    #expect(display(reading(midi: 46, cents: 5), accidentals: .sharps).letter == "A♯")
}

@Test func tickGeometryCoversEightyDegrees() {
    let d = display(.idle)
    #expect(d.ticks.count == TunerDisplay.tickCount)
    #expect(d.ticks.first?.degrees == -80)
    #expect(d.ticks.last?.degrees == 80)
}

@Test func layoutFollowsTheLargeScreenRule() {
    let phone = ScreenLayout(width: 390)
    #expect(phone.dialWidth == 350)
    #expect(phone.keysWidth == 350)
    let pad = ScreenLayout(width: 1194)
    #expect(pad.dialWidth == 520)
    #expect(pad.keysWidth == 620)
    let padPortrait = ScreenLayout(width: 834)
    #expect(abs(padPortrait.dialWidth - 834 * 0.62) < 0.01)
}

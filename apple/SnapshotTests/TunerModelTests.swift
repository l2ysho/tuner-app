import Foundation
import Testing
import TunerCore

@testable import TunerUI

@MainActor
@Suite
struct TunerModelTests {
    private let suite = "TunerModelTests.\(UUID().uuidString)"

    private func makeModel() -> TunerModel {
        TunerModel(
            defaults: UserDefaults(suiteName: suite)!, permission: GrantedMicrophonePermission(),
            makeMicrophone: { SyntheticSource(DemoSignal(hz: 0, silent: true)) })
    }

    private func lock(_ model: TunerModel, string: Int) {
        model.show(
            TunerReading(
                midi: model.tuning.notes[string], stringIndex: string, hz: 0, cents: 0, voiced: true, locked: true,
                idle: false, rmsDb: -20))
    }

    @Test func settingsSurviveARelaunch() {
        let model = makeModel()
        model.a4 = 442
        model.toleranceCents = 1
        model.accidentals = .flats
        model.strobe = true
        model.keepAwake = true
        model.appearance = .dark
        model.tuningID = Tuning.presets(for: .guitar)[1].id
        model.saveCustomTuning(.custom(name: "Open D", instrument: .guitar, notes: [38, 45, 50, 54, 57, 62]))

        let relaunched = makeModel()
        #expect(relaunched.a4 == 442)
        #expect(relaunched.toleranceCents == 1)
        #expect(relaunched.accidentals == .flats)
        #expect(relaunched.strobe)
        #expect(relaunched.keepAwake)
        #expect(relaunched.appearance == .dark)
        #expect(relaunched.tuningID == model.tuningID)
        #expect(relaunched.customTunings.map(\.name) == ["Open D"])
    }

    @Test func changingTheTuningClearsTunedStringsAndThePin() {
        let model = makeModel()
        lock(model, string: 0)
        model.toggleManualString(2)
        model.tuningID = Tuning.chromatic.id
        #expect(model.tunedStrings.isEmpty)
        #expect(model.manualString == nil)
    }

    @Test func editingTheActiveCustomTuningClearsTunedStringsAndThePin() {
        let model = makeModel()
        let tuning = Tuning.custom(name: "Mine", instrument: .guitar, notes: Tuning.standard.notes)
        model.saveCustomTuning(tuning)
        model.tuningID = tuning.id
        lock(model, string: 5)
        model.toggleManualString(5)

        var notes = tuning.notes
        notes[5] += 2
        model.saveCustomTuning(Tuning(id: tuning.id, name: tuning.name, instrument: .guitar, notes: notes))
        #expect(model.tunedStrings.isEmpty)
        #expect(model.manualString == nil)
        #expect(model.tuning.notes[5] == notes[5])
    }

    @Test func deletingTheSelectedCustomTuningFallsBackToStandard() {
        let model = makeModel()
        let tuning = Tuning.custom(name: "Gone", instrument: .guitar, notes: Tuning.standard.notes)
        model.saveCustomTuning(tuning)
        model.tuningID = tuning.id
        model.deleteCustomTuning(tuning)
        #expect(model.tuningID == Tuning.standard.id)
        #expect(model.customTunings.isEmpty)
    }

    @Test func closingTheIntonationCheckGivesBackThePinnedString() {
        let model = makeModel()
        model.toggleManualString(2)
        model.startIntonation(string: 0)
        model.startIntonation(string: 4)
        #expect(model.manualString == 4)
        model.endIntonation()
        #expect(model.manualString == 2)
    }

    @Test func allTunedNeedsEveryString() {
        let model = makeModel()
        for string in 0..<5 { lock(model, string: string) }
        #expect(!model.allTuned)
        lock(model, string: 5)
        #expect(model.allTuned)
    }
}

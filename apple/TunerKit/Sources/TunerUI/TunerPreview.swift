import SwiftUI
import TunerCore

/// The main screen frozen in one state, without audio or lifecycle: for snapshot tests and
/// SwiftUI previews.
public struct TunerPreview: View {
    public enum State: String, CaseIterable, Sendable {
        case flat, sharp, inTune, idle, allTuned, chromatic
    }

    @SwiftUI.State private var model: TunerModel

    public init(_ state: State) {
        Typeface.registerBundledFonts()
        let defaults = UserDefaults(suiteName: "TunerPreview.\(state.rawValue)") ?? .standard
        defaults.removePersistentDomain(forName: "TunerPreview.\(state.rawValue)")
        let model = TunerModel(
            defaults: defaults, permission: GrantedMicrophonePermission(),
            makeMicrophone: { SyntheticSource(DemoSignal(hz: 0, silent: true)) })
        switch state {
        case .allTuned:
            for string in Tuning.standard.notes.indices {
                model.show(
                    TunerReading(
                        midi: Tuning.standard.notes[string], stringIndex: string, hz: 0, cents: 0, voiced: true,
                        locked: true, idle: false, rmsDb: -20))
            }
        case .chromatic:
            model.tuningID = Tuning.chromatic.id
        default:
            break
        }
        model.show(Self.reading(state))
        _model = SwiftUI.State(initialValue: model)
    }

    public var body: some View {
        TunerScreen(model: model)
            .tint(Palette.sharpMark)
    }

    static func reading(_ state: State) -> TunerReading {
        switch state {
        case .flat:
            TunerReading(
                midi: 45, stringIndex: 1, hz: 109.24, cents: -12, voiced: true, locked: false,
                idle: false, rmsDb: -20)
        case .sharp:
            TunerReading(
                midi: 55, stringIndex: 3, hz: 198.04, cents: 18, voiced: true, locked: false,
                idle: false, rmsDb: -20)
        case .inTune:
            TunerReading(
                midi: 50, stringIndex: 2, hz: 146.92, cents: 1, voiced: true, locked: true,
                idle: false, rmsDb: -20)
        case .idle, .allTuned:
            .idle
        case .chromatic:
            TunerReading(
                midi: 61, stringIndex: -1, hz: 278.4, cents: 7, voiced: true, locked: false,
                idle: false, rmsDb: -20)
        }
    }
}

#Preview("Flat") { TunerPreview(.flat) }
#Preview("In tune") { TunerPreview(.inTune) }

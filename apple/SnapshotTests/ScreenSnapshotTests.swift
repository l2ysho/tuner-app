import SnapshotTesting
import SwiftUI
import Testing
import TunerCore

@testable import TunerUI

@MainActor
@Suite
struct ScreenSnapshotTests {
    enum Screen: String, CaseIterable, Sendable {
        case microphone, microphoneDenied, settings, tuningPicker, tuningEditor, intonation
    }

    @Test(arguments: Screen.allCases, [UIUserInterfaceStyle.light, .dark])
    func screen(_ screen: Screen, _ style: UIUserInterfaceStyle) {
        assertSnapshot(
            of: view(screen).tint(Palette.sharpMark),
            // Segmented pickers, toggles and text fields render blank without a window.
            as: .image(
                drawHierarchyInKeyWindow: true, perceptualPrecision: 0.98, layout: .fixed(width: 402, height: 874),
                traits: UITraitCollection { traits in
                    traits.displayScale = 2
                    traits.userInterfaceStyle = style
                }),
            named: style == .dark ? "\(screen.rawValue)-dark" : screen.rawValue)
    }

    private func view(_ screen: Screen) -> AnyView {
        Typeface.registerBundledFonts()
        let model = makeModel(screen)
        switch screen {
        case .microphone: return AnyView(MicrophoneScreen(denied: false, onPrimary: {}, onNotNow: {}))
        case .microphoneDenied: return AnyView(MicrophoneScreen(denied: true, onPrimary: {}, onNotNow: {}))
        case .settings: return AnyView(SettingsSheet(model: model))
        case .tuningPicker: return AnyView(TuningPickerSheet(model: model))
        case .tuningEditor:
            return AnyView(
                NavigationStack {
                    TuningEditor(original: .standard, isNew: true, accidentals: .sharps) { _ in }
                })
        case .intonation: return AnyView(NavigationStack { IntonationView(model: model) })
        }
    }

    private func makeModel(_ screen: Screen) -> TunerModel {
        let suite = "ScreenSnapshotTests.\(screen.rawValue)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let model = TunerModel(
            defaults: defaults, permission: GrantedMicrophonePermission(),
            makeMicrophone: { SyntheticSource(DemoSignal(hz: 0, silent: true)) })
        model.saveCustomTuning(.custom(name: "Open D", instrument: .guitar, notes: [38, 45, 50, 54, 57, 62]))
        return model
    }
}

import SnapshotTesting
import SwiftUI
import Testing
import TunerUI

/// Reference images live in __Snapshots__ next to this file. Record new ones with
/// `just record-snapshots`; failure diffs land in artifacts/snapshots/.
@MainActor
@Suite
struct TunerSnapshotTests {
    @Test(arguments: TunerPreview.State.allCases, [UIUserInterfaceStyle.light, .dark])
    func mainScreen(_ state: TunerPreview.State, _ style: UIUserInterfaceStyle) {
        assertSnapshot(
            of: TunerPreview(state),
            as: .image(
                perceptualPrecision: 0.98, layout: .fixed(width: 402, height: 874),
                traits: UITraitCollection { traits in
                    traits.displayScale = 2
                    traits.userInterfaceStyle = style
                }),
            named: style == .dark ? "\(state.rawValue)-dark" : state.rawValue)
    }
}

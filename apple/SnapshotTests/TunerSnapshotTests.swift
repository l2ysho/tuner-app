import SnapshotTesting
import SwiftUI
import Testing
import TunerUI

/// Reference images live in __Snapshots__ next to this file. Record new ones with
/// `just record-snapshots`; failure diffs land in artifacts/snapshots/.
@MainActor
@Suite
struct TunerSnapshotTests {
    @Test(arguments: TunerPreview.State.allCases)
    func mainScreen(_ state: TunerPreview.State) {
        assertSnapshot(
            of: TunerPreview(state),
            as: .image(
                perceptualPrecision: 0.98, layout: .fixed(width: 402, height: 874),
                traits: UITraitCollection(displayScale: 2)),
            named: state.rawValue)
    }
}

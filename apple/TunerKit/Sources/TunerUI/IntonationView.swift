import SwiftUI
import TunerCore

/// Compares the 12th-fret harmonic with the 12th-fret fretted note on one string.
struct IntonationView: View {
    @Bindable var model: TunerModel
    @State private var string = 0

    var body: some View {
        let status = model.intonation
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !model.tuning.isChromatic {
                    CapsLabel(text: "STRING")
                        .padding(.top, 8)
                        .padding(.bottom, 10)
                    StringKeys(
                        names: model.tuning.noteNames(model.accidentals), active: string, manual: string,
                        tuned: [], height: 52
                    ) { index in
                        string = index
                        model.startIntonation(string: index)
                    }
                }

                CapsLabel(text: "STEPS")
                    .padding(.top, 26)
                stepRow(
                    1, "Play the 12th-fret harmonic", value: status?.harmonicCents,
                    active: status?.step == .harmonic, progress: status?.progress ?? 0)
                stepRow(
                    2,
                    status?.waitingForSilence == true
                        ? "Mute the string, then fret the 12th fret" : "Fret the 12th fret",
                    value: status?.frettedCents, active: status?.step == .fretted,
                    progress: status?.waitingForSilence == true ? 0 : status?.progress ?? 0)

                if let status, status.step == .done {
                    result(status)
                }

                Text("Tune the open string first. Hold each note steady until its bar fills.")
                    .font(Typeface.ui(14, .regular, relativeTo: .footnote))
                    .foregroundStyle(Palette.mutedText)
                    .padding(.top, 20)
            }
            .padding(.horizontal, 20)
        }
        .background(Palette.panel)
        .navigationTitle("Intonation check")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Again", systemImage: "arrow.counterclockwise") { restart() }
                    .tint(Palette.ink)
            }
        }
        .onAppear {
            string = model.display.activeString ?? 0
            restart()
        }
        .onDisappear { model.endIntonation() }
    }

    private func restart() {
        model.startIntonation(string: model.tuning.isChromatic ? nil : string)
    }

    private func stepRow(_ number: Int, _ title: String, value: Float?, active: Bool, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(number)")
                    .font(Typeface.mono(13, .semibold, relativeTo: .footnote))
                    .frame(width: 24, height: 24)
                    .background(active ? Palette.ink : Palette.body, in: .circle)
                    .foregroundStyle(active ? Palette.panel : Palette.ink)
                Text(title).font(Typeface.ui(17, active ? .semibold : .medium, relativeTo: .body))
                Spacer()
                if let value {
                    Text(Self.signed(value)).font(Typeface.mono(15, .semibold, relativeTo: .callout))
                }
            }
            if active {
                ProgressView(value: progress)
                    .tint(Palette.inTuneMark)
                    .accessibilityLabel("Capturing")
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    private func result(_ status: IntonationCheck.Status) -> some View {
        let (title, detail, color): (String, String, Color) =
            switch status.verdict {
            case .ok?: ("Intonation OK", "Within ±2¢. No change needed.", Palette.inTuneText)
            case .moveSaddleBack?:
                ("Fretted note is sharp", "Move the saddle back, away from the neck.", Palette.sharpText)
            case .moveSaddleForward?:
                ("Fretted note is flat", "Move the saddle forward, toward the neck.", Palette.flatText)
            case nil: ("", "", Palette.ink)
            }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(Typeface.ui(20, .bold, relativeTo: .title3))
                Spacer()
                Text(Self.signed(status.difference ?? 0)).font(Typeface.mono(20, .semibold, relativeTo: .title3))
            }
            .foregroundStyle(color)
            Text(detail).font(Typeface.ui(15, .medium, relativeTo: .subheadline))
        }
        .padding(.top, 22)
        .accessibilityElement(children: .combine)
    }

    private static func signed(_ cents: Float) -> String {
        let value = (cents * 10).rounded() / 10
        return (value > 0 ? "+" : value < 0 ? "−" : "±") + String(format: "%.1f¢", abs(value))
    }
}

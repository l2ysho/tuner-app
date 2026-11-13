import SwiftUI
import TunerCore

struct TunerScreen: View {
    @Bindable var model: TunerModel
    @State private var sheet: Sheet?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Sheet: String, Identifiable {
        case tuning, settings
        var id: String { rawValue }
    }

    var body: some View {
        let display = model.display
        GeometryReader { proxy in
            let layout = Layout(width: proxy.size.width)
            VStack(spacing: 0) {
                Spacer(minLength: 24)
                VStack(spacing: 16 * layout.dialScale) {
                    DialView(display: display, width: layout.dialWidth)
                    statusLine(display, scale: layout.dialScale)
                }
                Spacer(minLength: 24)
                VStack(spacing: 18) {
                    StringKeys(
                        names: model.tuning.noteNames(model.accidentals),
                        active: display.activeString,
                        manual: model.manualString,
                        tuned: model.tunedStrings,
                        height: layout.keyHeight
                    ) { model.toggleManualString($0) }
                    ControlBar(
                        a4: model.a4, tuning: model.tuning,
                        onReference: { sheet = .settings },
                        onTuning: { sheet = .tuning },
                        onSettings: { sheet = .settings }
                    )
                    .padding(.horizontal, -4)
                }
                .frame(width: layout.keysWidth)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Palette.screenTint(display.state).ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: display.state)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: display.ticks)
        .sensoryFeedback(trigger: model.lockCount) { _, _ in model.hapticsOn ? .success : nil }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .tuning: TuningPickerSheet(model: model)
            case .settings: SettingsSheet(model: model)
            }
        }
    }

    @ViewBuilder
    private func statusLine(_ display: TunerDisplay, scale: CGFloat) -> some View {
        if let override = model.statusOverride {
            Button {
                model.micSkipped = false
            } label: {
                Text(override)
                    .font(Typeface.mono(18 * scale, .semibold, relativeTo: .headline))
                    .foregroundStyle(Palette.mutedText)
                    .underline()
            }
            .buttonStyle(.plain)
            .disabled(model.micAccess != .denied)
        } else {
            Text(display.status)
                .font(Typeface.mono(18 * scale, .semibold, relativeTo: .headline))
                .foregroundStyle(Palette.text(display.state))
                .contentTransition(.numericText())
                .accessibilityHidden(true)
        }
    }

    /// Phone: dial 350 pt, keys full width. Wider screens: dial ≈ 62 % (≤ 520), keys ≈ 74 % (≤ 620).
    struct Layout {
        let dialWidth: CGFloat
        let keysWidth: CGFloat
        let keyHeight: CGFloat
        var dialScale: CGFloat { dialWidth / 350 }

        init(width: CGFloat) {
            if width < 600 {
                dialWidth = min(350, width - 40)
                keysWidth = width - 40
                keyHeight = 64
            } else {
                dialWidth = min(width * 0.62, 520)
                keysWidth = min(width * 0.74, 620)
                keyHeight = 72
            }
        }
    }
}

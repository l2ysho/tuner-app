import SwiftUI
import TunerCore

struct SettingsSheet: View {
    @Bindable var model: TunerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section("REFERENCE")
                    referenceRow

                    section("DETECTION")
                    labelled("In-tune range") {
                        Picker("In-tune range", selection: $model.toleranceCents) {
                            ForEach(TunerModel.toleranceOptions, id: \.self) { Text("±\($0)¢").tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    labelled("Note names") {
                        Picker("Note names", selection: $model.accidentals) {
                            Text("Sharps  C♯").tag(Accidentals.sharps)
                            Text("Flats  D♭").tag(Accidentals.flats)
                        }
                        .pickerStyle(.segmented)
                    }
                    labelled("Noise gate", value: "\(Int(model.gateDb)) dB") {
                        Slider(value: gateBinding, in: TunerModel.gateRange) {
                            Text("Noise gate")
                        } minimumValueLabel: {
                            Text("More").font(Typeface.mono(10, .regular)).foregroundStyle(Palette.mutedText)
                        } maximumValueLabel: {
                            Text("Less").font(Typeface.mono(10, .regular)).foregroundStyle(Palette.mutedText)
                        }
                        .accessibilityValue("\(Int(model.gateDb)) decibels")
                    }

                    section("FEEDBACK")
                    toggleRow("Haptic tap when in tune", isOn: $model.hapticsOn)
                    toggleRow("Keep screen awake", isOn: $model.keepAwake)

                    CapsLabel(text: "NO ADS · NO TRACKING · NO ACCOUNT", size: 11)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
            .background(Palette.panel)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { dismiss() } label: { ConfirmLabel() }
                }
            }
        }
    }

    private var gateBinding: Binding<Double> {
        Binding(get: { model.gateDb }, set: { model.gateDb = $0.rounded() })
    }

    private func section(_ title: String) -> some View {
        CapsLabel(text: title)
            .padding(.top, 26)
            .padding(.bottom, 2)
    }

    private var referenceRow: some View {
        HStack {
            Text("A4 pitch").font(Typeface.ui(17, .medium, relativeTo: .body))
            Spacer()
            HStack(spacing: 4) {
                stepButton("−", label: "Lower A4", delta: -1)
                Text("\(model.a4) Hz")
                    .font(Typeface.mono(16, .semibold, relativeTo: .callout))
                    .frame(minWidth: 76)
                    .contentTransition(.numericText())
                    .accessibilityHidden(true)
                stepButton("+", label: "Raise A4", delta: 1)
            }
        }
        .frame(minHeight: 64)
        .overlay(alignment: .bottom) { hairline }
        .accessibilityElement(children: .contain)
    }

    private func stepButton(_ symbol: String, label: String, delta: Int) -> some View {
        Button {
            model.stepA4(delta)
        } label: {
            Text(symbol)
                .font(.system(size: 20))
                .frame(width: 44, height: 44)
                .background(Palette.body, in: .circle)
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
        .accessibilityValue("\(model.a4) hertz")
    }

    private func labelled<Content: View>(
        _ title: String, value: String? = nil, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(Typeface.ui(17, .medium, relativeTo: .body))
                Spacer()
                if let value {
                    Text(value).font(Typeface.mono(13, .semibold, relativeTo: .footnote))
                }
            }
            content()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { hairline }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).font(Typeface.ui(17, .medium, relativeTo: .body))
        }
        .frame(minHeight: 60)
        .overlay(alignment: .bottom) { hairline }
    }

    private var hairline: some View {
        Rectangle().fill(Palette.hairline).frame(height: 1)
    }
}

/// Ink checkmark on the tinted glass Done button, as on the canvas.
struct ConfirmLabel: View {
    var body: some View {
        Label("Done", systemImage: "checkmark")
            .labelStyle(.iconOnly)
            .foregroundStyle(Palette.ink)
    }
}

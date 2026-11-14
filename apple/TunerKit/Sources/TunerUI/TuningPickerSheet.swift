import SwiftUI
import TunerCore

struct TuningPickerSheet: View {
    @Bindable var model: TunerModel
    @Environment(\.dismiss) private var dismiss
    @State private var instrument: Instrument = .guitar
    @State private var selection: String = Tuning.standard.id

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Picker("Instrument", selection: $instrument) {
                        ForEach(Instrument.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 8)

                    CapsLabel(text: "PRESETS")
                        .padding(.top, 26)
                        .padding(.bottom, 4)

                    ForEach(Tuning.presets(for: instrument)) { tuning in
                        row(tuning)
                    }
                }
                .padding(.horizontal, 20)
            }
            .background(Palette.panel)
            .navigationTitle("Tuning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .tint(Palette.ink)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        model.tuningID = selection
                        dismiss()
                    } label: {
                        ConfirmLabel()
                    }
                    .disabled(selection == model.tuningID)
                }
            }
        }
        .onAppear {
            selection = model.tuningID
            instrument = model.tuning.instrument
        }
    }

    private func row(_ tuning: Tuning) -> some View {
        let selected = tuning.id == selection
        return Button {
            selection = tuning.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tuning.name)
                        .font(Typeface.ui(17, selected ? .bold : .medium, relativeTo: .body))
                    Text(tuning.spacedLetters)
                        .font(Typeface.mono(12, .regular, relativeTo: .caption))
                        .tracking(1)
                        .foregroundStyle(Palette.mutedText)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Palette.sharpText)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 2)
            .frame(minHeight: 60)
            .contentShape(.rect)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Palette.hairline).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

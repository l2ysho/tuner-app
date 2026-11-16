import SwiftUI
import TunerCore

struct TuningPickerSheet: View {
    @Bindable var model: TunerModel
    @Environment(\.dismiss) private var dismiss
    @State private var instrument: Instrument = .guitar
    @State private var selection: String = Tuning.standard.id
    @State private var editing: TuningEdit?

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

                    if instrument != .chromatic {
                        CapsLabel(text: "CUSTOM")
                            .padding(.top, 26)
                            .padding(.bottom, 4)
                        ForEach(model.customTunings.filter { $0.instrument == instrument }) { tuning in
                            row(tuning)
                                .contextMenu {
                                    Button("Edit", systemImage: "pencil") {
                                        editing = TuningEdit(tuning: tuning, isNew: false)
                                    }
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        model.deleteCustomTuning(tuning)
                                        if selection == tuning.id { selection = model.tuningID }
                                    }
                                }
                        }
                        newTuningRow
                    }
                }
                .padding(.horizontal, 20)
            }
            .background(Palette.panel)
            .navigationDestination(item: $editing) { edit in
                TuningEditor(original: edit.tuning, isNew: edit.isNew, accidentals: model.accidentals) { saved in
                    model.saveCustomTuning(saved)
                    selection = saved.id
                }
            }
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

    private var newTuningRow: some View {
        Button {
            let selected = Tuning.with(id: selection) ?? model.customTunings.first { $0.id == selection }
            let base = selected.flatMap { $0.instrument == instrument ? $0 : nil }
            editing = (base ?? Tuning.presets(for: instrument).first).map { TuningEdit(tuning: $0, isNew: true) }
        } label: {
            HStack {
                Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                Text("New tuning").font(Typeface.ui(17, .medium, relativeTo: .body))
                Spacer()
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 2)
            .frame(minHeight: 60)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Starts from the selected tuning. Touch and hold a custom tuning to edit or delete it.")
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

private struct TuningEdit: Hashable, Identifiable {
    let tuning: Tuning
    let isNew: Bool
    var id: String { (isNew ? "new:" : "edit:") + tuning.id }
}

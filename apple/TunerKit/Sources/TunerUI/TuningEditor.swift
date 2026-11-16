import SwiftUI
import TunerCore

/// Name plus one semitone stepper per string. Each string stays within an octave of the
/// instrument's standard tuning, so the detector range still fits.
struct TuningEditor: View {
    let original: Tuning
    /// New tunings start from `original` but never replace it.
    let isNew: Bool
    let accidentals: Accidentals
    let onSave: (Tuning) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var notes: [Int]

    private let reference: [Int]

    init(original: Tuning, isNew: Bool, accidentals: Accidentals, onSave: @escaping (Tuning) -> Void) {
        self.original = original
        self.isNew = isNew
        self.accidentals = accidentals
        self.onSave = onSave
        _name = State(initialValue: isNew ? "" : original.name)
        _notes = State(initialValue: original.notes)
        let standard = Tuning.presets(for: original.instrument).first ?? original
        reference = standard.notes.count == original.notes.count ? standard.notes : original.notes
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CapsLabel(text: "NAME")
                    .padding(.top, 8)
                TextField("My tuning", text: $name)
                    .font(Typeface.ui(17, .medium, relativeTo: .body))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .frame(minHeight: 52)
                    .overlay(alignment: .bottom) { hairline }

                CapsLabel(text: "STRINGS · LOWEST FIRST")
                    .padding(.top, 26)
                ForEach(notes.indices, id: \.self) { index in
                    stringRow(index)
                }
            }
            .padding(.horizontal, 20)
        }
        .background(Palette.panel)
        .navigationTitle(isNew ? "New tuning" : "Edit tuning")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .confirm) {
                    save()
                } label: {
                    ConfirmLabel()
                }
                .disabled(trimmedName.isEmpty)
            }
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        let tuning =
            isNew
            ? Tuning.custom(name: trimmedName, instrument: original.instrument, notes: notes)
            : Tuning(id: original.id, name: trimmedName, instrument: original.instrument, notes: notes)
        onSave(tuning)
        dismiss()
    }

    private func stringRow(_ index: Int) -> some View {
        let note = NoteName(midi: notes[index], accidentals: accidentals)
        let range = (reference[index] - 12)...(reference[index] + 12)
        return HStack {
            Text("String \(notes.count - index)")
                .font(Typeface.ui(17, .medium, relativeTo: .body))
            Spacer()
            HStack(spacing: 4) {
                step("−", label: "Lower string \(notes.count - index)", enabled: notes[index] > range.lowerBound) {
                    notes[index] -= 1
                }
                Text("\(note.letter)\(note.octave)")
                    .font(Typeface.mono(16, .semibold, relativeTo: .callout))
                    .frame(minWidth: 56)
                    .accessibilityHidden(true)
                step("+", label: "Raise string \(notes.count - index)", enabled: notes[index] < range.upperBound) {
                    notes[index] += 1
                }
            }
        }
        .frame(minHeight: 60)
        .overlay(alignment: .bottom) { hairline }
        // One adjustable element: VoiceOver reads the note and swipes up/down to change it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("String \(notes.count - index)")
        .accessibilityValue("\(note.letter) \(note.octave)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment where notes[index] < range.upperBound: notes[index] += 1
            case .decrement where notes[index] > range.lowerBound: notes[index] -= 1
            default: break
            }
        }
    }

    private func step(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 20))
                .frame(width: 44, height: 44)
                .background(Palette.body, in: .circle)
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    private var hairline: some View {
        Rectangle().fill(Palette.hairline).frame(height: 1)
    }
}

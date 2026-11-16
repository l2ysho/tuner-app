import SwiftUI
import TunerCore

/// One key per string. Active = ink fill; green dot = tuned this session. Tap to pin a string.
struct StringKeys: View {
    let names: [NoteName]
    let active: Int?
    let manual: Int?
    let tuned: Set<Int>
    var height: CGFloat = 64
    let onTap: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(names.indices, id: \.self) { index in
                key(index)
            }
        }
    }

    private func key(_ index: Int) -> some View {
        let name = names[index]
        let isActive = active == index
        return Button {
            onTap(index)
        } label: {
            VStack(spacing: 4) {
                Text(name.letter)
                    .font(Typeface.ui(21, .bold, relativeTo: .title3))
                Text(String(name.octave))
                    .font(Typeface.mono(10, .regular, relativeTo: .caption2))
                    .opacity(0.75)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(isActive ? Palette.panel : Palette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(isActive ? Palette.ink : Palette.panel, in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isActive ? Palette.ink : Palette.border, lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
                if tuned.contains(index) {
                    Circle()
                        .fill(Palette.inTuneMark)
                        .frame(width: 6, height: 6)
                        .padding(6)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("String \(name.letter) \(name.octave)")
        .accessibilityValue(tuned.contains(index) ? "Tuned" : "")
        .accessibilityHint(manual == index ? "Pinned. Tap to return to automatic." : "Tap to tune only this string.")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

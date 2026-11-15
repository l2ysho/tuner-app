import SwiftUI
import TunerCore

/// The boxless dial: 21 ticks on a ±80° arc with the note letter inside.
/// Geometry follows the canvas at 350 × 236 pt and scales with `width`.
struct DialView: View {
    let display: TunerDisplay
    let width: CGFloat

    @Environment(\.colorSchemeContrast) private var contrast

    private static let baseWidth: CGFloat = 350
    private static let baseHeight: CGFloat = 236
    private static let pivot = CGPoint(x: 175, y: 188)
    private static let radius: CGFloat = 184
    private static let letterSize: CGFloat = 176
    private static let octaveSize: CGFloat = 40
    private static let accidentalSize: CGFloat = 64
    private static let accidentalRise: CGFloat = 44
    /// Letter baseline in canvas coordinates (CSS line-height 0.82, bottom-aligned box).
    private static let letterBaseline: CGFloat = 228
    /// Octave baseline sits this far above the letter baseline.
    private static let octaveRise: CGFloat = 93

    private var scale: CGFloat { width / Self.baseWidth }

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(display.ticks, id: \.index) { tick in
                tickView(tick)
            }
            noteLabel
        }
        .frame(width: width, height: Self.baseHeight * scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(display.accessibilityLabel)
    }

    private func tickView(_ tick: TunerDisplay.Tick) -> some View {
        let length: CGFloat = tick.lit ? (tick.isCentre ? 20 : 16) : (tick.isCentre ? 16 : 10)
        return Capsule()
            .fill(tickColor(tick))
            .frame(width: 3 * scale, height: length * scale)
            .frame(width: 3 * scale, height: Self.radius * scale, alignment: .top)
            .rotationEffect(.degrees(tick.degrees), anchor: .bottom)
            .position(x: Self.pivot.x * scale, y: (Self.pivot.y - Self.radius / 2) * scale)
    }

    private func tickColor(_ tick: TunerDisplay.Tick) -> Color {
        if tick.lit { return Palette.mark(display.state) }
        let strong = contrast == .increased
        let opacity = tick.isCentre ? (strong ? 0.5 : 0.32) : (strong ? 0.3 : 0.13)
        return Palette.ink.opacity(opacity)
    }

    private var noteLabel: some View {
        let letterSize = Self.letterSize * scale
        let descender = Typeface.displayDescender(letterSize, .bold)
        // CSS letter-spacing −0.05em; negative tracking clips the glyph in SwiftUI, so it goes in the gap.
        return HStack(alignment: .firstTextBaseline, spacing: -0.05 * letterSize) {
            Text(display.letter.prefix(1))
                .font(Typeface.display(letterSize, .bold))
                .foregroundStyle(display.state == .idle ? Palette.idleLetter : Palette.ink)
            // Inter Tight has no ♯/♭ glyphs; the fallback font draws them far too large.
            if display.letter.count > 1 {
                Text(display.letter.dropFirst())
                    .font(.system(size: Self.accidentalSize * scale, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .baselineOffset(Self.accidentalRise * scale)
                    .padding(.horizontal, 0.05 * letterSize)
            }
            Text(display.octave)
                .font(Typeface.display(Self.octaveSize * scale, .semibold))
                .foregroundStyle(Palette.grey)
                .baselineOffset(Self.octaveRise * scale)
        }
        .lineLimit(1)
        .fixedSize()
        // Bottom of the text frame is baseline − descender; place the baseline where the canvas has it.
        .offset(y: (Self.letterBaseline - Self.baseHeight) * scale - descender)
    }
}

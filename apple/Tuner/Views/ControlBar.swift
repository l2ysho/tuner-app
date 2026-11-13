import SwiftUI
import TunerCore

/// Floating trio: A4 circle · tuning pill · settings circle. The only Liquid Glass on the main screen.
struct ControlBar: View {
    let a4: Int
    let tuning: Tuning
    let onReference: () -> Void
    let onTuning: () -> Void
    let onSettings: () -> Void

    private let size: CGFloat = 52

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button(action: onReference) {
                    VStack(spacing: 2) {
                        Text(String(a4))
                            .font(Typeface.mono(13, .semibold, relativeTo: .footnote))
                        Text("A4")
                            .font(Typeface.mono(8, .regular, relativeTo: .caption2))
                            .tracking(0.8)
                            .foregroundStyle(Palette.mutedText)
                    }
                    .frame(width: size, height: size)
                    .glassEffect(.regular.interactive(), in: .circle)
                }
                .accessibilityLabel("Reference pitch, \(a4) hertz")

                Button(action: onTuning) {
                    HStack(spacing: 10) {
                        Text(tuning.name)
                            .font(Typeface.ui(16, .semibold, relativeTo: .callout))
                        Text(tuning.compactLetters)
                            .font(Typeface.mono(12, .regular, relativeTo: .caption))
                            .tracking(0.7)
                            .foregroundStyle(Palette.mutedText)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .frame(height: size)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .accessibilityLabel("Tuning, \(tuning.instrument.title) \(tuning.name)")

                Button(action: onSettings) {
                    SlidersIcon()
                        .frame(width: 21, height: 21)
                        .frame(width: size, height: size)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .accessibilityLabel("Settings")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.ink)
        }
    }
}

/// Two-slider settings glyph from the canvas (24 × 24 grid).
struct SlidersIcon: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 24
            var lines = Path()
            lines.move(to: CGPoint(x: 4 * s, y: 7 * s))
            lines.addLine(to: CGPoint(x: 20 * s, y: 7 * s))
            lines.move(to: CGPoint(x: 4 * s, y: 17 * s))
            lines.addLine(to: CGPoint(x: 20 * s, y: 17 * s))
            let style = StrokeStyle(lineWidth: 1.9 * s, lineCap: .round)
            context.stroke(lines, with: .foreground, style: style)
            for centre in [CGPoint(x: 9, y: 7), CGPoint(x: 15, y: 17)] {
                let knob = Path(
                    ellipseIn: CGRect(x: (centre.x - 2.3) * s, y: (centre.y - 2.3) * s, width: 4.6 * s, height: 4.6 * s))
                context.fill(knob, with: .color(Palette.panel))
                context.stroke(knob, with: .foreground, style: style)
            }
        }
        .accessibilityHidden(true)
    }
}

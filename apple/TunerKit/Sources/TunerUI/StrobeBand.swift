import SwiftUI
import TunerCore

/// Stripes that drift right when sharp, left when flat and stand still in tune, like a strobe tuner.
/// Speed grows with the offset, so the last cent is easy to see.
struct StrobeBand: View {
    let cents: Int
    let state: TuneState
    /// Snapshots need the same frame on every machine.
    var frozen = false

    @State private var anchorPhase: Double = 0
    @State private var anchorTime = Date.now

    /// Stripe periods per second for each cent of offset.
    private static let periodsPerCent = 0.25
    private static let stripes = 12

    var body: some View {
        TimelineView(.animation(paused: frozen || state == .idle || state == .inTune)) { context in
            let phase = phase(at: context.date)
            Canvas { canvas, size in
                let period = size.width / CGFloat(Self.stripes)
                let offset = CGFloat(phase) * period
                let color = state == .idle ? Palette.ink.opacity(0.13) : Palette.mark(state)
                for i in -1...Self.stripes {
                    let x = CGFloat(i) * period + offset
                    let rect = CGRect(x: x, y: 0, width: period / 2, height: size.height)
                    canvas.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
                }
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0), .init(color: .black, location: 0.15),
                        .init(color: .black, location: 0.85), .init(color: .clear, location: 1),
                    ], startPoint: .leading, endPoint: .trailing)
            }
        }
        .onChange(of: cents) { _, _ in
            let now = Date.now
            anchorPhase = phase(at: now)
            anchorTime = now
        }
        .accessibilityHidden(true)
    }

    private var speed: Double { state == .inTune ? 0 : Double(cents) * Self.periodsPerCent }

    private func phase(at date: Date) -> Double {
        if frozen { return 0 }
        let p = anchorPhase + date.timeIntervalSince(anchorTime) * speed
        return p - p.rounded(.down)
    }
}

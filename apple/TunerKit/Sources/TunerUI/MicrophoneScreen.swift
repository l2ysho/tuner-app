import SwiftUI
import TunerCore

/// First launch ("Let's hear your guitar") and denied ("Microphone is off") screens.
struct MicrophoneScreen: View {
    let denied: Bool
    let onPrimary: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            icon
            Text(denied ? "Microphone is off" : "Let’s hear your guitar")
                .font(Typeface.ui(30, .bold, relativeTo: .largeTitle))
                .tracking(-0.6)
                .multilineTextAlignment(.center)
                .padding(.top, 36)
            Text(
                denied
                    ? "The tuner can’t hear anything. Turn on Microphone for this app in Settings, then come back."
                    : "The tuner listens through the microphone to find the note you play."
            )
            .font(Typeface.ui(16, .medium, relativeTo: .callout))
            .foregroundStyle(Palette.secondaryText)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .frame(maxWidth: 300)
            .padding(.top, 12)
            CapsLabel(text: denied ? "SETTINGS → PRIVACY → MICROPHONE" : "NOTHING IS RECORDED OR SENT", size: 11)
                .padding(.top, 14)
            Spacer()
            Button(action: onPrimary) {
                // "Continue", not "Allow": App Review rejects pre-prompt buttons that mimic the system prompt.
                Text(denied ? "Open Settings" : "Continue")
                    .font(Typeface.ui(17, .semibold, relativeTo: .body))
                    .foregroundStyle(Palette.panel)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Palette.ink, in: .capsule)
            }
            .buttonStyle(.plain)
            if denied {
                Button("Not now", action: onNotNow)
                    .font(Typeface.ui(15, .medium, relativeTo: .subheadline))
                    .underline()
                    .foregroundStyle(Palette.ink)
                    .frame(height: 44)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, denied ? 0 : 44)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .foregroundStyle(Palette.ink)
        .background(Palette.body.ignoresSafeArea())
    }

    private var icon: some View {
        ZStack(alignment: .bottom) {
            ForEach(-10...10, id: \.self) { i in
                Capsule()
                    .fill(Palette.ink.opacity(i == 0 ? 0.32 : 0.13))
                    .frame(width: 3, height: 10)
                    .frame(width: 3, height: 184, alignment: .top)
                    .rotationEffect(.degrees(Double(i) * 8), anchor: .bottom)
                    .position(x: 175, y: 96)
            }
            Circle()
                .fill(denied ? Palette.mutedText : Palette.ink)
                .frame(width: 96, height: 96)
                .overlay {
                    Image(systemName: denied ? "mic.slash" : "mic")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(Palette.panel)
                }
        }
        .frame(width: 350, height: 200)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(denied ? "Microphone off" : "Microphone")
    }
}

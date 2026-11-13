import AVFoundation
import SwiftUI

@main
struct TunerApp: App {
    @State private var model = TunerModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}

struct RootView: View {
    @Bindable var model: TunerModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.showsTuner {
                TunerScreen(model: model)
            } else {
                MicrophoneScreen(
                    denied: model.micAccess == .denied,
                    onPrimary: {
                        if model.micAccess == .denied {
                            model.openSystemSettings()
                        } else {
                            Task { await model.requestMicrophone() }
                        }
                    },
                    onNotNow: { model.micSkipped = true }
                )
            }
        }
        .tint(Palette.sharpMark)
        .preferredColorScheme(.light)
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { model.sceneBecameActive() } else { model.sceneLeftActive() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            model.audioInterrupted(ended: raw == AVAudioSession.InterruptionType.ended.rawValue)
        }
    }
}

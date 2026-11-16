import SwiftUI
import TunerCore

public struct RootView: View {
    @Bindable var model: TunerModel

    public init(model: TunerModel) {
        self.model = model
        Typeface.registerBundledFonts()
    }

    public var body: some View {
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
        .onAppear { model.applyAppearance() }
    }
}

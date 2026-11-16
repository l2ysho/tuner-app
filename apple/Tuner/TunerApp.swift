import SwiftUI
import TunerAudio
import TunerCore
import TunerUI

@main
struct TunerApp: App {
    @State private var model: TunerModel = {
        #if DEBUG
            // As a test host the app must not open the microphone: the simulator's audio server can
            // time out and abort the process before the tests start.
            let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            let demo =
                isTestHost
                ? DemoSignal(hz: 0, silent: true) : DemoSignal.fromArguments(ProcessInfo.processInfo.arguments)
        #else
            let demo: DemoSignal? = nil
        #endif
        return TunerModel(
            demo: demo, permission: SystemMicrophonePermission(), makeMicrophone: { MicrophoneSource() })
    }()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}

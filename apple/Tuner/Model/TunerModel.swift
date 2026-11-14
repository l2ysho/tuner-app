import AVFoundation
import Observation
import SwiftUI
import TunerCore

enum MicAccess: Equatable {
    case undetermined, granted, denied
}

@MainActor
@Observable
final class TunerModel {
    // MARK: Settings (persisted in UserDefaults)

    var tuningID: String {
        didSet {
            defaults.set(tuningID, forKey: Keys.tuning)
            manualString = nil
            tunedStrings = []
            pushConfig()
        }
    }
    var a4: Int {
        didSet {
            defaults.set(a4, forKey: Keys.a4)
            pushConfig()
        }
    }
    var toleranceCents: Int {
        didSet {
            defaults.set(toleranceCents, forKey: Keys.tolerance)
            pushConfig()
        }
    }
    var accidentals: Accidentals {
        didSet { defaults.set(accidentals.rawValue, forKey: Keys.accidentals) }
    }
    var gateDb: Double {
        didSet {
            defaults.set(gateDb, forKey: Keys.gate)
            pushConfig()
        }
    }
    var hapticsOn: Bool {
        didSet { defaults.set(hapticsOn, forKey: Keys.haptics) }
    }
    var keepAwake: Bool {
        didSet {
            defaults.set(keepAwake, forKey: Keys.keepAwake)
            updateIdleTimer()
        }
    }

    static let a4Range = 415...466
    static let toleranceOptions = [1, 3, 5]
    static let gateRange = -80.0 ... -20.0

    // MARK: Runtime state

    private(set) var reading = TunerReading.idle
    private(set) var manualString: Int?
    private(set) var tunedStrings: Set<Int> = []
    /// Increments once per lock; drives the haptic.
    private(set) var lockCount = 0
    private(set) var micAccess: MicAccess = .undetermined
    var micSkipped = false
    private(set) var audioUnavailable = false

    let demo: DemoSignal?
    private var isActive = false
    private let defaults: UserDefaults
    @ObservationIgnored private var audio: AudioController!

    var tuning: Tuning { Tuning.with(id: tuningID) ?? .standard }

    var display: TunerDisplay {
        TunerDisplay(reading: reading, tuning: tuning, accidentals: accidentals, manualString: manualString)
    }

    var showsTuner: Bool {
        demo != nil || micAccess == .granted || (micAccess == .denied && micSkipped)
    }

    /// Replaces the status line when no audio can arrive.
    var statusOverride: String? {
        if demo != nil { return nil }
        if micAccess == .denied { return "MICROPHONE OFF" }
        if audioUnavailable { return "NO MICROPHONE INPUT" }
        return nil
    }

    init(defaults: UserDefaults = .standard, arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.tuning: Tuning.standard.id,
            Keys.a4: 440,
            Keys.tolerance: 3,
            Keys.accidentals: Accidentals.sharps.rawValue,
            Keys.gate: -50.0,
            Keys.haptics: true,
            Keys.keepAwake: false,
        ])
        tuningID = defaults.string(forKey: Keys.tuning) ?? Tuning.standard.id
        let storedA4 = defaults.integer(forKey: Keys.a4)
        a4 = storedA4
        toleranceCents = defaults.integer(forKey: Keys.tolerance)
        accidentals = Accidentals(rawValue: defaults.string(forKey: Keys.accidentals) ?? "") ?? .sharps
        gateDb = defaults.double(forKey: Keys.gate)
        hapticsOn = defaults.bool(forKey: Keys.haptics)
        keepAwake = defaults.bool(forKey: Keys.keepAwake)

        #if DEBUG
            if let i = arguments.firstIndex(of: "-demo"), i + 1 < arguments.count {
                demo = DemoSignal.named(arguments[i + 1], a4: Float(storedA4))
            } else {
                demo = nil
            }
        #else
            demo = nil
        #endif

        audio = AudioController(
            onReading: { [weak self] reading, session in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.receive(reading, session: session) }
                }
            },
            onMicrophoneLost: { [weak self] in self?.microphoneLost() })
        refreshMicAccess()
        pushConfig()
    }

    // MARK: Actions

    func toggleManualString(_ index: Int) {
        manualString = manualString == index ? nil : index
        pushConfig()
    }

    func stepA4(_ delta: Int) {
        a4 = min(Self.a4Range.upperBound, max(Self.a4Range.lowerBound, a4 + delta))
    }

    func requestMicrophone() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        micAccess = granted ? .granted : .denied
        micSkipped = false
        if granted, isActive { startAudio() }
    }

    func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: Lifecycle

    func sceneBecameActive() {
        isActive = true
        refreshMicAccess()
        startAudio()
        updateIdleTimer()
    }

    func sceneLeftActive() {
        isActive = false
        audio.stop()
        reading = .idle
        updateIdleTimer()
    }

    func audioInterrupted(ended: Bool) {
        if ended, isActive {
            startAudio()
        } else {
            audio.stop()
            reading = .idle
        }
    }

    // MARK: Private

    private func startAudio() {
        if let demo {
            audio.startDemo(demo)
            return
        }
        guard micAccess == .granted else { return }
        do {
            try audio.startMicrophone()
            audioUnavailable = false
        } catch {
            audioUnavailable = true
        }
    }

    private func microphoneLost() {
        reading = .idle
        if isActive { startAudio() }
    }

    private func receive(_ new: TunerReading, session: UInt64) {
        guard session == audio.session else { return }
        if new.locked, !reading.locked {
            lockCount += 1
            if new.stringIndex >= 0 { tunedStrings.insert(new.stringIndex) }
        }
        reading = new
    }

    private func refreshMicAccess() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: micAccess = .granted
        case .denied: micAccess = .denied
        default: micAccess = .undetermined
        }
    }

    private func pushConfig() {
        guard let audio else { return }
        let tuning = tuning
        audio.apply(
            PipelineConfig(
                strings: tuning.frequencies(a4: Float(a4)), a4: Float(a4),
                tolerance: Float(toleranceCents), manualString: manualString ?? -1,
                minHz: tuning.instrument.minHz, gateDb: Float(gateDb)))
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = keepAwake && isActive
    }

    private enum Keys {
        static let tuning = "tuning"
        static let a4 = "a4"
        static let tolerance = "tolerance"
        static let accidentals = "accidentals"
        static let gate = "noiseGateDb"
        static let haptics = "haptics"
        static let keepAwake = "keepAwake"
    }
}

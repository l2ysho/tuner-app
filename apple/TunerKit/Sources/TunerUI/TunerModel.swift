import Observation
import SwiftUI
import TunerCore

typealias MicAccess = MicrophonePermissionStatus

@MainActor
@Observable
public final class TunerModel {
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
    private(set) var customTunings: [Tuning] {
        didSet { defaults.set(try? JSONEncoder().encode(customTunings), forKey: Keys.customTunings) }
    }
    var strobe: Bool {
        didSet { defaults.set(strobe, forKey: Keys.strobe) }
    }
    var keepAwake: Bool {
        didSet {
            defaults.set(keepAwake, forKey: Keys.keepAwake)
            updateIdleTimer()
        }
    }

    static let a4Range = 415...466
    static let toleranceOptions = [1, 3, 5]

    // MARK: Runtime state

    /// Only reassigned when the screen would change: the analyzer delivers ~94 readings a second,
    /// and every observed write re-renders the tuner screen and its sheets, which cancels taps.
    private(set) var reading = TunerReading.idle
    @ObservationIgnored private var latest = TunerReading.idle
    private(set) var manualString: Int?
    private(set) var tunedStrings: Set<Int> = []
    /// Non-nil while the intonation check is open.
    private(set) var intonation: IntonationCheck.Status?
    @ObservationIgnored private var intonationCheck: IntonationCheck?
    private(set) var micAccess: MicAccess = .undetermined
    var micSkipped = false
    private(set) var audioUnavailable = false

    let demo: DemoSignal?
    private var isActive = false
    private let defaults: UserDefaults
    @ObservationIgnored private var engine: TunerEngine!
    @ObservationIgnored private let permission: any MicrophonePermission
    @ObservationIgnored private let makeMicrophone: @MainActor () -> any AudioSource
    @ObservationIgnored private var microphone: (any AudioSource)?
    @ObservationIgnored private let makeTonePlayer: (@MainActor () -> any TonePlayer)?
    @ObservationIgnored private var tonePlayer: (any TonePlayer)?
    /// The microphone hears the reference tone; it must not mark the string as tuned.
    @ObservationIgnored private var toneUntil = 0.0

    var tuning: Tuning { Tuning.with(id: tuningID) ?? customTunings.first { $0.id == tuningID } ?? .standard }

    var display: TunerDisplay { display(for: reading) }

    var allTuned: Bool { !tuning.isChromatic && tunedStrings.count == tuning.notes.count }

    private func display(for reading: TunerReading) -> TunerDisplay {
        TunerDisplay(
            reading: reading, tuning: tuning, accidentals: accidentals, manualString: manualString,
            allTuned: allTuned)
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

    /// `makeMicrophone` and `permission` come from TunerAudio in the app; `demo` replaces the
    /// microphone with a synthetic tone.
    public init(
        defaults: UserDefaults = .standard,
        demo: DemoSignal? = nil,
        permission: any MicrophonePermission,
        makeMicrophone: @escaping @MainActor () -> any AudioSource,
        makeTonePlayer: (@MainActor () -> any TonePlayer)? = nil
    ) {
        self.defaults = defaults
        self.demo = demo
        self.permission = permission
        self.makeMicrophone = makeMicrophone
        self.makeTonePlayer = makeTonePlayer
        defaults.register(defaults: [
            Keys.tuning: Tuning.standard.id,
            Keys.a4: 440,
            Keys.tolerance: 3,
            Keys.accidentals: Accidentals.sharps.rawValue,
            Keys.keepAwake: false,
            Keys.strobe: false,
        ])
        tuningID = defaults.string(forKey: Keys.tuning) ?? Tuning.standard.id
        a4 = defaults.integer(forKey: Keys.a4)
        toleranceCents = defaults.integer(forKey: Keys.tolerance)
        accidentals = Accidentals(rawValue: defaults.string(forKey: Keys.accidentals) ?? "") ?? .sharps
        keepAwake = defaults.bool(forKey: Keys.keepAwake)
        strobe = defaults.bool(forKey: Keys.strobe)
        customTunings =
            defaults.data(forKey: Keys.customTunings).flatMap { try? JSONDecoder().decode([Tuning].self, from: $0) }
            ?? []

        engine = TunerEngine { [weak self] reading, session in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.receive(reading, session: session) }
            }
        }
        refreshMicAccess()
        pushConfig()
    }

    // MARK: Actions

    func toggleManualString(_ index: Int) {
        manualString = manualString == index ? nil : index
        pushConfig()
    }

    func saveCustomTuning(_ tuning: Tuning) {
        if let index = customTunings.firstIndex(where: { $0.id == tuning.id }) {
            customTunings[index] = tuning
            if tuning.id == tuningID { pushConfig() }
        } else {
            customTunings.append(tuning)
        }
    }

    func deleteCustomTuning(_ tuning: Tuning) {
        customTunings.removeAll { $0.id == tuning.id }
        if tuningID == tuning.id { tuningID = Tuning.standard.id }
    }

    /// Pins `string` (nil in chromatic mode) so the harmonic and the fretted note share one target.
    func startIntonation(string: Int?) {
        let check = IntonationCheck()
        intonationCheck = check
        intonation = check.status
        manualString = string
        pushConfig()
    }

    func endIntonation() {
        intonationCheck = nil
        intonation = nil
        manualString = nil
        pushConfig()
    }

    var canPlayTone: Bool { makeTonePlayer != nil }

    func playReference(string: Int) {
        guard let makeTonePlayer, tuning.notes.indices.contains(string) else { return }
        let player = tonePlayer ?? makeTonePlayer()
        tonePlayer = player
        let seconds = 2.5
        toneUntil = ProcessInfo.processInfo.systemUptime + seconds + 0.3
        player.play(hz: midiToHz(tuning.notes[string], a4: Float(a4)), seconds: seconds)
    }

    func stepA4(_ delta: Int) {
        a4 = min(Self.a4Range.upperBound, max(Self.a4Range.lowerBound, a4 + delta))
    }

    func requestMicrophone() async {
        let granted = await permission.request()
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
        engine.stop()
        resetReading()
        updateIdleTimer()
    }

    // MARK: Private

    private func startAudio() {
        if let demo {
            try? engine.start(SyntheticSource(demo))
            return
        }
        guard micAccess == .granted else { return }
        do {
            try engine.start(microphoneSource())
            audioUnavailable = false
        } catch {
            audioUnavailable = true
        }
    }

    private func microphoneSource() -> any AudioSource {
        if let microphone { return microphone }
        let source = makeMicrophone()
        source.onEvent = { [weak self] event in self?.handle(event) }
        microphone = source
        return source
    }

    private func handle(_ event: AudioSourceEvent) {
        switch event {
        case .interrupted:
            engine.stop()
            resetReading()
        case .resumed, .lost:
            resetReading()
            if isActive { startAudio() }
        }
    }

    /// Shows a fixed reading without audio (previews and snapshot tests).
    func show(_ reading: TunerReading) {
        latest = reading
        self.reading = reading
        if reading.locked, reading.stringIndex >= 0 { tunedStrings.insert(reading.stringIndex) }
    }

    private func resetReading() {
        latest = .idle
        reading = .idle
    }

    private func receive(_ new: TunerReading, session: UInt64) {
        guard session == engine.session else { return }
        if var check = intonationCheck {
            check.push(cents: new.cents, voiced: new.voiced, time: ProcessInfo.processInfo.systemUptime)
            intonationCheck = check
            if check.status != intonation { intonation = check.status }
        }
        if new.locked, !latest.locked, new.stringIndex >= 0, ProcessInfo.processInfo.systemUptime > toneUntil {
            tunedStrings.insert(new.stringIndex)
        }
        latest = new
        if display(for: new) != display { reading = new }
    }

    private func refreshMicAccess() {
        micAccess = permission.status
    }

    private func pushConfig() {
        guard let engine else { return }
        let tuning = tuning
        engine.apply(
            PipelineConfig(
                strings: tuning.frequencies(a4: Float(a4)), a4: Float(a4),
                tolerance: Float(toleranceCents), manualString: manualString ?? -1,
                minHz: tuning.instrument.minHz))
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = keepAwake && isActive
    }

    private enum Keys {
        static let tuning = "tuning"
        static let a4 = "a4"
        static let tolerance = "tolerance"
        static let accidentals = "accidentals"
        static let keepAwake = "keepAwake"
        static let strobe = "strobe"
        static let customTunings = "customTunings"
    }
}

public enum AudioSourceEvent: Sendable, Equatable {
    /// The system took the input away (a call, Siri). Show idle until `.resumed`.
    case interrupted
    case resumed
    /// The input was torn down (route or format change, media services reset); start again.
    case lost
}

/// Writes mono Float32 samples into a `SampleRing`. The microphone lives in TunerAudio;
/// tests and demo mode use `SyntheticSource`.
@MainActor
public protocol AudioSource: AnyObject, Sendable {
    /// Starts writing into `ring` and returns the sample rate.
    func start(into ring: SampleRing) throws -> Double
    func stop()
    /// Runs on the analysis queue before each poll. Pull-based sources write here; push-based
    /// sources (the microphone) write from their own thread and ignore it.
    nonisolated func pump(into ring: SampleRing)
    var onEvent: (@MainActor (AudioSourceEvent) -> Void)? { get set }
}

public enum MicrophonePermissionStatus: Sendable, Equatable {
    case undetermined, granted, denied
}

@MainActor
public protocol MicrophonePermission: AnyObject {
    var status: MicrophonePermissionStatus { get }
    func request() async -> Bool
}

/// Grants access without asking: for previews, tests and demo mode.
@MainActor
public final class GrantedMicrophonePermission: MicrophonePermission {
    public init() {}
    public var status: MicrophonePermissionStatus { .granted }
    public func request() async -> Bool { true }
}

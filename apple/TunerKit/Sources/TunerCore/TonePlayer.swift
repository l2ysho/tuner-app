/// Plays a reference pitch through the speaker. The implementation lives in TunerAudio.
@MainActor
public protocol TonePlayer: AnyObject {
    func play(hz: Float, seconds: Double)
}

import AVFoundation
import CoreAudioKit

/// Placeholder Audio Unit: passes audio through unchanged. It exists so the extension's
/// signing, embedding and registration work before the real tuner AU reuses the DSP core.
public final class AudioUnitViewController: AUViewController, AUAudioUnitFactory {
    public nonisolated func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit
    {
        try PassthroughAudioUnit(componentDescription: componentDescription, options: [])
    }
}

final class PassthroughAudioUnit: AUAudioUnit {
    private var inputBusArray: AUAudioUnitBusArray?
    private var outputBusArray: AUAudioUnitBusArray?

    override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = [])
        throws
    {
        try super.init(componentDescription: componentDescription, options: options)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2) else { return }
        inputBusArray = AUAudioUnitBusArray(
            audioUnit: self, busType: .input, busses: [try AUAudioUnitBus(format: format)])
        outputBusArray = AUAudioUnitBusArray(
            audioUnit: self, busType: .output, busses: [try AUAudioUnitBus(format: format)])
    }

    override var inputBusses: AUAudioUnitBusArray { inputBusArray ?? super.inputBusses }
    override var outputBusses: AUAudioUnitBusArray { outputBusArray ?? super.outputBusses }

    override var internalRenderBlock: AUInternalRenderBlock {
        { _, timestamp, frameCount, _, outputData, _, pullInputBlock in
            guard let pullInputBlock else { return kAudioUnitErr_NoConnection }
            var flags = AudioUnitRenderActionFlags()
            return pullInputBlock(&flags, timestamp, frameCount, 0, outputData)
        }
    }
}

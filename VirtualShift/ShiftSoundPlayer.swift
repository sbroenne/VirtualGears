import AVFoundation
import Foundation

@MainActor
final class ShiftSoundPlayer {
    enum Kind {
        case single
        case multiple
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(
        standardFormatWithSampleRate: 44_100,
        channels: 1
    )!
    private var configured = false

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func play(_ kind: Kind) throws {
        if !configured {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
            try engine.start()
            configured = true
        } else if !engine.isRunning {
            try engine.start()
        }

        let sampleRate = format.sampleRate
        let duration = 0.14
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ), let samples = buffer.floatChannelData?[0] else {
            throw ShiftSoundError.couldNotCreateBuffer
        }
        buffer.frameLength = frameCount

        let pulseStarts = kind == .single ? [0.0] : [0.0, 0.055]
        let frequency = kind == .single ? 1_250.0 : 850.0

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            var value = 0.0
            for start in pulseStarts where time >= start {
                let pulseTime = time - start
                guard pulseTime < 0.045 else { continue }
                value += sin(2 * .pi * frequency * pulseTime)
                    * exp(-70 * pulseTime)
            }
            samples[frame] = Float(value * 0.35)
        }

        player.stop()
        player.scheduleBuffer(buffer)
        player.play()
    }
}

private enum ShiftSoundError: Error {
    case couldNotCreateBuffer
}

import Foundation
import AppKit

final class FeedbackSoundPlayer {
    static let shared = FeedbackSoundPlayer()

    private static let volume: Float = 0.4

    private let startSound = FeedbackSoundPlayer.load("cue-start")
    private let stopSound = FeedbackSoundPlayer.load("cue-stop")

    private init() {}

    private static func load(_ name: String) -> NSSound? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "aiff"),
              let sound = NSSound(contentsOf: url, byReference: true) else {
            return nil
        }
        sound.volume = volume
        return sound
    }

    func playStart() {
        startSound?.stop()
        startSound?.play()
    }

    func playStop() {
        stopSound?.stop()
        stopSound?.play()
    }
}

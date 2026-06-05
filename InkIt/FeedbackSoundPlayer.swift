import Foundation
import AppKit

/// Plays short custom cue sounds when dictation starts and stops so the user has
/// audible confirmation that their hotkey actually triggered. The cues are warm,
/// ~50ms tonal "pock" sounds bundled with the app (rising on start, falling on
/// stop) rather than macOS system sounds — system sounds like "Tink" carry
/// learned "alert/error" associations. Two NSSound instances are kept around so
/// a rapid press/release doesn't have one call clobber the other.
final class FeedbackSoundPlayer {
    static let shared = FeedbackSoundPlayer()

    /// Kept quiet so the cue sits under the user's typing rather than reading as
    /// an alert. Matches the subtle level VoiceInk uses for its feedback sounds.
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

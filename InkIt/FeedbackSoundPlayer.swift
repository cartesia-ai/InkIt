import Foundation
import AppKit

/// Plays short system sounds when dictation starts and stops so the user has
/// audible confirmation that their hotkey actually triggered. Two NSSound
/// instances are kept around so a rapid press/release doesn't have one call
/// clobber the other.
final class FeedbackSoundPlayer {
    static let shared = FeedbackSoundPlayer()

    private let startSound = NSSound(named: NSSound.Name("Tink"))
    private let stopSound = NSSound(named: NSSound.Name("Tink"))

    private init() {}

    func playStart() {
        startSound?.stop()
        startSound?.play()
    }

    func playStop() {
        stopSound?.stop()
        stopSound?.play()
    }
}

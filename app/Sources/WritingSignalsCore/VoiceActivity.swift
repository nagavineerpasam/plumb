import Foundation

/// Tells speech from background noise, per microphone buffer. A fixed loudness cut-off misses a
/// normal voice on a quiet laptop mic, so this follows the room instead: it tracks the background
/// level and counts anything clearly above it as someone speaking.
public struct VoiceActivity: Sendable {
    /// Speech must be this many times louder than the background.
    static let ratio = 2.5
    /// Below this nothing counts as speech, however quiet the room.
    static let minimum = 0.0015
    /// A quiet laptop microphone: the background assumed while the room is first measured.
    static let quietRoom = 0.002
    /// Buffers (about half a second) spent measuring the room after Speak is clicked.
    static let measuring = 25

    private var floor = VoiceActivity.quietRoom
    private var heard = 0
    private var quietest = Double.infinity

    public init() {}

    /// Feeds one buffer's RMS level; true when it sounds like someone speaking.
    public mutating func hears(_ level: Double) -> Bool {
        if heard < Self.measuring {
            // The user may start talking at once, so the room's level is the quietest moment of
            // the first half second (the gaps between words), and speech meanwhile still counts.
            heard += 1
            quietest = min(quietest, level)
            if heard == Self.measuring { floor = quietest }
            return level > max(Self.minimum, Self.quietRoom * Self.ratio)
        }
        let voice = level > max(Self.minimum, floor * Self.ratio)
        // The background follows quieter sounds quickly and louder ones slowly, and barely moves
        // while someone speaks, so a long sentence never becomes the new background.
        let rate = level < floor ? 0.3 : (voice ? 0.0001 : 0.001)
        floor += (level - floor) * rate
        return voice
    }
}

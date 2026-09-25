import Foundation

/// Tells speech from background noise, per microphone buffer. A fixed loudness cut-off misses a
/// normal voice on a quiet laptop mic, so this follows the room instead: it tracks the background
/// level and counts anything clearly above it as someone speaking.
public struct VoiceActivity: Sendable {
    /// Speech must be this many times louder than the background.
    static let ratio = 2.5
    /// Below this nothing counts as speech, however quiet the room.
    static let minimum = 0.0015
    /// The background level; nil until the first buffer.
    private var floor: Double?

    public init() {}

    /// Feeds one buffer's RMS level; true when it sounds like someone speaking.
    public mutating func hears(_ level: Double) -> Bool {
        guard let current = floor else {
            floor = level  // Speak was just clicked: the first sound is the room
            return false
        }
        let voice = level > max(Self.minimum, current * Self.ratio)
        // The background follows quieter sounds quickly and louder ones slowly, and barely moves
        // while someone speaks, so a long sentence never becomes the new background.
        let rate = level < current ? 0.3 : (voice ? 0.0001 : 0.001)
        floor = current + (level - current) * rate
        return voice
    }
}

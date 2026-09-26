import CryptoKit
import Foundation

/// An app version like 0.2.0, compared number by number (so 0.10.0 is newer than 0.2.1).
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let numbers: [Int]
    /// As written, without a leading "v" (0.2.0), for showing.
    private let text: String

    /// Nil for anything that isn't a plain version, such as the "models-v1" release.
    public init?(_ text: String) {
        let plain = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = plain.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        var numbers = parts.compactMap { $0 }
        while numbers.count > 1, numbers.last == 0 { numbers.removeLast() }  // 0.2 == 0.2.0
        self.numbers = numbers
        self.text = plain
    }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        for i in 0..<max(a.numbers.count, b.numbers.count) {
            let x = i < a.numbers.count ? a.numbers[i] : 0, y = i < b.numbers.count ? b.numbers[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    public var description: String { text }

    public static func == (a: AppVersion, b: AppVersion) -> Bool { a.numbers == b.numbers }
}

/// The latest release, as GitHub's API describes it.
public struct ReleaseInfo: Sendable, Equatable {
    public let tag: String
    public let version: AppVersion
    /// Up to three "what's new" lines, from the bullet points in the release notes.
    public let highlights: [String]

    public static func parse(_ data: Data) -> ReleaseInfo? {
        struct Release: Decodable { let tag_name: String; let body: String? }
        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              let version = AppVersion(release.tag_name) else { return nil }
        let bullets = (release.body ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- ") || $0.hasPrefix("* ") }
            .map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        return ReleaseInfo(tag: release.tag_name, version: version,
                           highlights: bullets.isEmpty ? ["Improvements and fixes."] : Array(bullets.prefix(3)))
    }
}

/// Checks a download against its published SHA-256 fingerprint ("<hash>  Plumb.dmg").
public enum Fingerprint {
    public static func sha256(of file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func matches(_ file: URL, published: String) -> Bool {
        guard let expected = published.split(whereSeparator: \.isWhitespace).first, expected.count == 64 else { return false }
        return sha256(of: file) == expected.lowercased()
    }
}

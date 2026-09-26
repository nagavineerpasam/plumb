// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Plumb",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Whisper on Core ML, for speaking into notes (MIT).
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.0"),
    ],
    targets: [
        // The spelling word list: SCOWL (US + UK, size 60, plus abbreviations and common names).
        .target(name: "WritingSignalsCore",
                resources: [.copy("Resources/english-words.txt"), .copy("Resources/SCOWL-Copyright.txt")]),
        .executableTarget(name: "Plumb", dependencies: ["WritingSignalsCore", .product(name: "WhisperKit", package: "WhisperKit")],
                          resources: [.copy("Resources/AppIcon.icns")]),
        .testTarget(name: "WritingSignalsCoreTests", dependencies: ["WritingSignalsCore"]),
    ]
)

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
        .target(name: "WritingSignalsCore"),
        .executableTarget(name: "Plumb", dependencies: ["WritingSignalsCore", .product(name: "WhisperKit", package: "WhisperKit")],
                          resources: [.copy("Resources/AppIcon.icns")]),
        .testTarget(name: "WritingSignalsCoreTests", dependencies: ["WritingSignalsCore"]),
    ]
)

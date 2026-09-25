// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WritingSignals",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "WritingSignalsCore"),
        .executableTarget(name: "WritingSignals", dependencies: ["WritingSignalsCore"]),
        .testTarget(name: "WritingSignalsCoreTests", dependencies: ["WritingSignalsCore"]),
    ]
)

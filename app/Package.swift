// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Plumb",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "WritingSignalsCore"),
        .executableTarget(name: "Plumb", dependencies: ["WritingSignalsCore"],
                          resources: [.copy("Resources/AppIcon.icns")]),
        .testTarget(name: "WritingSignalsCoreTests", dependencies: ["WritingSignalsCore"]),
    ]
)

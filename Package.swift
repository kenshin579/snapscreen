// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SnapScreen",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")
    ],
    targets: [
        .target(name: "SnapScreenKit", dependencies: ["KeyboardShortcuts"]),
        .executableTarget(name: "SnapScreen", dependencies: ["SnapScreenKit"]),
        .testTarget(name: "SnapScreenKitTests", dependencies: ["SnapScreenKit"])
    ]
)

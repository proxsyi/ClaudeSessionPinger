// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeSessionPinger",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeSessionPinger",
            path: "Sources/ClaudeSessionPinger"
        )
    ]
)

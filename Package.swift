// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Brighter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Brighter",
            path: "Sources/Brighter",
            // Swift 6 language mode. Everything runs on the main actor: the menu, the EDR windows
            // and the gamma calls. Strict checking keeps it that way, so a later change that
            // touches a window or a gamma table from a background thread fails to compile.
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "BrighterTests",
            dependencies: ["Brighter"],
            path: "Tests/BrighterTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)

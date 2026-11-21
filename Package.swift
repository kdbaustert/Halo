// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Brighter",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Auto-update. A binary XCFramework, so build.sh has to copy it into Contents/Frameworks,
        // add an rpath for it and sign it before the app.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.5"),
    ],
    targets: [
        .executableTarget(
            name: "Brighter",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
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

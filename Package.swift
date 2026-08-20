// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Blockpad",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Blockpad",
            dependencies: ["KeyboardShortcuts"],
            path: "Sources/Blockpad",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)

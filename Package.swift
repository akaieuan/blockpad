// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Blockpad",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0")
    ],
    targets: [
        // Pure logic, no AppKit UI, so it can be unit tested. An executable
        // target with top-level code cannot be imported by a test target, which
        // is why this split exists at all.
        .target(
            name: "BlockpadKit",
            path: "Sources/BlockpadKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Blockpad",
            dependencies: ["KeyboardShortcuts", "BlockpadKit"],
            path: "Sources/Blockpad",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "BlockpadKitTests",
            dependencies: ["BlockpadKit"],
            path: "Tests/BlockpadKitTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)

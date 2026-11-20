// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Keybee",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "Keybee", targets: ["Keybee"]),
    ],
    targets: [
        .target(name: "Keybee"),
        .testTarget(name: "KeybeeTests", dependencies: ["Keybee"], resources: [.copy("Resources")]),
        // Apps that build in Swift 5 mode with main-actor default isolation use the same API.
        .testTarget(name: "Swift5ConsumerTests", dependencies: ["Keybee"], swiftSettings: [.swiftLanguageMode(.v5)]),
        // Against production in test mode; skipped unless KEYBEE_LIVE_TEST=1.
        .testTarget(name: "KeybeeLiveTests", dependencies: ["Keybee"]),
    ],
    swiftLanguageModes: [.v6]
)

// swift-tools-version:5.9
import PackageDescription

// Sparkle (auto-updates) is a macOS binary framework; leave it out elsewhere so the
// platform-independent core still builds and tests on Linux.
#if os(macOS)
let dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4"),
]
let appDependencies: [Target.Dependency] = ["HighlightCore", .product(name: "Sparkle", package: "Sparkle")]
#else
let dependencies: [Package.Dependency] = []
let appDependencies: [Target.Dependency] = ["HighlightCore"]
#endif

let package = Package(
    name: "HighlightCode",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "HighlightCode", targets: ["HighlightCode"]),
        .library(name: "HighlightCore", targets: ["HighlightCore"]),
    ],
    dependencies: dependencies,
    targets: [
        // Platform-independent logic (parsing, themes, fences) plus the
        // JavaScriptCore/AppKit glue, which is compiled only on macOS.
        .target(name: "HighlightCore"),
        // The menu-bar-less app that provides the macOS Services.
        .executableTarget(name: "HighlightCode", dependencies: appDependencies),
        .testTarget(name: "HighlightCoreTests", dependencies: ["HighlightCore"]),
    ]
)

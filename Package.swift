// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HighlightCode",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "HighlightCode", targets: ["HighlightCode"]),
        .library(name: "HighlightCore", targets: ["HighlightCore"]),
    ],
    targets: [
        // Platform-independent logic (parsing, themes, fences) plus the
        // JavaScriptCore/AppKit glue, which is compiled only on macOS.
        .target(name: "HighlightCore"),
        // The menu-bar-less app that provides the macOS Services.
        .executableTarget(name: "HighlightCode", dependencies: ["HighlightCore"]),
        .testTarget(name: "HighlightCoreTests", dependencies: ["HighlightCore"]),
    ]
)

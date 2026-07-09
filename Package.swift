// swift-tools-version: 6.1
//
// SwaTex — KaTeX-compatible math rendering in pure Swift.
// Built by the team behind Phrase (https://phrase.so), the native block
// editor for source-backed AI notes.

import PackageDescription

let package = Package(
    name: "SwaTex",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .tvOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "SwaTex", targets: ["SwaTex"]),
        .library(name: "SwaTexRender", targets: ["SwaTexRender"]),
    ],
    targets: [
        // Core engine: lexer → parser → layout → display list, plus the SVG backend.
        // Pure Swift, no platform dependencies.
        .target(
            name: "SwaTex"
        ),
        // Apple-native rendering: CoreText/CoreGraphics backend, bundled KaTeX
        // fonts, and a SwiftUI view.
        .target(
            name: "SwaTexRender",
            dependencies: ["SwaTex"],
            resources: [
                .copy("Resources/Fonts")
            ],
            linkerSettings: [
                // libz for FastPNGEncoder's level-1 deflate (stable C ABI,
                // present on every Apple platform).
                .linkedLibrary("z")
            ]
        ),
        // Differential-testing CLI mirroring RaTeX's `layout` binary.
        .executableTarget(
            name: "LayoutDump",
            dependencies: ["SwaTex"]
        ),
        // SwiftUI demo gallery (`swift run SwaTexDemo` on macOS).
        .executableTarget(
            name: "SwaTexDemo",
            dependencies: ["SwaTexRender"]
        ),
        .testTarget(
            name: "SwaTexTests",
            dependencies: ["SwaTex"],
            resources: [
                .copy("Resources/golden")
            ]
        ),
        .testTarget(
            name: "SwaTexRenderTests",
            dependencies: ["SwaTexRender"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Typetick",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Typetick", targets: ["Typetick"]),
        .library(name: "TypetickCore", targets: ["TypetickCore"]),
        .library(name: "TypetickAudio", targets: ["TypetickAudio"]),
        .library(name: "TypetickScene", targets: ["TypetickScene"]),
    ],
    targets: [
        // Pure Swift: the mechanical model of the typewriter, documents, styles.
        .target(name: "TypetickCore"),
        // Procedural sound synthesis for every mechanism (no audio files).
        .target(name: "TypetickAudio", dependencies: ["TypetickCore"]),
        // RealityKit scene: component library, assembly, paper rendering, animation.
        .target(
            name: "TypetickScene",
            dependencies: ["TypetickCore"],
            resources: [.copy("Resources/Components"), .process("Shaders/Surface.metal")]
        ),
        // The macOS app.
        .executableTarget(
            name: "Typetick",
            dependencies: ["TypetickCore", "TypetickAudio", "TypetickScene"]
        ),
        .testTarget(name: "TypetickCoreTests", dependencies: ["TypetickCore"]),
    ],
    swiftLanguageVersions: [.v5]
)

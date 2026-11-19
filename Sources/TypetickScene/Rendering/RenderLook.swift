import Foundation

/// "Camera and film" settings of the realtime renderer.
public struct RenderLook: Codable, Hashable, Sendable {
    public enum Quality: String, Codable, CaseIterable, Sendable, Identifiable {
        case balanced, high, cinematic
        public var id: String { rawValue }
        public var title: String { rawValue.capitalized }
    }

    public var quality: Quality = .cinematic
    /// Screen space ambient occlusion: contact shadows in every gap and crevice.
    public var ambientOcclusion: Double = 0.85
    public var bloom: Double = 0.35
    /// Volumetric looking rays from the lamp through the dusty air.
    public var lightShafts: Double = 0.25
    public var filmGrain: Double = 0.025
    public var vignette: Double = 0.45
    public var chromaticAberration: Double = 0.004
    public var exposure: Double = 0.0
    public var contrast: Double = 0.25
    public var saturation: Double = 1.05
    /// Teal shadows / warm highlights split toning.
    public var toning: Double = 0.35
    public var sharpen: Double = 0.25
    /// Dust, smudges and micro surface detail on every part.
    public var surfaceWear: Double = 0.6
    /// Floating dust motes in the lamp light.
    public var dustMotes = true

    public init() {}

    public static let natural: RenderLook = {
        var l = RenderLook()
        l.bloom = 0.15; l.lightShafts = 0; l.filmGrain = 0.01; l.vignette = 0.2; l.chromaticAberration = 0
        l.contrast = 0.1; l.toning = 0.1; l.dustMotes = false
        return l
    }()

    public static let noir: RenderLook = {
        var l = RenderLook()
        l.saturation = 0.15; l.contrast = 0.55; l.filmGrain = 0.06; l.vignette = 0.7; l.toning = 0.1; l.lightShafts = 0.4
        return l
    }()

    public static let neonNight: RenderLook = {
        var l = RenderLook()
        l.bloom = 0.65; l.lightShafts = 0.45; l.toning = 0.6; l.saturation = 1.25; l.contrast = 0.35; l.chromaticAberration = 0.008
        return l
    }()

    public static let presets: [(String, RenderLook)] = [("Cinematic", RenderLook()), ("Natural", .natural), ("Noir", .noir),
                                                         ("Neon Night", .neonNight)]
}

import Foundation

/// Linear-ish sRGB color with 0...1 components.
public struct RGB: Codable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    public init(hex: UInt32) {
        self.init(Double((hex >> 16) & 0xff) / 255, Double((hex >> 8) & 0xff) / 255, Double(hex & 0xff) / 255)
    }

    public func mixed(with other: RGB, _ t: Double) -> RGB {
        RGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }

    public func offset(_ o: [Double]) -> RGB {
        guard o.count >= 3 else { return self }
        return RGB(min(max(r + o[0], 0), 1), min(max(g + o[1], 0), 1), min(max(b + o[2], 0), 1))
    }

    public var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    public static let black = RGB(0, 0, 0)
    public static let white = RGB(1, 1, 1)
}

// MARK: - Machine

/// The twelve interchangeable assemblies of the machine. Raw values match the
/// folder names of the component library.
public enum ComponentKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case chassis, keys, typebars, carriage, knobs, returnLever, paperBail, ribbon, correction, bell, marginRack, recorder
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chassis: return "Chassis"
        case .keys: return "Keys"
        case .typebars: return "Typebars"
        case .carriage: return "Carriage"
        case .knobs: return "Platen Knobs"
        case .returnLever: return "Return Lever"
        case .paperBail: return "Paper Bail"
        case .ribbon: return "Ribbon"
        case .correction: return "Correction"
        case .bell: return "Bell"
        case .marginRack: return "Margin Rack"
        case .recorder: return "Recorder"
        }
    }

    public var symbol: String {
        switch self {
        case .chassis: return "square.stack.3d.up"
        case .keys: return "keyboard"
        case .typebars: return "line.3.horizontal.decrease"
        case .carriage: return "arrow.left.and.right"
        case .knobs: return "dial.medium"
        case .returnLever: return "arrow.turn.down.left"
        case .paperBail: return "doc.plaintext"
        case .ribbon: return "record.circle"
        case .correction: return "eraser"
        case .bell: return "bell"
        case .marginRack: return "ruler"
        case .recorder: return "recordingtape"
        }
    }
}

public struct MachineConfiguration: Codable, Hashable, Sendable {
    public var variants: [String: String]   // ComponentKind.rawValue -> variant id

    public init(variants: [String: String]) { self.variants = variants }

    public subscript(kind: ComponentKind) -> String {
        get { variants[kind.rawValue] ?? MachineConfiguration.standard.variants[kind.rawValue] ?? "" }
        set { variants[kind.rawValue] = newValue }
    }

    public static let standard = MachineConfiguration(variants: [
        "chassis": "atlas_upright", "keys": "glass_ring", "typebars": "slim_steel", "carriage": "classic_black",
        "knobs": "fluted_bakelite", "returnLever": "chrome_arm", "paperBail": "roller_bail", "ribbon": "open_metal",
        "correction": "chalk_cover", "bell": "classic_dome", "marginRack": "sliding_tabs", "recorder": "telegraph_perforator",
    ])
}

// MARK: - Paper

public enum PaperTint: String, Codable, CaseIterable, Sendable, Identifiable {
    case white, ivory, cream, yellow, kraft, gray, blue, rose, sage, black
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }

    /// Five shades from lightest to deepest.
    public var shades: [RGB] {
        switch self {
        case .white: return [RGB(hex: 0xFBFBF8), RGB(hex: 0xF6F6F1), RGB(hex: 0xF1F2F0), RGB(hex: 0xF4F1EA), RGB(hex: 0xEDEDE8)]
        case .ivory: return [RGB(hex: 0xFBF7EC), RGB(hex: 0xF7F1E1), RGB(hex: 0xF2EAD4), RGB(hex: 0xEDE3C8), RGB(hex: 0xE6DABB)]
        case .cream: return [RGB(hex: 0xF8F0DC), RGB(hex: 0xF2E6C8), RGB(hex: 0xEBDDB6), RGB(hex: 0xE3D19F), RGB(hex: 0xD9C48A)]
        case .yellow: return [RGB(hex: 0xFCF6C8), RGB(hex: 0xFAF0A8), RGB(hex: 0xF6E784), RGB(hex: 0xF0DA62), RGB(hex: 0xE8CB45)]
        case .kraft: return [RGB(hex: 0xD9C2A0), RGB(hex: 0xCDB08A), RGB(hex: 0xBE9C74), RGB(hex: 0xAD885F), RGB(hex: 0x98744D)]
        case .gray: return [RGB(hex: 0xE4E4E2), RGB(hex: 0xCFCFCD), RGB(hex: 0xB4B5B3), RGB(hex: 0x8F9091), RGB(hex: 0x6B6C6E)]
        case .blue: return [RGB(hex: 0xEAF1F7), RGB(hex: 0xD8E6F2), RGB(hex: 0xBFD4E8), RGB(hex: 0x8FB0D0), RGB(hex: 0x2E4A6B)]
        case .rose: return [RGB(hex: 0xF9ECEA), RGB(hex: 0xF3DAD6), RGB(hex: 0xEBC4BE), RGB(hex: 0xDCA49C), RGB(hex: 0x8C4A48)]
        case .sage: return [RGB(hex: 0xEEF2E8), RGB(hex: 0xDDE6D4), RGB(hex: 0xC5D3B8), RGB(hex: 0x9EB18E), RGB(hex: 0x4D5E44)]
        case .black: return [RGB(hex: 0x3A3A3C), RGB(hex: 0x2A2A2C), RGB(hex: 0x1D1D1F), RGB(hex: 0x141416), RGB(hex: 0x0B0B0C)]
        }
    }
}

public enum PaperFinish: String, Codable, CaseIterable, Sendable, Identifiable {
    case matte, vellum, laid, linen, cotton, glossy, onionskin, recycled, watercolor, parchment
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }

    /// Base microsurface roughness of the sheet (PBR).
    public var surfaceRoughness: Double {
        switch self {
        case .glossy: return 0.22
        case .onionskin: return 0.55
        case .vellum, .parchment: return 0.62
        case .matte: return 0.86
        case .laid, .linen: return 0.88
        case .cotton, .watercolor: return 0.93
        case .recycled: return 0.9
        }
    }
}

public enum PaperSize: String, Codable, CaseIterable, Sendable, Identifiable {
    case letter, a4, legal, a5
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .letter: return "US Letter"
        case .a4: return "A4"
        case .legal: return "US Legal"
        case .a5: return "A5"
        }
    }
    /// Size in points (1/72 inch).
    public var points: (width: Double, height: Double) {
        switch self {
        case .letter: return (612, 792)
        case .a4: return (595.28, 841.89)
        case .legal: return (612, 1008)
        case .a5: return (419.53, 595.28)
        }
    }
}

public struct PaperStyle: Codable, Hashable, Sendable {
    public var tint: PaperTint = .ivory
    public var shade: Int = 1
    public var finish: PaperFinish = .laid
    public var size: PaperSize = .letter
    /// 0 = blotting-soft (deep impressions, ink spreads), 1 = hard card.
    public var hardness: Double = 0.55
    /// Surface tooth / roughness of the texture.
    public var tooth: Double = 0.35
    /// Creases and cockling.
    public var wrinkle: Double = 0.08
    /// Visible fibers and inclusions.
    public var fibers: Double = 0.3
    /// Yellowing, foxing and edge darkening.
    public var age: Double = 0.1
    /// Grammage feel: thin papers let the platen show through a little.
    public var weight: Double = 0.5

    public init() {}

    public var color: RGB {
        let shades = tint.shades
        return shades[max(0, min(shades.count - 1, shade))]
    }

    public var isDark: Bool { color.luminance < 0.35 }

    public static let presets: [(String, PaperStyle)] = {
        var bond = PaperStyle(); bond.tint = .white; bond.shade = 0; bond.finish = .matte; bond.tooth = 0.2; bond.fibers = 0.15; bond.age = 0
        var laid = PaperStyle()
        var onion = PaperStyle(); onion.tint = .white; onion.shade = 2; onion.finish = .onionskin; onion.hardness = 0.35; onion.weight = 0.15; onion.wrinkle = 0.2
        var kraft = PaperStyle(); kraft.tint = .kraft; kraft.shade = 1; kraft.finish = .recycled; kraft.fibers = 0.8; kraft.tooth = 0.6
        var legal = PaperStyle(); legal.tint = .yellow; legal.shade = 1; legal.finish = .matte; legal.size = .legal
        var noir = PaperStyle(); noir.tint = .black; noir.shade = 2; noir.finish = .cotton; noir.tooth = 0.5
        var gloss = PaperStyle(); gloss.tint = .white; gloss.shade = 1; gloss.finish = .glossy; gloss.hardness = 0.9; gloss.tooth = 0.05
        var archive = PaperStyle(); archive.tint = .cream; archive.shade = 3; archive.finish = .parchment; archive.age = 0.7; archive.wrinkle = 0.35
        return [("Bond", bond), ("Laid Ivory", laid), ("Onionskin", onion), ("Kraft", kraft), ("Legal Pad", legal),
                ("Noir Cotton", noir), ("Gloss Card", gloss), ("Archive", archive)]
    }()
}

// MARK: - Ink

public enum InkKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case fabric, carbon, pearlescent, metallic, glitter, iridescent, fluorescent, chalk
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .fabric: return "Fabric Ribbon"
        case .carbon: return "Carbon Film"
        case .pearlescent: return "Pearlescent"
        case .metallic: return "Metallic Foil"
        case .glitter: return "Glitter Flakes"
        case .iridescent: return "Iridescent"
        case .fluorescent: return "Fluorescent"
        case .chalk: return "Chalk"
        }
    }
    public var summary: String {
        switch self {
        case .fabric: return "Inked cloth ribbon. Soft edges and visible weave."
        case .carbon: return "Single-strike film. Crisp, even and dense."
        case .pearlescent: return "Mother-of-pearl sheen that shifts with the light."
        case .metallic: return "Hot-foil look. Reflects the lamp like real metal."
        case .glitter: return "Scaly flakes that catch the light individually."
        case .iridescent: return "Hue drifts across each glyph like oil on water."
        case .fluorescent: return "Glows slightly under cool light."
        case .chalk: return "Dry, powdery deposit. Best on dark papers."
        }
    }
}

public struct InkStyle: Codable, Hashable, Sendable {
    public var color: RGB = RGB(hex: 0x16161A)
    public var secondColor: RGB = RGB(hex: 0xB0201C)
    public var kind: InkKind = .fabric
    /// How far the ink wicks into the fibers (feathering).
    public var bleed: Double = 0.18
    /// Overall ink load. Low = pale, dry ribbon.
    public var density: Double = 0.85
    /// Uneven inking across a glyph and between strikes.
    public var variance: Double = 0.35
    /// Ribbon wear: dropouts and weave pattern.
    public var wear: Double = 0.2
    /// Soft halo of excess ink around strikes.
    public var halo: Double = 0.1
    /// Fraction of shine for special inks (pearl, metallic, glitter...).
    public var sheen: Double = 0.6

    public init() {}

    public static let presets: [(String, InkStyle)] = {
        var black = InkStyle()
        var carbon = InkStyle(); carbon.kind = .carbon; carbon.bleed = 0.02; carbon.variance = 0.05; carbon.wear = 0; carbon.density = 1
        var navy = InkStyle(); navy.color = RGB(hex: 0x1C2A55); navy.bleed = 0.25
        var red = InkStyle(); red.color = RGB(hex: 0xA3241E)
        var brown = InkStyle(); brown.color = RGB(hex: 0x4A2E1E); brown.bleed = 0.35; brown.wear = 0.45
        var pearl = InkStyle(); pearl.color = RGB(hex: 0xEDE6F0); pearl.kind = .pearlescent; pearl.bleed = 0.05
        var gold = InkStyle(); gold.color = RGB(hex: 0xC9A045); gold.kind = .metallic; gold.bleed = 0; gold.variance = 0.15
        var silver = InkStyle(); silver.color = RGB(hex: 0xC8CACC); silver.kind = .glitter; silver.bleed = 0; silver.sheen = 0.9
        var oil = InkStyle(); oil.color = RGB(hex: 0x3A3F7A); oil.kind = .iridescent
        var chalk = InkStyle(); chalk.color = RGB(hex: 0xF4F1E8); chalk.kind = .chalk; chalk.bleed = 0; chalk.wear = 0.5
        var neon = InkStyle(); neon.color = RGB(hex: 0xF0398E); neon.kind = .fluorescent; neon.bleed = 0.1
        return [("Black Fabric", black), ("Carbon", carbon), ("Navy", navy), ("Red", red), ("Sepia", brown),
                ("Pearl", pearl), ("Gold Foil", gold), ("Silver Flake", silver), ("Oil Slick", oil),
                ("White Chalk", chalk), ("Neon Pink", neon)]
    }()
}

// MARK: - Typeface

public struct TypefaceStyle: Codable, Hashable, Sendable {
    /// PostScript name, or "system-mono" for SF Mono.
    public var fontName: String = "Courier"
    public var displayName: String = "Courier"
    /// Cap height scale relative to the pitch. 1 = classic fit.
    public var scale: Double = 1.0
    /// Extra stroke weight from heavy strikes.
    public var emboldening: Double = 0.15
    /// Per-letter vertical misalignment, in points.
    public var baselineJitter: Double = 0.35
    /// Per-letter rotation, in degrees.
    public var rotationJitter: Double = 0.6

    public init() {}

    public init(fontName: String, displayName: String) {
        self.fontName = fontName
        self.displayName = displayName
    }

    public static let presets: [TypefaceStyle] = [
        TypefaceStyle(fontName: "Courier", displayName: "Courier"),
        TypefaceStyle(fontName: "CourierNewPSMT", displayName: "Courier New"),
        TypefaceStyle(fontName: "AmericanTypewriter", displayName: "American Typewriter"),
        TypefaceStyle(fontName: "AmericanTypewriter-Light", displayName: "American Typewriter Light"),
        TypefaceStyle(fontName: "Menlo-Regular", displayName: "Menlo"),
        TypefaceStyle(fontName: "Monaco", displayName: "Monaco"),
        TypefaceStyle(fontName: "PTMono-Regular", displayName: "PT Mono"),
        TypefaceStyle(fontName: "AndaleMono", displayName: "Andale Mono"),
        TypefaceStyle(fontName: "system-mono", displayName: "SF Mono"),
        TypefaceStyle(fontName: "Courier-Bold", displayName: "Courier Bold"),
    ]
}

/// What a strike was made with. Sheets keep a palette of these so changing the
/// ribbon or type later never alters what is already on paper.
public struct StrikeStyle: Codable, Hashable, Sendable {
    public var ink: InkStyle
    public var typeface: TypefaceStyle
    public var useSecondColor: Bool

    public init(ink: InkStyle, typeface: TypefaceStyle, useSecondColor: Bool = false) {
        self.ink = ink
        self.typeface = typeface
        self.useSecondColor = useSecondColor
    }

    public var effectiveColor: RGB { useSecondColor ? ink.secondColor : ink.color }
}

// MARK: - Desk & environment

public enum DeskMaterial: String, Codable, CaseIterable, Sendable, Identifiable {
    case walnut, oak, cherry, ebony, pine, marble, slate, leather, felt, linoleum, steel, concrete, glass
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public struct DeskStyle: Codable, Hashable, Sendable {
    public var material: DeskMaterial = .walnut
    public var tint: RGB? = nil
    public var grainScale: Double = 1.0
    public var gloss: Double = 0.45
    public var wear: Double = 0.25
    public init() {}
}

public enum TimeOfDay: String, Codable, CaseIterable, Sendable, Identifiable {
    case dawn, day, dusk, night
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum LampKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case bankers, architect, candle, edison, neon, fluorescent, none
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .bankers: return "Banker's Lamp"
        case .architect: return "Architect Arm"
        case .candle: return "Brass Candle"
        case .edison: return "Edison Pendant"
        case .neon: return "Neon Sign"
        case .fluorescent: return "Office Tube"
        case .none: return "No Lamp"
        }
    }
    /// Default color temperature in Kelvin.
    public var kelvin: Double {
        switch self {
        case .bankers: return 2900
        case .architect: return 3400
        case .candle: return 1900
        case .edison: return 2300
        case .neon: return 0  // uses neonColor
        case .fluorescent: return 5200
        case .none: return 4000
        }
    }
}

public struct EnvironmentStyle: Codable, Hashable, Sendable {
    public var timeOfDay: TimeOfDay = .dusk
    public var lamp: LampKind = .bankers
    public var lampKelvin: Double = 2900
    public var lampIntensity: Double = 1.0
    public var neonColor: RGB = RGB(hex: 0xFF3B7F)
    public var windowLight: Bool = true
    public var ambient: Double = 0.5
    public var shadows: Bool = true
    public init() {}

    public static func kelvinToRGB(_ k: Double) -> RGB {
        // Tanner Helland's approximation.
        let t = max(1000, min(40000, k)) / 100
        var r: Double, g: Double, b: Double
        if t <= 66 {
            r = 255
            g = 99.4708025861 * log(t) - 161.1195681661
        } else {
            r = 329.698727446 * pow(t - 60, -0.1332047592)
            g = 288.1221695283 * pow(t - 60, -0.0755148492)
        }
        if t >= 66 { b = 255 } else if t <= 19 { b = 0 } else { b = 138.5177312231 * log(t - 10) - 305.0447927307 }
        func c(_ v: Double) -> Double { min(max(v, 0), 255) / 255 }
        return RGB(c(r), c(g), c(b))
    }
}

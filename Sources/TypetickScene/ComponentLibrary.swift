import Foundation
import simd
import TypetickCore

/// Loosely typed JSON used for the free-form `mechanics` blocks of manifests.
public enum JSONValue: Codable, Hashable, Sendable {
    case number(Double), string(String), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { self = .null }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case let .number(d): try c.encode(d)
        case let .string(s): try c.encode(s)
        case let .bool(b): try c.encode(b)
        case let .array(a): try c.encode(a)
        case let .object(o): try c.encode(o)
        case .null: try c.encodeNil()
        }
    }

    public subscript(_ key: String) -> JSONValue {
        if case let .object(o) = self { return o[key] ?? .null }
        return .null
    }

    public var double: Double? { if case let .number(d) = self { return d }; return nil }
    public var bool: Bool? { if case let .bool(b) = self { return b }; return nil }
    public var string: String? { if case let .string(s) = self { return s }; return nil }
    public var array: [JSONValue]? { if case let .array(a) = self { return a }; return nil }

    public func double(_ fallback: Double) -> Double { double ?? fallback }
    public func float(_ fallback: Float) -> Float { double.map(Float.init) ?? fallback }

    public var vec3: SIMD3<Float>? {
        guard let a = array, a.count >= 3, let x = a[0].double, let y = a[1].double, let z = a[2].double else { return nil }
        return SIMD3(Float(x), Float(y), Float(z))
    }
}

public struct VariantManifest: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var era: String
    public var summary: String
    public var tags: [String]?
    public var file: String
    public var parts: [String]
    public var mechanics: JSONValue
    public var sound: [String: JSONValue]
    public var animation: [String: Double]
    public var palette: [String: [Double]]

    public func sound(_ key: String, _ fallback: Double) -> Double { sound[key]?.double ?? fallback }
    public func anim(_ key: String, _ fallback: Double) -> Double { animation[key] ?? fallback }
}

public struct KindManifest: Codable, Sendable {
    public var kind: String
    public var title: String
    public var summary: String
    public var variants: [VariantManifest]
}

/// Loads the component catalog shipped with the app, merged with user made
/// components in `~/Library/Application Support/Typetick/Components/<kind>/`.
/// A user folder holds its own `manifest.json` + model files; variants with an
/// existing id replace the built-in one, new ids are appended.
public final class ComponentLibrary: @unchecked Sendable {
    public static let shared = ComponentLibrary()

    public private(set) var kinds: [ComponentKind: KindManifest] = [:]
    private var fileRoots: [String: URL] = [:]   // "kind/variant" -> folder

    public static var userComponentsFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Typetick/Components", isDirectory: true)
    }

    public init() { reload() }

    public func reload() {
        kinds = [:]
        fileRoots = [:]
        let builtIn = Bundle.module.url(forResource: "Components", withExtension: nil)
        for kind in ComponentKind.allCases {
            var manifest: KindManifest? = nil
            if let root = builtIn?.appendingPathComponent(kind.rawValue), let m = load(root) {
                manifest = m
                for v in m.variants { fileRoots["\(kind.rawValue)/\(v.id)"] = root }
            }
            let userRoot = ComponentLibrary.userComponentsFolder.appendingPathComponent(kind.rawValue)
            if let user = load(userRoot) {
                var merged = manifest ?? user
                for v in user.variants {
                    if let i = merged.variants.firstIndex(where: { $0.id == v.id }) { merged.variants[i] = v } else { merged.variants.append(v) }
                    fileRoots["\(kind.rawValue)/\(v.id)"] = userRoot
                }
                manifest = merged
            }
            if let m = manifest { kinds[kind] = m }
        }
    }

    private func load(_ folder: URL) -> KindManifest? {
        let url = folder.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(KindManifest.self, from: data)
        } catch {
            NSLog("Typetick: cannot read \(url.path): \(error)")
            return nil
        }
    }

    public func variants(_ kind: ComponentKind) -> [VariantManifest] { kinds[kind]?.variants ?? [] }

    public func variant(_ kind: ComponentKind, _ id: String) -> VariantManifest? {
        let all = variants(kind)
        return all.first(where: { $0.id == id }) ?? all.first
    }

    public func modelURL(_ kind: ComponentKind, _ variant: VariantManifest) -> URL? {
        guard let root = fileRoots["\(kind.rawValue)/\(variant.id)"] else { return nil }
        return root.appendingPathComponent(variant.file)
    }

    /// Resolved variants of a configuration, falling back to the first variant.
    public func resolve(_ config: MachineConfiguration) -> [ComponentKind: VariantManifest] {
        var out: [ComponentKind: VariantManifest] = [:]
        for kind in ComponentKind.allCases {
            if let v = variant(kind, config[kind]) { out[kind] = v }
        }
        return out
    }

    /// Mechanical spec of an assembled machine.
    public func spec(for config: MachineConfiguration) -> MachineSpec {
        let v = resolve(config)
        var s = MachineSpec()
        if let c = v[.carriage]?.mechanics {
            s.pitch = c["pitch"].double(s.pitch)
            s.lineHeight = c["lineHeight"].double(s.lineHeight)
            s.platenLength = c["platenLength"].double(s.platenLength)
            s.returnSpeed = c["returnSpeed"].double(s.returnSpeed)
            s.powerReturn = c["powerReturn"].bool ?? false
            s.escapementSnap = c["escapementSnap"].double(s.escapementSnap)
        }
        if let ch = v[.chassis]?.mechanics {
            s.shiftType = MachineSpec.ShiftType(rawValue: ch["shiftType"].string ?? "segment") ?? .segment
        }
        if let b = v[.bell]?.mechanics {
            s.bellOffsetColumns = Int(b["bellOffsetColumns"].double(7))
            s.bellStrikes = Int(b["strikes"].double(1))
        }
        if let l = v[.returnLever]?.mechanics {
            s.lineSpacingOptions = l["lineSpacingOptions"].array?.compactMap(\.double) ?? [1, 1.5, 2]
            s.feedBeforeReturn = l["feedBeforeReturn"].bool ?? true
        }
        if let k = v[.knobs]?.mechanics { s.detentsPerLine = Int(k["detentsPerLine"].double(3)) }
        if let c = v[.correction]?.mechanics {
            s.correctionMode = c["mode"].string == "liftOff" ? .liftOff : .coverUp
            s.correctionCoverage = c["coverage"].double(1)
            s.correctionTint = c["tintOffset"].array?.compactMap(\.double) ?? [0, 0, 0]
        }
        if let r = v[.recorder]?.mechanics {
            s.recorderMedium = MachineSpec.RecorderMedium(rawValue: r["medium"].string ?? "tape") ?? .tape
            s.recorderCPS = r["charactersPerSecond"].double(11)
            s.springCapacity = Int(r["springCapacity"].double(220))
        }
        if let t = v[.typebars]?.mechanics {
            s.typebarSwing = t["swingTime"].double(s.typebarSwing)
            s.typebarReturn = t["returnTime"].double(s.typebarReturn)
            s.impactForce = t["impactForce"].double(s.impactForce)
            s.alignmentJitter = t["alignmentJitter"].double(0.6)
        }
        if let k = v[.keys]?.mechanics { s.keyTravel = k["travel"].double(s.keyTravel) }
        if let r = v[.ribbon]?.mechanics { s.twoColorRibbon = r["twoColor"].bool ?? false }
        if let m = v[.marginRack]?.mechanics {
            s.defaultLeftMargin = Int(m["defaultLeftMargin"].double(10))
            s.defaultRightMargin = Int(m["defaultRightMargin"].double(75))
            s.defaultTabs = m["defaultTabs"].array?.compactMap { $0.double.map(Int.init) } ?? s.defaultTabs
        }
        // Escapement scales the default margins (elite fits more columns).
        let scale = 0.00254 / s.pitch
        if abs(scale - 1) > 0.01 {
            s.defaultLeftMargin = Int((Double(s.defaultLeftMargin) * scale).rounded())
            s.defaultRightMargin = Int((Double(s.defaultRightMargin) * scale).rounded())
            s.defaultTabs = s.defaultTabs.map { Int((Double($0) * scale).rounded()) }
        }
        return s
    }
}

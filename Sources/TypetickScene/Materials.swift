import AppKit
import Metal
import RealityKit
import TypetickCore

/// Builds physically based materials for the role names baked into the
/// component meshes (`Body__paint`, `Stem__steel`...).
@MainActor
public enum Materials {
    struct Look {
        var color: RGB
        var metallic: Float
        var roughness: Float
        var clearcoat: Float = 0
        var opacity: Float = 1
    }

    static let roles: [String: Look] = [
        "paint": Look(color: RGB(0.04, 0.04, 0.045), metallic: 0, roughness: 0.32, clearcoat: 0.8),
        "paintAccent": Look(color: RGB(0.78, 0.62, 0.30), metallic: 0.6, roughness: 0.35, clearcoat: 0.3),
        "paintSecond": Look(color: RGB(0.86, 0.83, 0.74), metallic: 0, roughness: 0.38, clearcoat: 0.6),
        "chrome": Look(color: RGB(0.92, 0.92, 0.94), metallic: 1, roughness: 0.07),
        "steel": Look(color: RGB(0.62, 0.63, 0.65), metallic: 1, roughness: 0.32),
        "blackSteel": Look(color: RGB(0.10, 0.10, 0.11), metallic: 0.9, roughness: 0.42),
        "brass": Look(color: RGB(0.86, 0.68, 0.36), metallic: 1, roughness: 0.26),
        "copper": Look(color: RGB(0.85, 0.50, 0.36), metallic: 1, roughness: 0.3),
        "rubber": Look(color: RGB(0.035, 0.035, 0.037), metallic: 0, roughness: 0.78),
        "redRubber": Look(color: RGB(0.42, 0.07, 0.05), metallic: 0, roughness: 0.72),
        "bakelite": Look(color: RGB(0.05, 0.035, 0.03), metallic: 0, roughness: 0.22, clearcoat: 0.9),
        "keyTop": Look(color: RGB(0.05, 0.05, 0.05), metallic: 0, roughness: 0.25, clearcoat: 0.7),
        "keyBody": Look(color: RGB(0.07, 0.07, 0.07), metallic: 0, roughness: 0.3, clearcoat: 0.5),
        "glass": Look(color: RGB(0.9, 0.95, 0.95), metallic: 0, roughness: 0.02, clearcoat: 1, opacity: 0.3),
        "smoked": Look(color: RGB(0.18, 0.14, 0.11), metallic: 0, roughness: 0.06, clearcoat: 1, opacity: 0.6),
        "felt": Look(color: RGB(0.13, 0.20, 0.13), metallic: 0, roughness: 0.95),
        "plastic": Look(color: RGB(0.80, 0.78, 0.72), metallic: 0, roughness: 0.4, clearcoat: 0.2),
        "darkPlastic": Look(color: RGB(0.12, 0.12, 0.13), metallic: 0, roughness: 0.45, clearcoat: 0.1),
        "wood": Look(color: RGB(0.36, 0.20, 0.10), metallic: 0, roughness: 0.5, clearcoat: 0.6),
        "enamel": Look(color: RGB(0.93, 0.92, 0.88), metallic: 0, roughness: 0.15, clearcoat: 1),
        "tape": Look(color: RGB(0.93, 0.88, 0.70), metallic: 0, roughness: 0.8),
        "medium": Look(color: RGB(0.93, 0.88, 0.70), metallic: 0, roughness: 0.75),
        "ribbon": Look(color: RGB(0.03, 0.03, 0.03), metallic: 0, roughness: 0.85),
        "correction": Look(color: RGB(0.97, 0.96, 0.93), metallic: 0, roughness: 0.9),
        "scale": Look(color: RGB(0.90, 0.88, 0.80), metallic: 0, roughness: 0.5, clearcoat: 0.2),
    ]

    public static func nsColor(_ c: RGB, alpha: Double = 1) -> NSColor {
        NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha)
    }

    /// High quality sampler: trilinear + 16x anisotropy keeps type crisp at grazing angles.
    public static var sharpSampler: MaterialParameters.Texture.Sampler {
        let d = MTLSamplerDescriptor()
        d.minFilter = .linear
        d.magFilter = .linear
        d.mipFilter = .linear
        d.maxAnisotropy = 16
        d.sAddressMode = .clampToEdge
        d.tAddressMode = .clampToEdge
        return MaterialParameters.Texture.Sampler(d)
    }

    public static var repeatSampler: MaterialParameters.Texture.Sampler {
        let d = MTLSamplerDescriptor()
        d.minFilter = .linear
        d.magFilter = .linear
        d.mipFilter = .linear
        d.maxAnisotropy = 16
        d.sAddressMode = .repeat
        d.tAddressMode = .repeat
        return MaterialParameters.Texture.Sampler(d)
    }

    /// Texture parameter with an explicit sampler.
    public static func texture(_ resource: TextureResource, sampler: MaterialParameters.Texture.Sampler) -> MaterialParameters.Texture {
        var t = MaterialParameters.Texture(resource)
        t.sampler = sampler
        return t
    }

    public static func material(role: String, palette: [String: [Double]]) -> PhysicallyBasedMaterial {
        var look = roles[role] ?? roles["paint"]!
        if let p = palette[role], p.count >= 3 { look.color = RGB(p[0], p[1], p[2]) }
        return make(look)
    }

    static func make(_ look: Look) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: nsColor(look.color))
        m.metallic = .init(floatLiteral: look.metallic)
        m.roughness = .init(floatLiteral: look.roughness)
        if look.clearcoat > 0 {
            m.clearcoat = .init(floatLiteral: look.clearcoat)
            m.clearcoatRoughness = .init(floatLiteral: 0.06)
        }
        if look.opacity < 1 {
            m.blending = .transparent(opacity: .init(floatLiteral: look.opacity))
        }
        return m
    }

    public static func solid(_ c: RGB, roughness: Float = 0.6, metallic: Float = 0) -> PhysicallyBasedMaterial {
        make(Look(color: c, metallic: metallic, roughness: roughness))
    }

    // MARK: realistic surfaces (Metal surface shader)

    /// Global wear amount (0...1) applied to dust and smudges.
    public static var wear: Float = 0.6
    /// Set to false to compare against plain PBR.
    public static var useSurfaceShader = true

    /// dust, smudge, micro detail, clear coat
    static let wearProfile: [String: SIMD4<Float>] = [
        "paint": SIMD4(0.55, 0.25, 0.6, 0.85), "paintSecond": SIMD4(0.5, 0.25, 0.6, 0.75),
        "paintAccent": SIMD4(0.3, 0.2, 0.4, 0.3), "chrome": SIMD4(0.25, 0.6, 0.3, 0),
        "steel": SIMD4(0.4, 0.35, 1.0, 0), "blackSteel": SIMD4(0.5, 0.3, 0.8, 0),
        "brass": SIMD4(0.35, 0.55, 0.6, 0), "copper": SIMD4(0.35, 0.5, 0.6, 0),
        "rubber": SIMD4(0.7, 0.1, 1.0, 0), "redRubber": SIMD4(0.7, 0.1, 1.0, 0),
        "bakelite": SIMD4(0.35, 0.5, 0.4, 0.9), "keyTop": SIMD4(0.12, 0.7, 0.3, 0.6),
        "keyBody": SIMD4(0.35, 0.4, 0.5, 0.4), "felt": SIMD4(0.3, 0, 1, 0),
        "plastic": SIMD4(0.45, 0.3, 0.5, 0.2), "darkPlastic": SIMD4(0.5, 0.3, 0.5, 0.1),
        "wood": SIMD4(0.3, 0.2, 0.8, 0.5), "enamel": SIMD4(0.2, 0.3, 0.3, 1),
        "scale": SIMD4(0.3, 0.2, 0.3, 0.2),
    ]

    private static var surfaceShader: CustomMaterial.SurfaceShader? = {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        // Prefer a precompiled library if one was bundled, else compile the source now.
        if let lib = try? device.makeDefaultLibrary(bundle: Bundle.module), lib.functionNames.contains("typetickSurface") {
            return CustomMaterial.SurfaceShader(named: "typetickSurface", in: lib)
        }
        do {
            let lib = try device.makeLibrary(source: SurfaceShaderSource.source, options: nil)
            return CustomMaterial.SurfaceShader(named: "typetickSurface", in: lib)
        } catch {
            NSLog("Typetick: surface shader unavailable (\(error)); using plain PBR")
            return nil
        }
    }()

    /// Wraps a PBR material in the wear/dust surface shader when available.
    public static func realistic(_ pbr: PhysicallyBasedMaterial, role: String) -> any RealityKit.Material {
        guard useSurfaceShader, let shader = surfaceShader, var profile = wearProfile[role] else { return pbr }
        do {
            var m = try CustomMaterial(from: pbr, surfaceShader: shader)
            profile.x *= wear * 1.6
            profile.y *= wear * 1.6
            m.custom.value = profile
            return m
        } catch {
            return pbr
        }
    }

    /// Re-materializes every mesh below `entity` from its role suffix.
    public static func apply(to entity: Entity, palette: [String: [Double]], overrides: [String: PhysicallyBasedMaterial] = [:]) {
        var cache: [String: any RealityKit.Material] = [:]
        func visit(_ e: Entity) {
            if var model = e.components[ModelComponent.self] {
                let role = roleName(of: e)
                if let role = role {
                    let mat = cache[role] ?? realistic(overrides[role] ?? material(role: role, palette: palette), role: role)
                    cache[role] = mat
                    model.materials = Array(repeating: mat, count: max(1, model.materials.count))
                    e.components.set(model)
                }
            }
            for c in e.children { visit(c) }
        }
        visit(entity)
    }

    /// Role from `Name__role` on the entity or its parent (USD importers may
    /// wrap the mesh in an extra node).
    public static func roleName(of e: Entity) -> String? {
        for name in [e.name, e.parent?.name ?? ""] {
            if let r = name.range(of: "__") { return String(name[r.upperBound...]) }
        }
        return nil
    }
}

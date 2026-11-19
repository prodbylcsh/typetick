import CoreGraphics
import CoreText
import Foundation
import simd
import TypetickCore

/// Procedural desk surfaces, environment maps and key legends.
public enum ProceduralTextures {
    public struct SurfaceSet {
        public var color: CGImage
        public var roughness: CGImage
        public var normal: CGImage
        public var metallic: Float
        /// How many times the texture repeats across one meter.
        public var tilesPerMeter: Float
    }

    private static func c(_ rgb: RGB) -> SIMD3<Float> { SIMD3(Float(rgb.r), Float(rgb.g), Float(rgb.b)) }

    // MARK: desk

    public static func desk(_ style: DeskStyle, size: Int = 1024) -> SurfaceSet? {
        let n = Noise(seed: style.material.rawValue.utf8.reduce(UInt64(0xDE5C)) { $0 &* 31 &+ UInt64($1) })
        var color = Bitmap(width: size, height: size)
        var rough = Bitmap(width: size, height: size, channels: 1)
        var heights = [Float](repeating: 0, count: size * size)
        let gloss = Float(style.gloss)
        let wear = Float(style.wear)
        let grain = Float(style.grainScale)
        var metallic: Float = 0
        var tiles: Float = 1.6

        func wood(_ light: SIMD3<Float>, _ dark: SIMD3<Float>, rings: Float, figure: Float) -> (Int, Int) -> (SIMD3<Float>, Float, Float) {
            return { x, y in
                let u = Float(x) / Float(size), v = Float(y) / Float(size)
                let warp = n.fbm(u * 3, v * 0.6, octaves: 4, period: 3) * figure
                let ringV = (u * rings * grain + warp * 6 + n.fbm(u * 8, v * 1.5, octaves: 3, period: 8) * 0.8)
                let ring = 0.5 + 0.5 * sin(ringV * 2 * .pi)
                let streak = n.fbm(u * 60 * grain, v * 2, octaves: 3, period: 60)
                let t = pow(ring, 2.2) * 0.75 + streak * 0.35
                let col = simd_mix(light, dark, SIMD3(repeating: min(1, t)))
                let pores = n.value(u * 900, v * 40, period: 900) > 0.82 ? Float(0.08) : 0
                return (col * (1 - pores), 1 - gloss * 0.7 + pores * 0.5 + streak * 0.08, ring * 0.3 + streak * 0.6 - pores * 2)
            }
        }

        let sampler: (Int, Int) -> (SIMD3<Float>, Float, Float)
        switch style.material {
        case .walnut: sampler = wood(SIMD3(0.36, 0.21, 0.12), SIMD3(0.16, 0.08, 0.045), rings: 9, figure: 0.9)
        case .oak: sampler = wood(SIMD3(0.70, 0.52, 0.32), SIMD3(0.46, 0.31, 0.17), rings: 14, figure: 0.6)
        case .cherry: sampler = wood(SIMD3(0.58, 0.27, 0.15), SIMD3(0.36, 0.13, 0.07), rings: 8, figure: 0.5)
        case .ebony: sampler = wood(SIMD3(0.10, 0.08, 0.07), SIMD3(0.03, 0.025, 0.02), rings: 20, figure: 0.3)
        case .pine: sampler = wood(SIMD3(0.86, 0.70, 0.48), SIMD3(0.66, 0.45, 0.24), rings: 6, figure: 1.2)
        case .marble:
            tiles = 1.0
            sampler = { x, y in
                let u = Float(x) / Float(size), v = Float(y) / Float(size)
                let turb = n.fbm(u * 4, v * 4, octaves: 6, period: 4)
                let vein = abs(sin((u * 3 + v * 2 + turb * 4) * .pi))
                let t = pow(1 - vein, 8)
                let base = SIMD3<Float>(0.90, 0.89, 0.86) - n.fbm(u * 12, v * 12, octaves: 3, period: 12) * 0.06
                return (simd_mix(base, SIMD3(0.35, 0.36, 0.38), SIMD3(repeating: t)), 0.18 - gloss * 0.12 + t * 0.1, -t)
            }
        case .slate:
            tiles = 1.2
            sampler = { x, y in
                let u = Float(x) / Float(size), v = Float(y) / Float(size)
                let layers = n.fbm(u * 2, v * 14, octaves: 5, period: 2)
                let g = 0.16 + layers * 0.12
                return (SIMD3(g, g * 1.03, g * 1.08), 0.75 - gloss * 0.3, layers)
            }
        case .leather:
            tiles = 4
            sampler = { x, y in
                let u = Float(x) / Float(size), v = Float(y) / Float(size)
                let cells = n.value(u * 160, v * 160, period: 160)
                let pebble = pow(cells, 0.6)
                let mott = n.fbm(u * 6, v * 6, octaves: 4, period: 6)
                let base = SIMD3<Float>(0.24, 0.13, 0.07) * (0.75 + 0.5 * mott)
                return (base * (0.85 + 0.15 * pebble), 0.55 - gloss * 0.25 + (1 - pebble) * 0.15, pebble)
            }
        case .felt:
            tiles = 3
            sampler = { x, y in
                let u = Float(x) / Float(size), v = Float(y) / Float(size)
                let fuzz = n.fbm(u * 200, v * 200, octaves: 2, period: 200)
                return (SIMD3(0.10, 0.24, 0.15) * (0.85 + 0.3 * fuzz), 0.98, fuzz * 0.4)
            }
        case .linoleum:
            tiles = 2
            sampler = { x, y in
                let u = Float(x) / Float(size), v = Float(y) / Float(size)
                let speck = n.value(u * 300, v * 300, period: 300)
                let mott = n.fbm(u * 5, v * 5, octaves: 4, period: 5)
                var col = SIMD3<Float>(0.40, 0.48, 0.42) * (0.9 + 0.2 * mott)
                if speck > 0.9 { col = SIMD3(0.85, 0.83, 0.75) }
                return (col, 0.45 - gloss * 0.2, mott * 0.2)
            }
        case .steel:
            tiles = 2
            metallic = 1
            sampler = { x, y in
                let u = Float(x) / Float(size), v = Float(y) / Float(size)
                let brush = n.fbm(u * 2, v * 300, octaves: 3, period: 2)
                let g = 0.55 + brush * 0.15
                return (SIMD3(g, g, g * 1.02), 0.32 - gloss * 0.2 + brush * 0.1, brush * 0.2)
            }
        case .concrete:
            tiles = 1.5
            sampler = { x, y in
                let u = Float(x) / Float(size), v = Float(y) / Float(size)
                let f = n.fbm(u * 10, v * 10, octaves: 6, period: 10)
                let pit = n.value(u * 500, v * 500, period: 500) > 0.93 ? Float(0.6) : 1
                let g = (0.52 + f * 0.18) * pit
                return (SIMD3(g, g * 0.99, g * 0.96), 0.9, f - (1 - pit))
            }
        case .glass:
            tiles = 1
            sampler = { x, y in
                let u = Float(x) / Float(size), v = Float(y) / Float(size)
                let smudge = n.fbm(u * 6, v * 6, octaves: 4, period: 6)
                return (SIMD3(0.05, 0.07, 0.07), 0.04 + smudge * 0.12 * (1 - gloss), 0)
            }
        }

        let tint = style.tint.map(c)
        for y in 0..<size {
            for x in 0..<size {
                var (col, r, h) = sampler(x, y)
                if let t = tint { col = col * (t * 1.6) }
                let u = Float(x) / Float(size), v = Float(y) / Float(size)
                let scratches = n.value(u * 2, v * 400, period: 2) > (1 - 0.05 * wear) ? Float(0.15) : 0
                let wearMask = n.fbm(u * 3, v * 3, octaves: 3, period: 3) * wear
                col = col * (1 + scratches * 0.4) + SIMD3(repeating: wearMask * 0.05)
                r = r + wearMask * 0.25 + scratches * 0.2
                color.set(x, y, col)
                rough.setGray(x, y, r)
                heights[y * size + x] = h - scratches
            }
        }
        let normal = Bitmap.normalMap(from: heights, width: size, height: size, strength: 2.5)
        guard let ci = color.makeImage(), let ri = rough.makeImage(), let ni = normal.makeImage() else { return nil }
        return SurfaceSet(color: ci, roughness: ri, normal: ni, metallic: metallic, tilesPerMeter: tiles / max(grain, 0.2))
    }

    // MARK: environment (equirectangular IBL)

    public static func environment(_ env: EnvironmentStyle, width: Int = 1024) -> CGImage? {
        let h = width / 2
        var bmp = Bitmap(width: width, height: h)
        let n = Noise(seed: 0xE7)
        let lamp = env.lamp == .neon ? c(env.neonColor) : c(EnvironmentStyle.kelvinToRGB(env.lampKelvin))
        let sky: SIMD3<Float>
        let sun: SIMD3<Float>
        switch env.timeOfDay {
        case .dawn: sky = SIMD3(0.75, 0.62, 0.62); sun = SIMD3(1.0, 0.72, 0.5)
        case .day: sky = SIMD3(0.75, 0.85, 1.0); sun = SIMD3(1.0, 0.97, 0.9)
        case .dusk: sky = SIMD3(0.55, 0.38, 0.45); sun = SIMD3(1.0, 0.55, 0.3)
        case .night: sky = SIMD3(0.05, 0.07, 0.14); sun = SIMD3(0.4, 0.5, 0.75)
        }
        let roomBase: SIMD3<Float> = env.timeOfDay == .night ? SIMD3(0.03, 0.028, 0.03) : SIMD3(0.18, 0.16, 0.14)
        let ambient = Float(env.ambient)
        for y in 0..<h {
            let lat = (0.5 - Float(y) / Float(h)) * .pi            // +pi/2 up
            for x in 0..<width {
                let lon = (Float(x) / Float(width)) * 2 * .pi - .pi  // 0 = -Z
                var col = roomBase * (0.6 + 0.8 * ambient)
                // floor darker, ceiling a bit lighter
                col *= lat < 0 ? 0.55 : 1.0 + lat * 0.3
                col += SIMD3(repeating: n.fbm(Float(x) / 64, Float(y) / 64, octaves: 3, period: 16) * 0.02)
                // window on the left wall
                if env.windowLight {
                    let dl = abs(lon - (-1.25)), dlat = abs(lat - 0.25)
                    if dl < 0.45 && dlat < 0.35 {
                        let mullion = (abs(lon + 1.25) < 0.012 || abs(lat - 0.25) < 0.01) ? Float(0.2) : 1
                        let brightness: Float = env.timeOfDay == .night ? 0.25 : 3.2
                        col = sky * brightness * mullion
                    } else {
                        let d = sqrt(pow(dl / 0.9, 2) + pow(dlat / 0.7, 2))
                        col += sky * max(0, 1 - d) * (env.timeOfDay == .night ? 0.05 : 0.35)
                    }
                    if env.timeOfDay != .night {
                        let ds = sqrt(pow(lon + 1.3, 2) + pow(lat - 0.45, 2))
                        col += sun * max(0, 1 - ds * 6) * 6
                    }
                }
                // lamp glow up and to the right
                if env.lamp != .none {
                    let dl = sqrt(pow(lon - 0.65, 2) + pow(lat - 0.55, 2))
                    col += lamp * Float(env.lampIntensity) * (max(0, 1 - dl * 3.5) * 4 + max(0, 1 - dl * 12) * 18)
                }
                bmp.set(x, y, col / (col + 1) * 1.25)   // soft tone map into 8 bit
            }
        }
        return bmp.makeImage()
    }

    // MARK: key legends

    public static func keyLegend(_ text: String, sub: String? = nil, ink: RGB, ground: RGB, size: Int = 256,
                                 style: String = "printed") -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: ground.r, green: ground.g, blue: ground.b, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        // subtle radial falloff, like a domed or dished top
        if let grad = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.10), CGColor(gray: 0, alpha: 0.12)] as CFArray,
                                 locations: [0, 1]) {
            ctx.drawRadialGradient(grad, startCenter: CGPoint(x: size / 2 - size / 10, y: size / 2 + size / 10), startRadius: 0,
                                   endCenter: CGPoint(x: size / 2, y: size / 2), endRadius: CGFloat(size) * 0.55, options: [])
        }
        let fontName = style == "engraved" ? "Futura-Medium" : (style == "stamped" ? "Courier-Bold" : "AvenirNext-DemiBold")
        func draw(_ s: String, _ pt: CGFloat, _ center: CGPoint) {
            let font = CTFontCreateWithName(fontName as CFString, pt, nil)
            let attrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(srgbRed: ink.r, green: ink.g, blue: ink.b, alpha: 1),
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
            let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            ctx.textPosition = CGPoint(x: center.x - b.width / 2 - b.minX, y: center.y - b.height / 2 - b.minY)
            CTLineDraw(line, ctx)
        }
        let s = CGFloat(size)
        if let sub = sub {
            draw(sub, s * 0.26, CGPoint(x: s * 0.5, y: s * 0.68))
            draw(text, s * 0.30, CGPoint(x: s * 0.5, y: s * 0.32))
        } else {
            draw(text, text.count > 2 ? s * 0.20 : s * 0.42, CGPoint(x: s / 2, y: s / 2))
        }
        return ctx.makeImage()
    }
}

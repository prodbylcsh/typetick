import CoreGraphics
import CoreText
import Foundation
import simd
import TypetickCore

/// Paints a sheet: paper body, ink strikes, impressions and corrections.
///
/// Four layers are kept: color (full resolution), and height/roughness/metal
/// at half resolution. Height becomes a normal map so type impressions and
/// creases catch the lamp, roughness/metal let foils and pearls shine.
public final class PaperRenderer {
    public let sheet: Sheet
    public let pxPerPoint: CGFloat
    public let size: CGSize          // pixels, color layer
    public let color: CGContext
    public let height: CGContext
    public let roughness: CGContext
    public let metal: CGContext
    public let normal: CGContext
    public private(set) var dirtyColor: CGRect?
    public private(set) var dirtyAux: CGRect?
    private var paper: PaperStyle
    private var styles: [StrikeStyle]
    private var spec: MachineSpec
    private var fontCache: [String: (CTFont, CGFloat)] = [:]

    public init?(sheet: Sheet, dpi: CGFloat, spec: MachineSpec) {
        self.sheet = sheet
        paper = sheet.paper
        styles = sheet.styles
        self.spec = spec
        pxPerPoint = dpi / 72
        let (w, h) = sheet.pageSize
        size = CGSize(width: (CGFloat(w) * pxPerPoint).rounded(), height: (CGFloat(h) * pxPerPoint).rounded())
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let gray = CGColorSpaceCreateDeviceGray()
        let W = Int(size.width), H = Int(size.height)
        guard let c = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let hc = CGContext(data: nil, width: W / 2, height: H / 2, bitsPerComponent: 8, bytesPerRow: W / 2, space: gray,
                                 bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let rc = CGContext(data: nil, width: W / 2, height: H / 2, bitsPerComponent: 8, bytesPerRow: W / 2, space: gray,
                                 bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let mc = CGContext(data: nil, width: W / 2, height: H / 2, bitsPerComponent: 8, bytesPerRow: W / 2, space: gray,
                                 bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let nc = CGContext(data: nil, width: W / 2, height: H / 2, bitsPerComponent: 8, bytesPerRow: W * 2, space: space,
                                 bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        color = c; height = hc; roughness = rc; metal = mc; normal = nc
        // Page space: points, y down from the top edge.
        for (ctx, s) in [(color, pxPerPoint), (height, pxPerPoint / 2), (roughness, pxPerPoint / 2), (metal, pxPerPoint / 2)] {
            ctx.translateBy(x: 0, y: CGFloat(ctx.height))
            ctx.scaleBy(x: s, y: -s)
            ctx.interpolationQuality = .high
            ctx.setShouldAntialias(true)
            ctx.setAllowsFontSmoothing(false)
        }
        paintPaper()
        for strike in sheet.strikes { draw(strike, markDirty: false) }
        rebuildNormals(in: nil)
        dirtyColor = CGRect(origin: .zero, size: size)
        dirtyAux = CGRect(x: 0, y: 0, width: size.width / 2, height: size.height / 2)
    }

    public func update(styles: [StrikeStyle]) { self.styles = styles }

    public func takeDirty() -> (color: CGRect?, aux: CGRect?) {
        defer { dirtyColor = nil; dirtyAux = nil }
        return (dirtyColor, dirtyAux)
    }

    // MARK: paper body

    private func cg(_ c: RGB, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: a) }

    private func paintPaper() {
        let (w, h) = sheet.pageSize
        let page = CGRect(x: 0, y: 0, width: w, height: h)
        let base = paper.color
        color.setFillColor(cg(base))
        color.fill(page)
        let n = Noise(seed: sheet.id.uuidString.utf8.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 })
        let dark = paper.isDark

        // Low-frequency mottling (cloudy formation of the sheet).
        let mw = 160, mh = Int(Double(mw) * h / w)
        var mottle = Bitmap(width: mw, height: mh, channels: 4)
        for y in 0..<mh {
            for x in 0..<mw {
                let v = n.fbm(Float(x) / 20, Float(y) / 20, octaves: 4, period: 64)
                let a = Float(0.05 + paper.fibers * 0.05)
                let tone: Float = v > 0.5 ? 1 : 0
                mottle.set(x, y, SIMD3(repeating: tone) * a, alpha: abs(v - 0.5) * 2 * a)
            }
        }
        if let img = mottle.makeImage() { color.draw(img, in: page) }

        // High-frequency tooth + fibers, drawn as a tile.
        let tile = 384
        var grain = Bitmap(width: tile, height: tile, channels: 4)
        var heightTile = Bitmap(width: tile, height: tile, channels: 1)
        let tooth = Float(paper.tooth)
        for y in 0..<tile {
            for x in 0..<tile {
                let fx = Float(x), fy = Float(y)
                var v = n.value(fx / 1.6, fy / 1.6, period: Int(Float(tile) / 1.6)) - 0.5
                v += (n.value(fx / 5, fy / 5, period: tile / 5) - 0.5) * 0.6
                switch paper.finish {
                case .laid:
                    v += (sin(fy * 2 * .pi / 9) > 0.85 ? 0.35 : 0)
                case .linen:
                    v += 0.25 * (sin(fx * 2 * .pi / 6) + sin(fy * 2 * .pi / 6))
                case .watercolor, .cotton:
                    v += (n.value(fx / 14, fy / 14, period: tile / 14) - 0.5) * 1.2
                case .glossy:
                    v *= 0.25
                default: break
                }
                let a = (0.05 + tooth * 0.18) * min(1, abs(v) * 1.5)
                grain.set(x, y, v > 0 ? SIMD3(repeating: 1) * a : SIMD3(repeating: 0), alpha: a)
                heightTile.setGray(x, y, 0.5 + v * (0.15 + tooth * 0.35))
            }
        }
        // fibers
        var rng = SplitMix(seed: 0xF1BE)
        let fiberCount = Int(40 + paper.fibers * 260)
        if let gimg = grain.makeImage(), let tileCtx = CGContext(data: nil, width: tile, height: tile, bitsPerComponent: 8, bytesPerRow: tile * 4,
                                                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            tileCtx.draw(gimg, in: CGRect(x: 0, y: 0, width: tile, height: tile))
            for _ in 0..<fiberCount {
                let x = CGFloat(rng.unit()) * CGFloat(tile), y = CGFloat(rng.unit()) * CGFloat(tile)
                let len = CGFloat(4 + rng.unit() * 22)
                let ang = CGFloat(rng.unit()) * .pi * 2
                let path = CGMutablePath()
                path.move(to: CGPoint(x: x, y: y))
                path.addQuadCurve(to: CGPoint(x: x + cos(ang) * len, y: y + sin(ang) * len),
                                  control: CGPoint(x: x + cos(ang + 0.6) * len * 0.5, y: y + sin(ang + 0.6) * len * 0.5))
                let tint: CGFloat = dark ? 1 : CGFloat(rng.unit() < 0.15 ? 0.25 : 0.0)
                tileCtx.setStrokeColor(CGColor(gray: tint, alpha: 0.05 + CGFloat(paper.fibers) * 0.10))
                tileCtx.setLineWidth(0.6 + CGFloat(rng.unit()))
                tileCtx.addPath(path)
                tileCtx.strokePath()
            }
            if let tiled = tileCtx.makeImage() {
                // tile is laid at ~1 pixel per texel
                let tilePts = CGFloat(tile) / pxPerPoint
                color.draw(tiled, in: CGRect(x: 0, y: 0, width: tilePts, height: tilePts), byTiling: true)
            }
        }
        if let himg = heightTile.makeImage() {
            let tilePts = CGFloat(tile) / pxPerPoint
            height.draw(himg, in: CGRect(x: 0, y: 0, width: tilePts, height: tilePts), byTiling: true)
        }

        // Laid paper chain lines.
        if paper.finish == .laid {
            color.setStrokeColor(CGColor(gray: dark ? 1 : 0, alpha: 0.025))
            color.setLineWidth(1.2)
            var x: CGFloat = 18
            while x < CGFloat(w) {
                color.move(to: CGPoint(x: x, y: 0)); color.addLine(to: CGPoint(x: x, y: h)); color.strokePath()
                x += 72
            }
        }

        // Creases and cockles in the height map, with matching faint shading.
        let wrinkle = CGFloat(paper.wrinkle)
        if wrinkle > 0.01 {
            let count = Int(2 + wrinkle * 10)
            for _ in 0..<count {
                let a = CGPoint(x: CGFloat(rng.unit()) * CGFloat(w), y: CGFloat(rng.unit()) * CGFloat(h))
                let ang = CGFloat(rng.unit()) * .pi
                let len = CGFloat(80 + rng.unit() * 400) * wrinkle
                let b = CGPoint(x: a.x + cos(ang) * len, y: a.y + sin(ang) * len)
                height.setStrokeColor(CGColor(gray: 0.3, alpha: 0.6 * wrinkle))
                height.setLineWidth(1.2)
                height.setShadow(offset: .zero, blur: 6, color: CGColor(gray: 0.2, alpha: 0.5))
                height.move(to: a); height.addLine(to: b); height.strokePath()
                height.setShadow(offset: .zero, blur: 0, color: nil)
                color.setStrokeColor(CGColor(gray: dark ? 1 : 0, alpha: 0.03 * wrinkle))
                color.setLineWidth(0.8)
                color.move(to: a); color.addLine(to: b); color.strokePath()
            }
        }

        // Aging: warm edges and foxing spots.
        let age = CGFloat(paper.age)
        if age > 0.01 {
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            if let g = CGGradient(colorsSpace: space, colors: [CGColor(srgbRed: 0.55, green: 0.38, blue: 0.15, alpha: 0),
                                                               CGColor(srgbRed: 0.55, green: 0.38, blue: 0.15, alpha: 0.18 * age)] as CFArray,
                                  locations: [0.72, 1]) {
                color.drawRadialGradient(g, startCenter: CGPoint(x: w / 2, y: h / 2), startRadius: 0,
                                         endCenter: CGPoint(x: w / 2, y: h / 2), endRadius: CGFloat(max(w, h)) * 0.62, options: [.drawsAfterEndLocation])
            }
            for _ in 0..<Int(age * 40) {
                let p = CGPoint(x: CGFloat(rng.unit()) * CGFloat(w), y: CGFloat(rng.unit()) * CGFloat(h))
                let r = CGFloat(0.5 + rng.unit() * 3) * (1 + age)
                color.setFillColor(CGColor(srgbRed: 0.5, green: 0.32, blue: 0.14, alpha: 0.08 + 0.12 * CGFloat(rng.unit())))
                color.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
        }

        // Roughness of the sheet.
        roughness.setFillColor(CGColor(gray: CGFloat(paper.finish.surfaceRoughness), alpha: 1))
        roughness.fill(page)
        metal.setFillColor(CGColor(gray: 0, alpha: 1))
        metal.fill(page)
    }

    // MARK: strikes

    private func font(for typeface: TypefaceStyle, pitch: CGFloat) -> (CTFont, CGFloat) {
        let key = "\(typeface.fontName)|\(pitch)|\(typeface.scale)"
        if let f = fontCache[key] { return f }
        let probe: CTFont
        if typeface.fontName == "system-mono" {
            probe = CTFontCreateUIFontForLanguage(.userFixedPitch, 12, nil) ?? CTFontCreateWithName("Menlo-Regular" as CFString, 12, nil)
        } else {
            probe = CTFontCreateWithName(typeface.fontName as CFString, 12, nil)
        }
        var glyph = CGGlyph(0)
        var ch: UniChar = 0x4D // "M"
        CTFontGetGlyphsForCharacters(probe, &ch, &glyph, 1)
        var adv = CGSize.zero
        CTFontGetAdvancesForGlyphs(probe, .horizontal, &glyph, &adv, 1)
        let ratio = max(adv.width / 12, 0.45)
        let size = pitch / ratio * CGFloat(typeface.scale)
        let f = CTFontCreateCopyWithAttributes(probe, size, nil, nil)
        fontCache[key] = (f, size)
        return (f, size)
    }

    private func glyphPath(_ text: String, font: CTFont) -> (CGPath, CGFloat) {
        let attr = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attr)
        let path = CGMutablePath()
        var advance: CGFloat = 0
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            let attrs = CTRunGetAttributes(run) as NSDictionary
            let runFont = attrs[kCTFontAttributeName as String] as! CTFont
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for i in 0..<count {
                if let gp = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) {
                    path.addPath(gp, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
                }
            }
        }
        advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        return (path, advance)
    }

    public func draw(_ s: Strike, markDirty: Bool = true) {
        let style = styles.indices.contains(s.style) ? styles[s.style] : StrikeStyle(ink: InkStyle(), typeface: TypefaceStyle())
        let ink = style.ink
        let (font, _) = self.font(for: style.typeface, pitch: CGFloat(s.pitch))
        let (raw, advance) = glyphPath(s.character, font: font)
        var rng = SplitMix(seed: UInt64(s.seed) | 0x1_0000_0000)
        let jitter = CGFloat(style.typeface.baselineJitter * (0.4 + spec.alignmentJitter))
        let dx = (CGFloat(rng.unit()) - 0.5) * jitter * 0.6
        let dy = (CGFloat(rng.unit()) - 0.5) * jitter
        let rot = (CGFloat(rng.unit()) - 0.5) * CGFloat(style.typeface.rotationJitter) * .pi / 180
        // Glyph space is y-up; page space is y-down: flip around the baseline.
        let ox = CGFloat(s.x) + (CGFloat(s.pitch) - advance) / 2 + dx
        let oy = CGFloat(s.baseline) + dy
        var t = CGAffineTransform(translationX: ox + advance / 2, y: oy)
            .rotated(by: rot)
            .translatedBy(x: -advance / 2, y: 0)
            .scaledBy(x: 1, y: -1)
        guard let path = raw.copy(using: &t) else { return }
        let bounds = path.boundingBoxOfPath.insetBy(dx: -4, dy: -4)
        let pressure = CGFloat(s.pressure)
        let soft = CGFloat(1 - paper.hardness)

        switch s.kind {
        case .ink:
            drawInk(path: path, bounds: bounds, ink: ink, color: style.effectiveColor, pressure: pressure, rng: &rng)
            // Impression: the slug dents the paper; soft paper keeps a deep bite.
            height.saveGState()
            height.addPath(path)
            height.setFillColor(CGColor(gray: 0, alpha: 0.18 + 0.55 * soft * pressure))
            height.setShadow(offset: .zero, blur: 1.2, color: CGColor(gray: 0, alpha: 0.4 * soft))
            height.fillPath()
            height.restoreGState()
        case .coverUp:
            let paperColor = paper.color.offset(spec.correctionTint)
            let tint = paper.isDark ? paperColor : paperColor.mixed(with: .white, 0.25)
            color.saveGState()
            color.addPath(path)
            color.setLineWidth(1.1)
            color.setLineJoin(.round)
            color.setStrokeColor(cg(tint, CGFloat(spec.correctionCoverage)))
            color.setFillColor(cg(tint, CGFloat(spec.correctionCoverage)))
            color.drawPath(using: .fillStroke)
            // chalky grain
            color.addPath(path.copy(strokingWithWidth: 1.1, lineCap: .round, lineJoin: .round, miterLimit: 2))
            color.addPath(path)
            color.clip()
            for _ in 0..<30 {
                let p = CGPoint(x: bounds.minX + CGFloat(rng.unit()) * bounds.width, y: bounds.minY + CGFloat(rng.unit()) * bounds.height)
                color.setFillColor(CGColor(gray: CGFloat(rng.unit()) > 0.5 ? 1 : 0.6, alpha: 0.12))
                color.fill(CGRect(x: p.x, y: p.y, width: 0.35, height: 0.35))
            }
            color.restoreGState()
            roughness.saveGState()
            roughness.addPath(path)
            roughness.setLineWidth(1.1)
            roughness.setFillColor(CGColor(gray: 0.97, alpha: 1))
            roughness.setStrokeColor(CGColor(gray: 0.97, alpha: 1))
            roughness.drawPath(using: .fillStroke)
            roughness.restoreGState()
            metal.saveGState()
            metal.addPath(path)
            metal.setLineWidth(1.1)
            metal.setFillColor(CGColor(gray: 0, alpha: 1))
            metal.setStrokeColor(CGColor(gray: 0, alpha: 1))
            metal.drawPath(using: .fillStroke)
            metal.restoreGState()
            height.saveGState()
            height.addPath(path)
            height.setFillColor(CGColor(gray: 0.62, alpha: 0.6))
            height.fillPath()
            height.restoreGState()
        case .liftOff:
            color.saveGState()
            color.addPath(path)
            color.setLineWidth(0.5)
            let a = CGFloat(spec.correctionCoverage)
            color.setFillColor(cg(paper.color, a))
            color.setStrokeColor(cg(paper.color, a))
            color.drawPath(using: .fillStroke)
            color.restoreGState()
            roughness.saveGState()
            roughness.addPath(path)
            roughness.setFillColor(CGColor(gray: CGFloat(paper.finish.surfaceRoughness) + 0.06, alpha: 1))
            roughness.fillPath()
            roughness.restoreGState()
            metal.saveGState()
            metal.addPath(path)
            metal.setFillColor(CGColor(gray: 0, alpha: 1))
            metal.fillPath()
            metal.restoreGState()
        }

        if markDirty {
            let pxRect = pixelRect(bounds, scale: pxPerPoint)
            dirtyColor = dirtyColor.map { $0.union(pxRect) } ?? pxRect
            let auxRect = pixelRect(bounds.insetBy(dx: -2, dy: -2), scale: pxPerPoint / 2)
            dirtyAux = dirtyAux.map { $0.union(auxRect) } ?? auxRect
            rebuildNormals(in: auxRect)
        }
    }

    private func drawInk(path: CGPath, bounds: CGRect, ink: InkStyle, color base: RGB, pressure: CGFloat, rng: inout SplitMix) {
        let density = CGFloat(ink.density) * min(1.15, 0.7 + 0.35 * pressure) * (1 - CGFloat(ink.variance) * 0.25 * CGFloat(rng.unit()))
        let ctx = color
        ctx.saveGState()
        // halo / bleed
        if ink.halo > 0.01 {
            ctx.saveGState()
            ctx.addPath(path)
            ctx.setShadow(offset: .zero, blur: CGFloat(1.5 + ink.halo * 3) * pxPerPoint, color: cg(base, CGFloat(ink.halo) * 0.35))
            ctx.setFillColor(cg(base, 0.02))
            ctx.fillPath()
            ctx.restoreGState()
        }
        let bleed = CGFloat(ink.bleed) * (1.3 - CGFloat(paper.hardness) * 0.6)
        if bleed > 0.01 {
            ctx.saveGState()
            ctx.addPath(path)
            ctx.setLineWidth(bleed * 0.6)
            ctx.setLineJoin(.round)
            ctx.setStrokeColor(cg(base, density * 0.35))
            ctx.setShadow(offset: .zero, blur: bleed * 0.9 * pxPerPoint, color: cg(base, density * 0.5))
            ctx.strokePath()
            ctx.restoreGState()
        }

        ctx.addPath(path)
        ctx.clip()
        switch ink.kind {
        case .iridescent:
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let hueShift: [RGB] = [base, base.mixed(with: RGB(0.2, 0.75, 0.7), 0.6), base.mixed(with: RGB(0.75, 0.3, 0.8), 0.6), base]
            if let g = CGGradient(colorsSpace: space, colors: hueShift.map { cg($0, density) } as CFArray, locations: [0, 0.35, 0.7, 1]) {
                let a = CGFloat(rng.unit()) * .pi
                let c = CGPoint(x: bounds.midX, y: bounds.midY)
                let d = max(bounds.width, bounds.height)
                ctx.drawLinearGradient(g, start: CGPoint(x: c.x - cos(a) * d, y: c.y - sin(a) * d),
                                       end: CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d), options: [])
            }
        case .pearlescent:
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let tones = [base, base.mixed(with: RGB(0.95, 0.85, 0.9), 0.5), base.mixed(with: RGB(0.8, 0.92, 0.95), 0.5)]
            if let g = CGGradient(colorsSpace: space, colors: tones.map { cg($0, density) } as CFArray, locations: [0, 0.5, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: bounds.minX, y: bounds.minY), end: CGPoint(x: bounds.maxX, y: bounds.maxY), options: [])
            }
        default:
            ctx.setFillColor(cg(base, min(1, density)))
            ctx.fill(bounds)
        }
        // Uneven slug contact: one side of the glyph prints lighter.
        if ink.variance > 0.01 && ink.kind != .carbon {
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let p = paper.color
            if let g = CGGradient(colorsSpace: space, colors: [cg(p, 0), cg(p, CGFloat(ink.variance) * 0.45)] as CFArray, locations: [0, 1]) {
                let a = CGFloat(rng.unit()) * .pi * 2
                let c = CGPoint(x: bounds.midX, y: bounds.midY)
                let r = bounds.width * 0.6
                ctx.drawLinearGradient(g, start: c, end: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r), options: [.drawsAfterEndLocation])
            }
        }
        // Ribbon weave / wear dropouts.
        if (ink.kind == .fabric || ink.kind == .chalk) && (ink.wear > 0.01 || ink.kind == .chalk) {
            let step: CGFloat = 0.55
            let p = paper.color
            var y = bounds.minY
            let wear = CGFloat(ink.kind == .chalk ? max(ink.wear, 0.5) : ink.wear)
            while y < bounds.maxY {
                var x = bounds.minX + (Int((y - bounds.minY) / step) % 2 == 0 ? 0 : step / 2)
                while x < bounds.maxX {
                    if CGFloat(rng.unit()) < wear * 0.55 {
                        ctx.setFillColor(cg(p, 0.35 + 0.5 * CGFloat(rng.unit())))
                        ctx.fill(CGRect(x: x, y: y, width: step * 0.6, height: step * 0.6))
                    }
                    x += step
                }
                y += step
            }
        }
        if ink.kind == .glitter {
            for _ in 0..<Int(bounds.width * bounds.height * 0.6) {
                let pt = CGPoint(x: bounds.minX + CGFloat(rng.unit()) * bounds.width, y: bounds.minY + CGFloat(rng.unit()) * bounds.height)
                let f = CGFloat(0.25 + rng.unit() * 0.5)
                let bright = base.mixed(with: .white, Double(rng.unit()) * 0.7)
                ctx.setFillColor(cg(bright, 1))
                ctx.fill(CGRect(x: pt.x, y: pt.y, width: f, height: f))
            }
        }
        if ink.kind == .fluorescent {
            ctx.setBlendMode(.screen)
            ctx.setFillColor(cg(base.mixed(with: .white, 0.15), 0.35))
            ctx.fill(bounds)
        }
        ctx.restoreGState()

        // Surface response layers.
        let (rough, metallic): (CGFloat, CGFloat) = {
            switch ink.kind {
            case .fabric: return (0.9, 0)
            case .carbon: return (0.55, 0)
            case .pearlescent: return (0.28, 0.35 * CGFloat(ink.sheen))
            case .metallic: return (0.22, 0.95 * CGFloat(ink.sheen) + 0.05)
            case .glitter: return (0.2, 0.9 * CGFloat(ink.sheen))
            case .iridescent: return (0.3, 0.5 * CGFloat(ink.sheen))
            case .fluorescent: return (0.6, 0)
            case .chalk: return (0.98, 0)
            }
        }()
        roughness.saveGState(); roughness.addPath(path); roughness.setFillColor(CGColor(gray: rough, alpha: 1)); roughness.fillPath(); roughness.restoreGState()
        if metallic > 0 {
            metal.saveGState()
            metal.addPath(path)
            metal.clip()
            if ink.kind == .glitter {
                for _ in 0..<Int(bounds.width * bounds.height * 0.5) {
                    let pt = CGPoint(x: bounds.minX + CGFloat(rng.unit()) * bounds.width, y: bounds.minY + CGFloat(rng.unit()) * bounds.height)
                    metal.setFillColor(CGColor(gray: metallic * CGFloat(0.5 + rng.unit() * 0.5), alpha: 1))
                    metal.fill(CGRect(x: pt.x, y: pt.y, width: 0.6, height: 0.6))
                }
            } else {
                metal.setFillColor(CGColor(gray: metallic, alpha: 1))
                metal.fill(bounds)
            }
            metal.restoreGState()
        }
    }

    private func pixelRect(_ r: CGRect, scale: CGFloat) -> CGRect {
        CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale).integral
    }

    /// Recomputes normals from the height layer (pixel rect in aux space, top-left origin).
    private func rebuildNormals(in rect: CGRect?) {
        guard let hData = height.data?.assumingMemoryBound(to: UInt8.self),
              let nData = normal.data?.assumingMemoryBound(to: UInt8.self) else { return }
        let W = height.width, H = height.height
        let r = (rect ?? CGRect(x: 0, y: 0, width: W, height: H)).intersection(CGRect(x: 0, y: 0, width: W, height: H))
        guard !r.isEmpty else { return }
        let hb = height.bytesPerRow, nb = normal.bytesPerRow
        let strength: Float = 2.2 + Float(1 - paper.hardness) * 2
        for y in Int(r.minY)..<Int(r.maxY) {
            for x in Int(r.minX)..<Int(r.maxX) {
                let xl = max(0, x - 1), xr = min(W - 1, x + 1), yu = max(0, y - 1), yd = min(H - 1, y + 1)
                let dx = (Float(hData[y * hb + xr]) - Float(hData[y * hb + xl])) / 255 * strength
                let dy = (Float(hData[yd * hb + x]) - Float(hData[yu * hb + x])) / 255 * strength
                let n = simd_normalize(SIMD3<Float>(-dx, dy, 1)) * 0.5 + 0.5
                let i = y * nb + x * 4
                nData[i] = UInt8(n.x * 255)
                nData[i + 1] = UInt8(n.y * 255)
                nData[i + 2] = UInt8(n.z * 255)
                nData[i + 3] = 255
            }
        }
    }

    /// A flat, high resolution image of the sheet for the reading view and export.
    public func snapshot() -> CGImage? { color.makeImage() }
}

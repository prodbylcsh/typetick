import Foundation
import Metal
import RealityKit
import simd

/// Custom Metal post-processing for the RealityKit view:
/// SSAO -> bilateral blur, bloom (dual filter), lamp light shafts,
/// composite + color grade + film, FXAA + light sharpening.
///
/// Runs on RealityKit's render thread through `ARView.renderCallbacks`.
public final class PostProcessor: @unchecked Sendable {
    private let lock = NSLock()
    private var _look = RenderLook()
    private var _lampUV = SIMD2<Float>(-0.3, -0.2)
    private var _lampColor = SIMD3<Float>(1, 0.8, 0.6)

    private var device: MTLDevice?
    private var library: MTLLibrary?
    private var pipelines: [String: MTLRenderPipelineState] = [:]
    private var textures: [String: MTLTexture] = [:]
    private var kernel: [SIMD4<Float>] = []
    private var failed = false
    private let start = Date()

    public init() {
        var rng = SystemRandomNumberGenerator()
        for i in 0..<16 {
            var v = SIMD3<Float>(Float.random(in: -1...1, using: &rng), Float.random(in: -1...1, using: &rng), Float.random(in: 0.05...1, using: &rng))
            v = simd_normalize(v) * Float.random(in: 0.1...1, using: &rng)
            let s = Float(i) / 16
            v *= 0.1 + 0.9 * s * s           // more samples close to the surface
            kernel.append(SIMD4(v, 0))
        }
    }

    public var look: RenderLook {
        get { lock.lock(); defer { lock.unlock() }; return _look }
        set { lock.lock(); _look = newValue; lock.unlock() }
    }

    /// Lamp position in normalized screen coordinates (may be off screen).
    public func setLamp(uv: SIMD2<Float>, color: SIMD3<Float>) {
        lock.lock(); _lampUV = uv; _lampColor = color; lock.unlock()
    }

    public func install(on view: ARView) {
        view.renderCallbacks.prepareWithDevice = { [weak self] device in self?.prepare(device) }
        view.renderCallbacks.postProcess = { [weak self] context in
            guard let self = self else { return }
            self.process(context)
        }
    }

    private func prepare(_ device: MTLDevice) {
        self.device = device
        do {
            library = try device.makeLibrary(source: PostFXShaders.source, options: nil)
        } catch {
            NSLog("Typetick: post FX shaders failed to compile: \(error)")
            failed = true
        }
    }

    // MARK: resources

    private func pipeline(_ fragment: String, format: MTLPixelFormat) -> MTLRenderPipelineState? {
        let key = "\(fragment)|\(format.rawValue)"
        if let p = pipelines[key] { return p }
        guard let device = device, let lib = library,
              let vf = lib.makeFunction(name: "vs_fullscreen"), let ff = lib.makeFunction(name: fragment) else { return nil }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = vf
        d.fragmentFunction = ff
        d.colorAttachments[0].pixelFormat = format
        guard let p = try? device.makeRenderPipelineState(descriptor: d) else { return nil }
        pipelines[key] = p
        return p
    }

    private func texture(_ name: String, width: Int, height: Int, format: MTLPixelFormat) -> MTLTexture? {
        let w = max(1, width), h = max(1, height)
        if let t = textures[name], t.width == w, t.height == h, t.pixelFormat == format { return t }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        let t = device?.makeTexture(descriptor: d)
        textures[name] = t
        return t
    }

    private func pass(_ cb: MTLCommandBuffer, target: MTLTexture, fragment: String,
                      textures: [MTLTexture?], bytes: [(UnsafeRawPointer, Int)] = []) {
        guard let pso = pipeline(fragment, format: target.pixelFormat) else { return }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = target
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        enc.setRenderPipelineState(pso)
        for (i, t) in textures.enumerated() { enc.setFragmentTexture(t, index: i) }
        for (i, b) in bytes.enumerated() { enc.setFragmentBytes(b.0, length: b.1, index: i) }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    private func withBytes<T>(_ value: T, _ body: (UnsafeRawPointer, Int) -> Void) {
        var v = value
        withUnsafeBytes(of: &v) { body($0.baseAddress!, MemoryLayout<T>.stride) }
    }

    // MARK: frame

    struct AOUniforms { var invProj: simd_float4x4; var proj: simd_float4x4; var params: SIMD4<Float>; var texel: SIMD4<Float> }
    struct BlurUniforms { var dir: SIMD4<Float>; var params: SIMD4<Float> }
    struct BloomUniforms { var params: SIMD4<Float>; var texel: SIMD4<Float> }
    struct ShaftUniforms { var light: SIMD4<Float>; var params: SIMD4<Float> }
    struct CompositeUniforms {
        var fx: SIMD4<Float>; var grade: SIMD4<Float>; var film: SIMD4<Float>
        var shadowTint: SIMD4<Float>; var highlightTint: SIMD4<Float>; var lampColor: SIMD4<Float>
    }
    struct FXAAUniforms { var texel: SIMD4<Float>; var params: SIMD4<Float> }

    private func process(_ ctx: ARView.PostProcessContext) {
        let src = ctx.sourceColorTexture
        let dst = ctx.targetColorTexture
        let cb = ctx.commandBuffer
        if device == nil { prepare(ctx.device) }
        guard !failed, library != nil else {
            blit(cb, src, dst)
            return
        }
        lock.lock()
        let look = _look
        let lampUV = _lampUV
        let lampColor = _lampColor
        lock.unlock()

        let W = src.width, H = src.height
        let hdr: MTLPixelFormat = .rgba16Float
        let q = look.quality
        let aoScale = q == .balanced ? 2 : (q == .high ? 2 : 1)

        // 1. ambient occlusion
        var aoTex: MTLTexture? = nil
        let depth = ctx.sourceDepthTexture
        let depthUsable = depth.textureType == .type2D
        if look.ambientOcclusion > 0.01, depthUsable,
           let ao = texture("ao", width: W / aoScale, height: H / aoScale, format: .r16Float),
           let aoTmp = texture("aoTmp", width: W / aoScale, height: H / aoScale, format: .r16Float) {
            let proj = ctx.projection
            // reverse-Z if the far plane maps to 0
            let farClip = proj * SIMD4<Float>(0, 0, -1000, 1)
            let reverse: Float = (farClip.z / farClip.w) < 0.5 ? 1 : 0
            let u = AOUniforms(invProj: proj.inverse, proj: proj,
                               params: SIMD4(0.012, 1.6, 0.0004, reverse),
                               texel: SIMD4(1 / Float(depth.width), 1 / Float(depth.height), Float(ao.width), Float(ao.height)))
            withBytes(u) { up, ul in
                kernel.withUnsafeBytes { kb in
                    pass(cb, target: ao, fragment: "fs_ssao", textures: [depth], bytes: [(up, ul), (kb.baseAddress!, kb.count)])
                }
            }
            let sharp: Float = reverse > 0.5 ? 4000 : 1500
            withBytes(BlurUniforms(dir: SIMD4(1 / Float(ao.width), 0, 0, 0), params: SIMD4(sharp, 0, 0, 0))) {
                pass(cb, target: aoTmp, fragment: "fs_aoblur", textures: [ao, depth], bytes: [($0, $1)])
            }
            withBytes(BlurUniforms(dir: SIMD4(0, 1 / Float(ao.height), 0, 0), params: SIMD4(sharp, 0, 0, 0))) {
                pass(cb, target: ao, fragment: "fs_aoblur", textures: [aoTmp, depth], bytes: [($0, $1)])
            }
            aoTex = ao
        }

        // 2. bloom pyramid
        var bloomTex: MTLTexture? = nil
        var brightTex: MTLTexture? = nil
        if look.bloom > 0.01 || look.lightShafts > 0.01 {
            let levels = q == .balanced ? 4 : 5
            var chain: [MTLTexture] = []
            var w = W / 2, h = H / 2
            for i in 0..<levels {
                guard let t = texture("bloom\(i)", width: w, height: h, format: hdr) else { break }
                chain.append(t)
                w /= 2; h /= 2
            }
            if let first = chain.first {
                withBytes(BloomUniforms(params: SIMD4(0.78, 0.25, 0, 0), texel: SIMD4(1 / Float(W), 1 / Float(H), 0, 0))) {
                    pass(cb, target: first, fragment: "fs_bright", textures: [src], bytes: [($0, $1)])
                }
                brightTex = first
                for i in 1..<chain.count {
                    let s = chain[i - 1]
                    withBytes(BloomUniforms(params: .zero, texel: SIMD4(1 / Float(s.width), 1 / Float(s.height), 0, 0))) {
                        pass(cb, target: chain[i], fragment: "fs_down", textures: [s], bytes: [($0, $1)])
                    }
                }
                // upsample back into separate textures (cannot read and write the same one)
                var current = chain.last!
                for i in stride(from: chain.count - 2, through: 0, by: -1) {
                    guard let up = texture("bloomUp\(i)", width: chain[i].width, height: chain[i].height, format: hdr) else { break }
                    withBytes(BloomUniforms(params: .zero, texel: SIMD4(0.5 / Float(current.width), 0.5 / Float(current.height), 0, 0))) {
                        pass(cb, target: up, fragment: "fs_up", textures: [current], bytes: [($0, $1)])
                    }
                    current = up
                }
                bloomTex = current
            }
        }

        // 3. light shafts from the lamp
        var shaftTex: MTLTexture? = nil
        if look.lightShafts > 0.01, let bright = brightTex, let st = texture("shafts", width: W / 2, height: H / 2, format: hdr) {
            let samples: Float = q == .cinematic ? 48 : 24
            withBytes(ShaftUniforms(light: SIMD4(lampUV.x, lampUV.y, 0, 0), params: SIMD4(0.85, 0.965, 0.035, samples))) {
                pass(cb, target: st, fragment: "fs_shafts", textures: [bright], bytes: [($0, $1)])
            }
            shaftTex = st
        }

        // 4. composite and grade
        guard let comp = texture("composite", width: W, height: H, format: hdr) else { blit(cb, src, dst); return }
        let white = textureWhite(cb)
        let black = textureBlack(cb)
        let time = Float(Date().timeIntervalSince(start).truncatingRemainder(dividingBy: 1000))
        let cu = CompositeUniforms(
            fx: SIMD4(Float(look.ambientOcclusion), Float(look.bloom), Float(look.lightShafts), Float(look.chromaticAberration)),
            grade: SIMD4(Float(look.exposure), Float(look.contrast), Float(look.saturation), Float(look.toning)),
            film: SIMD4(Float(look.vignette), Float(look.filmGrain), time, Float(W) / Float(max(H, 1))),
            shadowTint: SIMD4(0.86, 0.98, 1.08, 0), highlightTint: SIMD4(1.07, 1.0, 0.9, 0),
            lampColor: SIMD4(lampColor, 0))
        withBytes(cu) {
            pass(cb, target: comp, fragment: "fs_composite", textures: [src, aoTex ?? white, bloomTex ?? black, shaftTex ?? black], bytes: [($0, $1)])
        }

        // 5. anti-aliasing into the drawable
        withBytes(FXAAUniforms(texel: SIMD4(1 / Float(W), 1 / Float(H), 0, 0), params: SIMD4(Float(look.sharpen), 0, 0, 0))) {
            pass(cb, target: dst, fragment: "fs_fxaa", textures: [comp], bytes: [($0, $1)])
        }
    }

    private var white1: MTLTexture?
    private var black1: MTLTexture?

    private func solid(_ value: Float) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 1, height: 1, mipmapped: false)
        d.usage = [.shaderRead]
        d.storageMode = .shared
        guard let t = device?.makeTexture(descriptor: d) else { return nil }
        let h = Float16Bits.bits(value)
        var px: [UInt16] = [h, h, h, Float16Bits.bits(1)]
        t.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &px, bytesPerRow: 8)
        return t
    }

    private func textureWhite(_ cb: MTLCommandBuffer) -> MTLTexture? {
        if white1 == nil { white1 = solid(1) }
        return white1
    }

    private func textureBlack(_ cb: MTLCommandBuffer) -> MTLTexture? {
        if black1 == nil { black1 = solid(0) }
        return black1
    }

    private func blit(_ cb: MTLCommandBuffer, _ src: MTLTexture, _ dst: MTLTexture) {
        if src.pixelFormat == dst.pixelFormat, src.width == dst.width, src.height == dst.height, let b = cb.makeBlitCommandEncoder() {
            b.copy(from: src, to: dst)
            b.endEncoding()
        } else if library != nil {
            pass(cb, target: dst, fragment: "fs_copy", textures: [src])
        }
    }
}

/// IEEE half conversion without relying on `Float16` (unavailable on Intel Macs).
enum Float16Bits {
    static func bits(_ f: Float) -> UInt16 {
        let x = f.bitPattern
        let sign = UInt16((x >> 16) & 0x8000)
        var exp = Int((x >> 23) & 0xff) - 127 + 15
        var mant = x & 0x7fffff
        if exp <= 0 { return sign }
        if exp >= 31 { exp = 31; mant = 0 }
        return sign | UInt16(exp << 10) | UInt16(mant >> 13)
    }
}

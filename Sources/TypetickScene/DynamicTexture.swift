import CoreGraphics
import Foundation
import Metal
import RealityKit

/// A RealityKit texture fed from a CPU bitmap context with cheap partial
/// updates: only the dirty rows/columns are copied into a staging Metal
/// texture, then the GPU blits the whole staging texture into a
/// `LowLevelTexture` and regenerates mipmaps (keeps the paper razor sharp at
/// glancing angles without shimmering).
@MainActor
public final class DynamicTexture {
    public enum Format { case rgba8sRGB, rgba8, r8 }

    public let width: Int
    public let height: Int
    public let format: Format
    public private(set) var resource: TextureResource?
    /// Whether meshes should put v = 0 at the top edge of the image. RealityKit
    /// samples image textures with a bottom-left UV origin; low level textures
    /// are expected to behave the same. If the sheet ever renders upside down
    /// on a particular OS build, `defaults write <bundle id> TypetickFlipPaperV -bool YES`.
    public private(set) var originTop = UserDefaults.standard.bool(forKey: "TypetickFlipPaperV")

    private var lowLevel: LowLevelTexture?
    private var staging: MTLTexture?
    private static let device = MTLCreateSystemDefaultDevice()
    private static let queue = device?.makeCommandQueue()

    public init(width: Int, height: Int, format: Format) {
        self.width = width
        self.height = height
        self.format = format
        setUpLowLevel()
    }

    private var pixelFormat: MTLPixelFormat {
        switch format {
        case .rgba8sRGB: return .rgba8Unorm_srgb
        case .rgba8: return .rgba8Unorm
        case .r8: return .r8Unorm
        }
    }

    private var bytesPerPixel: Int { format == .r8 ? 1 : 4 }

    private var mipLevels: Int { Int(floor(log2(Double(max(width, height))))) + 1 }

    private func setUpLowLevel() {
        guard let device = DynamicTexture.device else { return }
        var desc = LowLevelTexture.Descriptor()
        desc.textureType = .type2D
        desc.pixelFormat = pixelFormat
        desc.width = width
        desc.height = height
        desc.depth = 1
        desc.mipmapLevelCount = mipLevels
        desc.arrayLength = 1
        desc.textureUsage = [.shaderRead, .renderTarget]
        do {
            let llt = try LowLevelTexture(descriptor: desc)
            let res = try TextureResource(from: llt)
            let sd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
            sd.storageMode = device.hasUnifiedMemory ? .shared : .managed
            sd.usage = [.shaderRead]
            staging = device.makeTexture(descriptor: sd)
            lowLevel = llt
            resource = res
        } catch {
            NSLog("Typetick: LowLevelTexture unavailable (\(error)); falling back to image uploads")
            lowLevel = nil
        }
    }

    /// Copies `rect` (pixel coordinates, origin top-left) of a bitmap context
    /// and schedules a GPU update.
    public func upload(from ctx: CGContext, rect: CGRect?) {
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        let r = (rect ?? full).integral.intersection(full)
        guard !r.isEmpty else { return }
        if let staging = staging, let llt = lowLevel, let base = ctx.data, let queue = DynamicTexture.queue {
            let bpr = ctx.bytesPerRow
            let ptr = base.advanced(by: Int(r.minY) * bpr + Int(r.minX) * bytesPerPixel)
            staging.replace(region: MTLRegionMake2D(Int(r.minX), Int(r.minY), Int(r.width), Int(r.height)),
                            mipmapLevel: 0, withBytes: ptr, bytesPerRow: bpr)
            guard let cb = queue.makeCommandBuffer() else { return }
            let target = llt.replace(using: cb)
            if let blit = cb.makeBlitCommandEncoder() {
                blit.copy(from: staging, sourceSlice: 0, sourceLevel: 0, to: target, destinationSlice: 0, destinationLevel: 0,
                          sliceCount: 1, levelCount: 1)
                if mipLevels > 1 { blit.generateMipmaps(for: target) }
                blit.endEncoding()
            }
            cb.commit()
        } else if let image = ctx.makeImage() {
            uploadImage(image)
        }
    }

    private func uploadImage(_ image: CGImage) {
        let semantic: TextureResource.Semantic = format == .rgba8sRGB ? .color : (format == .r8 ? .scalar : .normal)
        let options = TextureResource.CreateOptions(semantic: semantic, mipmapsMode: .allocateAndGenerateAll)
        if let res = resource {
            try? res.replace(withImage: image, options: options)
        } else {
            resource = try? TextureResource.generate(from: image, options: options)
        }
    }
}

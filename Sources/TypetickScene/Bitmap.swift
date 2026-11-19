import CoreGraphics
import Foundation
import simd

/// Minimal CPU bitmap helpers used by the procedural texture generators.
public struct Bitmap {
    public let width: Int
    public let height: Int
    public let channels: Int
    public var data: [UInt8]

    public init(width: Int, height: Int, channels: Int = 4) {
        self.width = width
        self.height = height
        self.channels = channels
        data = [UInt8](repeating: 255, count: width * height * channels)
    }

    @inline(__always)
    public mutating func set(_ x: Int, _ y: Int, _ c: SIMD3<Float>, alpha: Float = 1) {
        let i = (y * width + x) * channels
        data[i] = UInt8(clamping: Int(max(0, min(1, c.x)) * 255 + 0.5))
        if channels >= 3 {
            data[i + 1] = UInt8(clamping: Int(max(0, min(1, c.y)) * 255 + 0.5))
            data[i + 2] = UInt8(clamping: Int(max(0, min(1, c.z)) * 255 + 0.5))
        }
        if channels == 4 { data[i + 3] = UInt8(clamping: Int(max(0, min(1, alpha)) * 255 + 0.5)) }
    }

    @inline(__always)
    public mutating func setGray(_ x: Int, _ y: Int, _ v: Float) {
        let b = UInt8(clamping: Int(max(0, min(1, v)) * 255 + 0.5))
        let i = (y * width + x) * channels
        for k in 0..<min(channels, 3) { data[i + k] = b }
        if channels == 4 { data[i + 3] = 255 }
    }

    public func makeImage() -> CGImage? {
        let space = channels == 1 ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB)!
        let info: CGBitmapInfo = channels == 1 ? CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
            : CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8 * channels,
                       bytesPerRow: width * channels, space: space, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Converts a height field (gray, 0...1) to a tangent-space normal map.
    public static func normalMap(from heights: [Float], width: Int, height: Int, strength: Float, wrap: Bool = true) -> Bitmap {
        var out = Bitmap(width: width, height: height, channels: 4)
        func h(_ x: Int, _ y: Int) -> Float {
            let xx = wrap ? (x + width) % width : max(0, min(width - 1, x))
            let yy = wrap ? (y + height) % height : max(0, min(height - 1, y))
            return heights[yy * width + xx]
        }
        for y in 0..<height {
            for x in 0..<width {
                let dx = (h(x + 1, y) - h(x - 1, y)) * strength
                let dy = (h(x, y + 1) - h(x, y - 1)) * strength
                let n = simd_normalize(SIMD3<Float>(-dx, dy, 1))
                out.set(x, y, n * 0.5 + 0.5)
            }
        }
        return out
    }
}

/// Tileable value noise + fbm.
public struct Noise {
    private var perm: [Int]

    public init(seed: UInt64) {
        var rng = SplitMix(seed: seed)
        var p = Array(0..<256)
        for i in stride(from: 255, to: 0, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            p.swapAt(i, j)
        }
        perm = p + p
    }

    @inline(__always)
    private func hash(_ x: Int, _ y: Int) -> Float {
        Float(perm[(perm[x & 255] + y) & 511]) / 255
    }

    /// Value noise tiling every `period` units.
    public func value(_ x: Float, _ y: Float, period: Int = 256) -> Float {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let xf = x - floor(x), yf = y - floor(y)
        let u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf)
        func w(_ a: Int) -> Int { ((a % period) + period) % period }
        let a = hash(w(xi), w(yi)), b = hash(w(xi + 1), w(yi))
        let c = hash(w(xi), w(yi + 1)), d = hash(w(xi + 1), w(yi + 1))
        return (a + (b - a) * u) + ((c + (d - c) * u) - (a + (b - a) * u)) * v
    }

    public func fbm(_ x: Float, _ y: Float, octaves: Int = 5, period: Int = 8) -> Float {
        var sum: Float = 0, amp: Float = 0.5, f: Float = 1, norm: Float = 0
        for o in 0..<octaves {
            sum += value(x * f, y * f, period: period << o) * amp
            norm += amp
            amp *= 0.5
            f *= 2
        }
        return sum / norm
    }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Float { Float(next() >> 40) / Float(1 << 24) }
}

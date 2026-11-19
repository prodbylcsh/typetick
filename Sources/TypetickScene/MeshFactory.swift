import Foundation
import RealityKit
import simd

/// Runtime generated meshes: the sheet of paper, ribbons and tapes.
@MainActor
public enum MeshFactory {
    /// The sheet wrapped around the platen. Two parts: front (textured, part
    /// index 0) and back (plain, part index 1).
    public static func paper(layout: MachineLayout, pageWidth: Float, pageHeight: Float, feed: Float,
                             originTop: Bool, shake: Float = 0) -> MeshResource? {
        // Page row y (meters from top) sits at path coordinate u = feed - y.
        let columns = 10
        var ys: [Float] = []
        var y: Float = 0
        while y < pageHeight {
            let u = feed - y
            // finer steps where the sheet bends around the platen
            let onPlaten = u < layout.platenRadius * (layout.exitAngle - layout.printAngle) + 0.004 &&
                u > layout.platenRadius * (layout.entryAngle - layout.printAngle) - 0.004
            ys.append(y)
            y += onPlaten ? 0.0012 : 0.006
        }
        ys.append(pageHeight)

        var pos: [SIMD3<Float>] = []
        var nrm: [SIMD3<Float>] = []
        var uv: [SIMD2<Float>] = []
        for py in ys {
            let (p, n) = layout.paperPoint(feed - py)
            for i in 0...columns {
                let fx = Float(i) / Float(columns)
                let x = -pageWidth / 2 + pageWidth * fx
                // a faint ripple when the type bar hits, strongest at the print line
                let dist = abs(feed - py)
                let ripple = shake * exp(-dist * 60) * cos(x * 40)
                pos.append(SIMD3(x, p.x + n.x * ripple, p.y + n.y * ripple))
                nrm.append(SIMD3(0, n.x, n.y))
                let v = py / pageHeight
                uv.append(SIMD2(fx, originTop ? v : 1 - v))
            }
        }
        let rows = ys.count
        var front: [UInt32] = []
        var back: [UInt32] = []
        let stride = UInt32(columns + 1)
        for j in 0..<(rows - 1) {
            for i in 0..<columns {
                let a = UInt32(j) * stride + UInt32(i)
                let b = a + 1
                let c = a + stride + 1
                let d = a + stride
                // Rows run from the top edge (high u) down, so this winding faces outward.
                front += [a, c, b, a, d, c]
                back += [a, b, c, a, c, d]
            }
        }
        var fd = MeshDescriptor(name: "paperFront")
        fd.positions = MeshBuffers.Positions(pos)
        fd.normals = MeshBuffers.Normals(nrm)
        fd.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        fd.primitives = .triangles(front)
        fd.materials = .allFaces(0)
        var bd = MeshDescriptor(name: "paperBack")
        bd.positions = MeshBuffers.Positions(pos)
        bd.normals = MeshBuffers.Normals(nrm.map { -$0 })
        bd.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        bd.primitives = .triangles(back)
        bd.materials = .allFaces(1)
        return try? MeshResource.generate(from: [fd, bd])
    }

    /// A thin double-sided band following `path` (world or local points), `width`
    /// measured along `up`.
    public static func band(path: [SIMD3<Float>], width: Float, up: SIMD3<Float> = SIMD3(0, 1, 0),
                            uvLength: Float = 1) -> MeshResource? {
        guard path.count >= 2 else { return nil }
        var pos: [SIMD3<Float>] = []
        var nrm: [SIMD3<Float>] = []
        var uv: [SIMD2<Float>] = []
        var acc: Float = 0
        for (i, p) in path.enumerated() {
            if i > 0 { acc += simd_length(p - path[i - 1]) }
            let t = simd_normalize(path[min(i + 1, path.count - 1)] - path[max(i - 1, 0)])
            var n = simd_cross(t, up)
            if simd_length(n) < 1e-5 { n = SIMD3(0, 0, 1) }
            n = simd_normalize(n)
            pos.append(p - up * width / 2)
            pos.append(p + up * width / 2)
            nrm.append(n); nrm.append(n)
            uv.append(SIMD2(acc / uvLength, 0)); uv.append(SIMD2(acc / uvLength, 1))
        }
        var idx: [UInt32] = []
        for i in 0..<(path.count - 1) {
            let a = UInt32(i * 2), b = a + 1, c = a + 2, d = a + 3
            idx += [a, c, b, b, c, d]   // one side
            idx += [a, b, c, b, d, c]   // other side
        }
        var desc = MeshDescriptor(name: "band")
        desc.positions = MeshBuffers.Positions(pos)
        desc.normals = MeshBuffers.Normals(nrm)
        desc.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        desc.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [desc])
    }

    /// Path that wraps a spool (circle in XZ at `center`) and leaves tangentially.
    public static func spoolTangent(center: SIMD3<Float>, radius: Float, toward target: SIMD3<Float>, height: Float) -> SIMD3<Float> {
        let d = SIMD2(target.x - center.x, target.z - center.z)
        let len = simd_length(d)
        guard len > radius else { return SIMD3(center.x, height, center.z) }
        let dir = d / len
        let perp = SIMD2(-dir.y, dir.x)
        let a = acos(radius / len)
        let side: Float = center.x < target.x ? 1 : -1
        let p = SIMD2(center.x, center.z) + radius * (dir * cos(a) + perp * sin(a) * side)
        return SIMD3(p.x, height, p.y)
    }
}

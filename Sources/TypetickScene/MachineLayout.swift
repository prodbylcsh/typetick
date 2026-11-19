import Foundation
import simd
import TypetickCore

/// Geometry of the assembled machine in meters (Y up, +Z toward the typist).
/// All numbers come from the variant manifests of the chassis and carriage.
public struct MachineLayout {
    public var carriageAnchor: SIMD3<Float>
    public var platenRadius: Float
    public var platenLength: Float
    public var pitch: Float
    public var lineHeight: Float
    public var printAngle: Float
    public var exitAngle: Float
    public var entryAngle: Float
    public var basketCenter: SIMD3<Float>
    public var basketRadius: Float
    public var basketArc: Float
    public var restTilt: Float
    public var keyboard: JSONValue
    public var anchors: JSONValue
    public var carriageAnchors: JSONValue
    public var shiftTravel: Float
    public var shiftType: MachineSpec.ShiftType
    public var curlRadius: Float = 0.55
    /// Paper floats this far above the platen rubber.
    public var paperGap: Float = 0.00025

    public init(chassis: VariantManifest, carriage: VariantManifest) {
        let ch = chassis.mechanics
        let ca = carriage.mechanics
        carriageAnchor = ch["anchors"]["carriage"].vec3 ?? SIMD3(0, 0.14, -0.07)
        platenRadius = ca["platenRadius"].float(0.0165)
        platenLength = ca["platenLength"].float(0.245)
        pitch = ca["pitch"].float(0.00254)
        lineHeight = ca["lineHeight"].float(0.0042333)
        printAngle = ca["printAngleDegrees"].float(8) * .pi / 180
        exitAngle = ca["paperExitDegrees"].float(30) * .pi / 180
        entryAngle = ca["paperEntryDegrees"].float(-125) * .pi / 180
        basketCenter = ch["basket"]["center"].vec3 ?? SIMD3(0, 0.075, -0.03)
        basketRadius = ch["basket"]["radius"].float(0.07)
        basketArc = ch["basket"]["arcDegrees"].float(150) * .pi / 180
        restTilt = ch["basket"]["restTiltDegrees"].float(26) * .pi / 180
        keyboard = ch["keyboard"]
        anchors = ch["anchors"]
        carriageAnchors = ca["anchors"]
        shiftTravel = ch["shiftTravel"].float(0.0055)
        shiftType = ch["shiftType"].string == "carriage" ? .carriage : .segment
    }

    // MARK: printing point & carriage

    /// Where every typebar lands (world space). The carriage moves, this does not.
    public var printPoint: SIMD3<Float> {
        carriageAnchor + SIMD3(0, platenRadius * sin(printAngle), platenRadius * cos(printAngle))
    }

    /// Carriage X offset that brings `column` of a page of `pageWidth` meters
    /// under the printing point.
    public func carriageX(column: Double, pageWidth: Float) -> Float {
        pageWidth / 2 - Float(column) * pitch - pitch / 2
    }

    public func anchor(_ name: String, fallback: SIMD3<Float> = .zero) -> SIMD3<Float> {
        anchors[name].vec3 ?? fallback
    }

    public func carriageAnchor(_ name: String) -> SIMD3<Float> {
        carriageAnchors[name].vec3 ?? .zero
    }

    // MARK: keyboard

    public func keyPosition(_ key: TypeKey) -> SIMD3<Float> {
        let rowCount = KeyboardLayout.rows[key.row].count
        let pitchX = keyboard["keyPitchX"].float(0.0205)
        let stagger = keyboard["rowStaggerX"].array?[safe: key.row]?.double.map(Float.init) ?? 0
        let x = (Float(key.index) - Float(rowCount - 1) / 2) * pitchX + stagger
        let y = keyboard["frontY"].float(0.05) + Float(key.row) * keyboard["rowRiseY"].float(0.0095)
        let z = keyboard["frontZ"].float(0.15) - Float(key.row) * keyboard["rowPitchZ"].float(0.0215)
        return SIMD3(x, y, z)
    }

    public func functionKeyPosition(_ key: FunctionKey) -> SIMD3<Float> {
        let pitchX = keyboard["keyPitchX"].float(0.0205)
        func rowPos(_ row: Int, _ index: Double) -> SIMD3<Float> {
            let n = KeyboardLayout.rows[row].count
            let stagger = keyboard["rowStaggerX"].array?[safe: row]?.double.map(Float.init) ?? 0
            let x = (Float(index) - Float(n - 1) / 2) * pitchX + stagger
            let y = keyboard["frontY"].float(0.05) + Float(row) * keyboard["rowRiseY"].float(0.0095)
            let z = keyboard["frontZ"].float(0.15) - Float(row) * keyboard["rowPitchZ"].float(0.0215)
            return SIMD3(x, y, z)
        }
        switch key {
        case .shiftLeft: return rowPos(0, -1.3)
        case .shiftRight: return rowPos(0, Double(KeyboardLayout.rows[0].count) + 0.3)
        case .shiftLock: return rowPos(1, -1.2)
        case .tab: return rowPos(2, -1.2)
        case .backspace: return rowPos(3, Double(KeyboardLayout.rows[3].count) + 0.2)
        case .marginRelease: return rowPos(3, -1.2)
        case .space: return SIMD3(0, keyboard["spaceY"].float(0.04), keyboard["spaceZ"].float(0.176))
        }
    }

    // MARK: typebars

    public struct TypebarPose {
        public var pivot: SIMD3<Float>
        public var length: Float
        public var rest: simd_quatf
        public var strike: simd_quatf
    }

    public func typebarPose(slot: Int, count: Int) -> TypebarPose {
        let t = count > 1 ? Float(slot) / Float(count - 1) : 0.5
        let a = -basketArc / 2 + basketArc * t
        let pivot = basketCenter + basketRadius * SIMD3(sin(a), 0, cos(a))
        let p = printPoint
        let toP = p - pivot
        let length = simd_length(toP)
        var horiz = SIMD3<Float>(pivot.x - p.x, 0, pivot.z - p.z)
        if simd_length(horiz) < 1e-5 { horiz = SIMD3(0, 0, 1) }
        horiz = simd_normalize(horiz)
        let restDir = simd_normalize(horiz * cos(restTilt) - SIMD3(0, 1, 0) * sin(restTilt))
        let rest = simd_quatf(from: SIMD3(0, 0, 1), to: restDir)
        let strike = simd_quatf(from: restDir, to: simd_normalize(toP)) * rest
        return TypebarPose(pivot: pivot, length: length, rest: rest, strike: strike)
    }

    // MARK: paper path (carriage local, YZ plane)

    /// Point on the paper path at arc length `u` (meters) from the printing
    /// line; positive `u` runs up toward the top edge already typed.
    public func paperPoint(_ u: Float) -> (position: SIMD2<Float>, normal: SIMD2<Float>) {
        let r = platenRadius + paperGap
        let uExit = r * (exitAngle - printAngle)
        let uEntry = r * (entryAngle - printAngle)
        if u >= uExit {
            let s = u - uExit
            let e = SIMD2(r * sin(exitAngle), r * cos(exitAngle))
            let th = exitAngle + s / curlRadius
            let pos = e + curlRadius * SIMD2(sin(th) - sin(exitAngle), cos(th) - cos(exitAngle))
            let tangent = SIMD2(cos(th), -sin(th))
            return (pos, SIMD2(-tangent.y, tangent.x))
        } else if u >= uEntry {
            let phi = printAngle + u / r
            return (SIMD2(r * sin(phi), r * cos(phi)), SIMD2(sin(phi), cos(phi)))
        } else {
            let s = uEntry - u
            let start = SIMD2(r * sin(entryAngle), r * cos(entryAngle))
            let back = SIMD2(-cos(entryAngle), sin(entryAngle))
            let tangent = -back
            return (start + back * s, SIMD2(-tangent.y, tangent.x))
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

import Foundation

/// Everything the mechanical model needs to know about the assembled machine.
/// Built from the component manifests by the scene layer, but plain data so
/// the core stays testable.
public struct MachineSpec: Sendable, Equatable {
    public enum ShiftType: String, Sendable { case segment, carriage }
    public enum CorrectionMode: String, Sendable { case coverUp, liftOff }
    public enum RecorderMedium: String, Sendable { case tape, drum, loop, cards }

    /// Escapement pitch in meters (pica 2.54 mm, elite 2.117 mm).
    public var pitch: Double = 0.00254
    public var lineHeight: Double = 0.0042333
    public var platenLength: Double = 0.245
    public var bellOffsetColumns: Int = 7
    public var bellStrikes: Int = 1
    public var lineSpacingOptions: [Double] = [1, 1.5, 2]
    public var powerReturn: Bool = false
    /// Carriage return speed, meters per second.
    public var returnSpeed: Double = 0.9
    public var feedBeforeReturn: Bool = true
    public var detentsPerLine: Int = 3
    public var shiftType: ShiftType = .segment
    public var correctionMode: CorrectionMode = .coverUp
    public var correctionCoverage: Double = 1
    public var correctionTint: [Double] = [0, 0, 0]
    public var recorderMedium: RecorderMedium = .tape
    public var recorderCPS: Double = 11
    public var springCapacity: Int = 220
    public var typebarSwing: Double = 0.034
    public var typebarReturn: Double = 0.07
    public var impactForce: Double = 0.75
    public var alignmentJitter: Double = 0.6
    public var keyTravel: Double = 0.009
    public var escapementSnap: Double = 0.012
    public var twoColorRibbon: Bool = false
    public var defaultLeftMargin: Int = 10
    public var defaultRightMargin: Int = 75
    public var defaultTabs: [Int] = [15, 25, 35, 45, 55, 65]

    public init() {}

    public var pitchPoints: Double { Units.points(pitch) }
    public var lineHeightPoints: Double { Units.points(lineHeight) }

    public func columns(forPageWidth width: Double) -> Int { Int(width / pitchPoints) }
}

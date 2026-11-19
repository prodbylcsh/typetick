import Foundation

public enum Curve {
    case linear, easeIn, easeOut, easeInOut
    /// Ease out with an overshoot of the given fraction, then settle.
    case overshoot(Double)
    /// Hits the target and bounces back a little (impacts, carriage stops).
    case bounce(Double)

    func apply(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        switch self {
        case .linear: return t
        case .easeIn: return t * t * t
        case .easeOut: return 1 - pow(1 - t, 3)
        case .easeInOut: return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        case let .overshoot(k):
            let s = 1.70158 * k * 4
            let u = t - 1
            return 1 + (s + 1) * u * u * u + s * u * u
        case let .bounce(k):
            if t < 0.7 { let u = t / 0.7; return u * u }
            let u = (t - 0.7) / 0.3
            return 1 - k * sin(u * .pi) * (1 - u)
        }
    }
}

/// A scalar that animates through a queue of segments. All mechanical motion
/// in the scene is expressed as channels so that the rig can re-apply the
/// current pose each frame.
public final class Channel {
    struct Segment {
        var from: Double?
        var to: Double
        var duration: Double
        var curve: Curve
        var delay: Double
    }

    public private(set) var value: Double
    private var queue: [Segment] = []
    private var current: Segment?
    private var start: Double = 0
    private var elapsed: Double = 0
    /// Damped oscillation added on top (impacts, jiggles).
    private var wobbleAmp: Double = 0
    private var wobbleFreq: Double = 0
    private var wobbleDecay: Double = 0
    private var wobbleTime: Double = 0
    public private(set) var wobble: Double = 0

    public init(_ value: Double = 0) { self.value = value }

    public var isAnimating: Bool { current != nil || !queue.isEmpty || abs(wobbleAmp) > 1e-6 }
    public var target: Double { queue.last?.to ?? current?.to ?? value }
    public var output: Double { value + wobble }

    /// Replace any running motion.
    @discardableResult
    public func animate(to: Double, duration: Double, curve: Curve = .easeInOut, delay: Double = 0) -> Channel {
        queue = [Segment(from: nil, to: to, duration: max(duration, 0.0001), curve: curve, delay: delay)]
        current = nil
        return self
    }

    /// Append after the queued motion.
    @discardableResult
    public func then(to: Double, duration: Double, curve: Curve = .easeInOut, delay: Double = 0) -> Channel {
        queue.append(Segment(from: nil, to: to, duration: max(duration, 0.0001), curve: curve, delay: delay))
        return self
    }

    public func set(_ v: Double) {
        value = v
        queue.removeAll()
        current = nil
    }

    public func kick(amplitude: Double, frequency: Double, decay: Double) {
        wobbleAmp = amplitude
        wobbleFreq = frequency
        wobbleDecay = decay
        wobbleTime = 0
    }

    /// Returns true when the output changed.
    @discardableResult
    public func step(_ dt: Double) -> Bool {
        var changed = false
        if abs(wobbleAmp) > 1e-7 {
            wobbleTime += dt
            let env = exp(-wobbleTime * wobbleDecay)
            wobble = wobbleAmp * env * sin(wobbleTime * wobbleFreq * 2 * .pi)
            if env < 0.002 { wobbleAmp = 0; wobble = 0 }
            changed = true
        }
        var remaining = dt
        while remaining > 0 {
            if current == nil {
                guard !queue.isEmpty else { break }
                current = queue.removeFirst()
                start = value
                elapsed = -(current!.delay)
            }
            guard let seg = current else { break }
            elapsed += remaining
            remaining = 0
            if elapsed < 0 { break }
            let from = seg.from ?? start
            let t = elapsed / seg.duration
            value = from + (seg.to - from) * seg.curve.apply(t)
            changed = true
            if t >= 1 {
                value = seg.to
                remaining = elapsed - seg.duration
                current = nil
                if queue.isEmpty { break }
            }
        }
        return changed
    }
}

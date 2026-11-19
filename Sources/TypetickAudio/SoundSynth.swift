import Foundation

/// Per component voice parameters (from the variant manifests).
public struct SoundProfile: Sendable, Equatable {
    public var pitch: Double = 1
    public var body: Double = 0.5
    public var brightness: Double = 0.6
    public var decay: Double = 1
    public var ring: Double = 0.3
    public init() {}
    public init(pitch: Double, body: Double, brightness: Double, decay: Double, ring: Double) {
        self.pitch = pitch; self.body = body; self.brightness = brightness; self.decay = decay; self.ring = ring
    }
}

/// Procedural mechanical sound synthesis: modal resonators + shaped noise.
/// Every sound is generated once per configuration in a few random takes.
public enum SoundSynth {
    public static let sampleRate: Double = 48_000

    public struct Mode { public var freq: Double; public var decay: Double; public var amp: Double
        public init(_ f: Double, _ d: Double, _ a: Double) { freq = f; decay = d; amp = a } }

    struct RNG {
        var s: UInt64
        mutating func next() -> Double {
            s &+= 0x9E37_79B9_7F4A_7C15
            var z = s
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
        }
        mutating func bi() -> Double { next() * 2 - 1 }
    }

    /// A struck object: modes ring out, a noise transient gives the "click".
    public static func impact(modes: [Mode], noise: Double, noiseDecay: Double, lowpass: Double, highpass: Double = 60,
                              duration: Double, attack: Double = 0.0004, seed: UInt64) -> [Float] {
        let n = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: n)
        var rng = RNG(s: seed)
        var phases = modes.map { _ in rng.next() * 2 * .pi }
        let detune = modes.map { _ in 1 + rng.bi() * 0.012 }
        var lp = 0.0, hp = 0.0, hpPrev = 0.0
        let aLP = 1 - exp(-2 * .pi * lowpass / sampleRate)
        let aHP = exp(-2 * .pi * highpass / sampleRate)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let env = t < attack ? t / attack : 1
            var s = 0.0
            for (k, m) in modes.enumerated() {
                phases[k] += 2 * .pi * m.freq * detune[k] / sampleRate
                s += sin(phases[k]) * m.amp * exp(-t / max(m.decay, 0.0005))
            }
            let raw = rng.bi() * noise * exp(-t / max(noiseDecay, 0.0002))
            lp += (raw - lp) * aLP
            let h = aHP * (hp + lp - hpPrev)
            hpPrev = lp
            hp = h
            out[i] = Float((s + h) * env)
        }
        return normalize(fadeOut(out), peak: 0.9)
    }

    public static func fadeOut(_ x: [Float], ms: Double = 4) -> [Float] {
        var y = x
        let n = min(y.count, Int(ms / 1000 * sampleRate))
        for i in 0..<n { y[y.count - 1 - i] *= Float(i) / Float(max(n, 1)) }
        return y
    }

    public static func normalize(_ x: [Float], peak: Float) -> [Float] {
        let m = x.map(abs).max() ?? 1
        guard m > 0 else { return x }
        return x.map { $0 / m * peak }
    }

    public static func mix(_ a: [Float], _ b: [Float], at offset: Double, gain: Float = 1) -> [Float] {
        let o = Int(offset * sampleRate)
        var out = a
        if out.count < o + b.count { out += [Float](repeating: 0, count: o + b.count - out.count) }
        for i in 0..<b.count { out[o + i] += b[i] * gain }
        return out
    }

    // MARK: building blocks

    /// Small metal/plastic click (pawls, detents, keys).
    public static func click(_ p: SoundProfile, base: Double, seed: UInt64, length: Double = 0.05) -> [Float] {
        let f = base * p.pitch
        let modes = [Mode(f, 0.006 * p.decay, 0.6), Mode(f * 2.76, 0.004 * p.decay, 0.35 * p.brightness),
                     Mode(f * 5.4, 0.003 * p.decay * (1 + p.ring * 3), 0.25 * p.ring), Mode(f * 0.5, 0.01 * p.decay, 0.4 * p.body)]
        return impact(modes: modes, noise: 0.9 * p.brightness + 0.2, noiseDecay: 0.002, lowpass: 3000 + 9000 * p.brightness,
                      duration: length, seed: seed)
    }

    /// Typebar slug hitting paper on the platen.
    public static func strike(typebar t: SoundProfile, frame: SoundProfile, platenHardness: Double, paperHardness: Double,
                              frameResonance: Double, seed: UInt64) -> [Float] {
        let hard = (platenHardness + paperHardness) / 2
        let f = 180 * t.pitch * (0.85 + 0.3 * hard)
        var modes = [Mode(f, 0.018 * t.decay, 1.0 * t.body + 0.3),
                     Mode(f * 2.3, 0.010 * t.decay, 0.6),
                     Mode(f * 4.1, 0.006, 0.35 * t.brightness),
                     Mode(1450 * t.pitch, 0.004 + 0.02 * t.ring, 0.3 * t.ring)]
        // the frame answers each blow
        let fr = 320 * frame.pitch
        modes += [Mode(fr, 0.03 * frame.decay * (0.4 + frameResonance), 0.35 * frame.body),
                  Mode(fr * 2.7, 0.02 * frame.decay * (0.4 + frameResonance), 0.25 * frame.ring * frameResonance),
                  Mode(fr * 6.3, 0.012 * frameResonance, 0.15 * frame.ring * frameResonance)]
        let thwack = impact(modes: modes, noise: 1.2 + hard, noiseDecay: 0.0025 + 0.002 * (1 - hard),
                            lowpass: 2500 + 7000 * hard * t.brightness, duration: 0.18 + 0.12 * frameResonance, seed: seed)
        return thwack
    }

    /// Carriage sliding: rolling bearings, rack teeth and air.
    public static func slide(_ p: SoundProfile, duration: Double, teeth: Int, power: Bool, seed: UInt64) -> [Float] {
        let n = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: n)
        var rng = RNG(s: seed)
        var lp = 0.0
        let aLP = 1 - exp(-2 * .pi * (600 + 1600 * p.brightness) / sampleRate)
        var motor = 0.0
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let env = min(1, t / 0.02) * min(1, (duration - t) / 0.03)
            lp += (rng.bi() - lp) * aLP
            var s = lp * 0.5 * env
            if power {
                motor += 2 * .pi * (95 + 40 * min(1, t / 0.1)) / sampleRate
                s += sin(motor) * 0.25 * env + sin(motor * 3.01) * 0.08 * env
            }
            out[i] = Float(s)
        }
        if teeth > 0 && !power {
            let tick = click(p, base: 2200, seed: seed &+ 7, length: 0.012).map { $0 * 0.25 }
            for k in 0..<teeth {
                let at = duration * Double(k) / Double(teeth)
                out = mix(out, tick, at: at)
            }
        }
        return normalize(fadeOut(out), peak: 0.6)
    }

    /// Ratchet: a pawl over teeth (platen detents, spring winding).
    public static func ratchet(_ p: SoundProfile, clicks: Int, duration: Double, seed: UInt64) -> [Float] {
        var out = [Float](repeating: 0, count: Int((duration + 0.05) * sampleRate))
        let c = max(1, clicks)
        for k in 0..<c {
            let at = duration * Double(k) / Double(c)
            out = mix(out, click(p, base: 1400, seed: seed &+ UInt64(k), length: 0.03), at: at, gain: k == c - 1 ? 1 : 0.7)
        }
        return normalize(out, peak: 0.7)
    }

    /// Bell from explicit partials [freq, decay, amp].
    public static func bell(partials: [[Double]], dispersion: Double, seed: UInt64) -> [Float] {
        let modes = partials.map { Mode($0[0], $0.count > 1 ? $0[1] / 3 : 0.5, $0.count > 2 ? $0[2] : 0.5) }
        let longest = (modes.map(\.decay).max() ?? 0.5) * 5
        var out = impact(modes: modes, noise: 0.25, noiseDecay: 0.001, lowpass: 8000, highpass: 200, duration: min(4.5, longest + 0.1), seed: seed)
        if dispersion > 0 {
            // coil gongs smear high partials in time: add a chirp shimmer
            let n = out.count
            var ph = 0.0
            for i in 0..<n {
                let t = Double(i) / sampleRate
                ph += 2 * .pi * (1200 + 2200 * exp(-t * 6)) / sampleRate
                out[i] += Float(sin(ph) * 0.15 * dispersion * exp(-t * 2.5))
            }
            out = normalize(out, peak: 0.9)
        }
        return out
    }

    /// Paper: rustle when inserting or pulling a sheet.
    public static func rustle(duration: Double, softness: Double, seed: UInt64) -> [Float] {
        let n = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: n)
        var rng = RNG(s: seed)
        var bp1 = 0.0, bp2 = 0.0
        var grain = 0.0
        for i in 0..<n {
            let t = Double(i) / sampleRate
            if rng.next() < 0.002 { grain = 0.4 + rng.next() * 0.6 }
            grain *= 0.9995
            let env = sin(min(1, t / duration) * .pi)
            let w = rng.bi()
            bp1 += (w - bp1) * (0.25 - 0.15 * softness)
            bp2 += (bp1 - bp2) * 0.2
            out[i] = Float((bp1 - bp2) * env * (0.3 + grain))
        }
        return normalize(fadeOut(out), peak: 0.5)
    }

    /// Electric motor whir (power return, recorder rewinding).
    public static func motor(duration: Double, pitch: Double, seed: UInt64) -> [Float] {
        let n = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: n)
        var rng = RNG(s: seed)
        var ph = 0.0
        var lp = 0.0
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let env = min(1, t / 0.05) * min(1, (duration - t) / 0.08)
            ph += 2 * .pi * (140 * pitch + 60 * sin(t * 3)) / sampleRate
            lp += (rng.bi() - lp) * 0.05
            out[i] = Float((sin(ph) * 0.4 + sin(ph * 2) * 0.2 + sin(ph * 5.03) * 0.08 + lp * 0.4) * env)
        }
        return normalize(fadeOut(out), peak: 0.45)
    }
}

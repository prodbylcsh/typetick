import AVFoundation
import Foundation
import TypetickCore

/// Everything the director needs to voice a configured machine.
public struct MachineVoice: Sendable, Equatable {
    public var profiles: [ComponentKind: SoundProfile] = [:]
    public var bellPartials: [[Double]] = [[2380, 1.4, 1.0], [5710, 0.7, 0.45]]
    public var bellDispersion: Double = 0
    public var frameResonance: Double = 0.5
    public var platenHardness: Double = 0.7
    public var paperHardness: Double = 0.55
    public var powerReturn = false
    public var musicBoxRecorder = false
    public init() {}

    public func profile(_ k: ComponentKind) -> SoundProfile { profiles[k] ?? SoundProfile() }
}

/// Plays procedurally generated takes through a small pool of voices with
/// stereo placement (the carriage position pans the platen sounds).
public final class SoundEngine {
    public enum Sound: Hashable {
        case keyDown, keyUp, spaceBar, strike, escapement, backspace, carriageStop, ratchet, lever, leverRelease
        case bell, shift, bail, release, insert, eject, ribbon, correction, punch, read, seek, wind, motor, jam, marginSet
        case slide(Int)          // duration in 50 ms buckets
        case ratchetN(Int)       // number of clicks
    }

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private let reverb = AVAudioUnitReverb()
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private let format = AVAudioFormat(standardFormatWithSampleRate: SoundSynth.sampleRate, channels: 1)!
    private var takes: [Sound: [AVAudioPCMBuffer]] = [:]
    private var takeIndex: [Sound: Int] = [:]
    private let queue = DispatchQueue(label: "typetick.audio")
    private let lock = NSLock()
    public private(set) var voice = MachineVoice()
    public var volume: Float = 0.8 { didSet { engine.mainMixerNode.outputVolume = volume } }
    public var enabled = true

    public init() {
        engine.attach(mixer)
        engine.attach(reverb)
        reverb.loadFactoryPreset(.smallRoom)
        reverb.wetDryMix = 10
        engine.connect(mixer, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)
        for _ in 0..<40 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: mixer, format: format)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = volume
        engine.prepare()
        do { try engine.start() } catch { NSLog("Typetick audio: \(error)") }
    }

    public func setRoom(wet: Float) { reverb.wetDryMix = wet }

    public func configure(_ v: MachineVoice) {
        guard v != voice || takes.isEmpty else { return }
        voice = v
        lock.lock()
        takes = [:]
        lock.unlock()
        queue.async { [weak self] in self?.prebuild() }
    }

    private func prebuild() {
        for s: Sound in [.keyDown, .keyUp, .spaceBar, .strike, .escapement, .backspace, .carriageStop, .lever, .leverRelease,
                         .bell, .shift, .bail, .release, .ribbon, .correction, .punch, .read, .jam, .marginSet] {
            _ = buffers(for: s)
        }
    }

    private func buffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        b.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            b.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        return b
    }

    private func buffers(for sound: Sound) -> [AVAudioPCMBuffer] {
        lock.lock()
        let cached = takes[sound]
        lock.unlock()
        if let t = cached { return t }
        let count: Int
        switch sound {
        case .strike, .keyDown, .keyUp, .escapement: count = 6
        case .slide, .ratchetN, .bell, .insert, .eject, .seek, .wind, .motor: count = 1
        default: count = 3
        }
        var out: [AVAudioPCMBuffer] = []
        for i in 0..<count {
            if let b = buffer(synthesize(sound, seed: UInt64(i + 1) &* 0x9E37)) { out.append(b) }
        }
        lock.lock()
        takes[sound] = out
        lock.unlock()
        return out
    }

    private func synthesize(_ sound: Sound, seed: UInt64) -> [Float] {
        let v = voice
        let keys = v.profile(.keys), bars = v.profile(.typebars), car = v.profile(.carriage), frame = v.profile(.chassis)
        switch sound {
        case .keyDown:
            return SoundSynth.click(keys, base: 900, seed: seed, length: 0.06).map { $0 * 0.45 }
        case .keyUp:
            return SoundSynth.click(keys, base: 1300, seed: seed &+ 3, length: 0.04).map { $0 * 0.25 }
        case .spaceBar:
            var s = SoundSynth.click(keys, base: 420, seed: seed, length: 0.09)
            s = SoundSynth.mix(s, SoundSynth.click(car, base: 2600, seed: seed &+ 1, length: 0.03), at: 0.03, gain: 0.6)
            return s.map { $0 * 0.6 }
        case .strike:
            return SoundSynth.strike(typebar: bars, frame: frame, platenHardness: v.platenHardness, paperHardness: v.paperHardness,
                                     frameResonance: v.frameResonance, seed: seed)
        case .escapement:
            return SoundSynth.click(car, base: 2600, seed: seed, length: 0.025).map { $0 * 0.35 }
        case .backspace:
            var s = SoundSynth.click(keys, base: 700, seed: seed, length: 0.05)
            s = SoundSynth.mix(s, SoundSynth.click(car, base: 1900, seed: seed &+ 2, length: 0.04), at: 0.02)
            return s.map { $0 * 0.6 }
        case .carriageStop:
            let modes = [SoundSynth.Mode(95 * car.pitch, 0.06, 1), SoundSynth.Mode(260 * frame.pitch, 0.05 * frame.decay, 0.5),
                         SoundSynth.Mode(1100 * frame.pitch, 0.03 * (0.3 + v.frameResonance), 0.3 * frame.ring)]
            return SoundSynth.impact(modes: modes, noise: 0.8, noiseDecay: 0.004, lowpass: 3000, duration: 0.3, seed: seed)
        case .ratchet:
            return SoundSynth.ratchet(v.profile(.knobs), clicks: 1, duration: 0.01, seed: seed)
        case let .ratchetN(n):
            return SoundSynth.ratchet(v.profile(.knobs), clicks: n, duration: min(1.2, 0.035 * Double(n)), seed: seed).map { $0 * 0.6 }
        case .lever:
            let l = v.profile(.returnLever)
            var s = SoundSynth.click(l, base: 600, seed: seed, length: 0.08)
            s = SoundSynth.mix(s, SoundSynth.ratchet(v.profile(.knobs), clicks: 2, duration: 0.05, seed: seed &+ 9), at: 0.02, gain: 0.7)
            return s
        case .leverRelease:
            return SoundSynth.click(v.profile(.returnLever), base: 900, seed: seed, length: 0.06).map { $0 * 0.4 }
        case .bell:
            return SoundSynth.bell(partials: v.bellPartials, dispersion: v.bellDispersion, seed: seed).map { $0 * 0.7 }
        case .shift:
            let modes = [SoundSynth.Mode(140 * frame.pitch, 0.04, 1), SoundSynth.Mode(520 * frame.pitch, 0.03, 0.4)]
            return SoundSynth.impact(modes: modes, noise: 0.6, noiseDecay: 0.003, lowpass: 2500, duration: 0.16, seed: seed).map { $0 * 0.55 }
        case .bail:
            let b = v.profile(.paperBail)
            let modes = [SoundSynth.Mode(1800 * b.pitch, 0.08 * b.decay * (0.3 + b.ring), 0.8), SoundSynth.Mode(420 * b.pitch, 0.03, 0.6)]
            return SoundSynth.impact(modes: modes, noise: 0.5, noiseDecay: 0.002, lowpass: 6000, duration: 0.3, seed: seed).map { $0 * 0.5 }
        case .release:
            return SoundSynth.click(v.profile(.paperBail), base: 500, seed: seed, length: 0.1).map { $0 * 0.5 }
        case .insert:
            return SoundSynth.rustle(duration: 0.9, softness: 1 - v.paperHardness, seed: seed)
        case .eject:
            return SoundSynth.rustle(duration: 0.6, softness: 1 - v.paperHardness, seed: seed &+ 5)
        case .ribbon:
            return SoundSynth.click(v.profile(.ribbon), base: 3200, seed: seed, length: 0.015).map { $0 * 0.12 }
        case .correction:
            let c = v.profile(.correction)
            var s = SoundSynth.click(c, base: 1100, seed: seed, length: 0.05)
            s = SoundSynth.mix(s, SoundSynth.rustle(duration: 0.08, softness: 0.5, seed: seed), at: 0.01, gain: 0.5)
            return s.map { $0 * 0.5 }
        case .punch:
            let r = v.profile(.recorder)
            if v.musicBoxRecorder {
                let f = [523.25, 587.33, 659.25, 783.99, 880.0][Int(seed % 5)]
                return SoundSynth.impact(modes: [SoundSynth.Mode(f, 0.6, 1), SoundSynth.Mode(f * 4.1, 0.1, 0.2)], noise: 0.2,
                                         noiseDecay: 0.001, lowpass: 8000, duration: 0.9, seed: seed).map { $0 * 0.25 }
            }
            return SoundSynth.click(r, base: 2400, seed: seed, length: 0.03).map { $0 * 0.22 }
        case .read:
            return SoundSynth.click(v.profile(.recorder), base: 3400, seed: seed, length: 0.02).map { $0 * 0.15 }
        case .seek:
            return SoundSynth.motor(duration: 0.4, pitch: 1.6, seed: seed).map { $0 * 0.4 }
        case .wind:
            return SoundSynth.ratchet(v.profile(.recorder), clicks: 14, duration: 0.7, seed: seed).map { $0 * 0.5 }
        case .motor:
            return SoundSynth.motor(duration: 0.4, pitch: 1, seed: seed)
        case .jam:
            let modes = [SoundSynth.Mode(110, 0.05, 1), SoundSynth.Mode(330, 0.03, 0.5)]
            return SoundSynth.impact(modes: modes, noise: 0.8, noiseDecay: 0.005, lowpass: 1800, duration: 0.15, seed: seed).map { $0 * 0.6 }
        case .marginSet:
            return SoundSynth.click(v.profile(.marginRack), base: 1600, seed: seed, length: 0.04).map { $0 * 0.4 }
        case let .slide(buckets):
            let d = Double(buckets) * 0.05
            return SoundSynth.slide(car, duration: max(0.06, d), teeth: v.powerReturn ? 0 : Int(d * 40), power: v.powerReturn, seed: seed)
        }
    }

    /// pan: -1 left ... 1 right
    public func play(_ sound: Sound, gain: Float = 1, pan: Float = 0, rate: Float = 1) {
        guard enabled, engine.isRunning else { return }
        let takes = buffers(for: sound)
        guard !takes.isEmpty else { return }
        let i = (takeIndex[sound] ?? 0) % takes.count
        takeIndex[sound] = i + 1
        let player = players[next]
        next = (next + 1) % players.count
        player.stop()
        player.volume = gain
        player.pan = max(-1, min(1, pan))
        player.scheduleBuffer(takes[i], at: nil, options: [], completionHandler: nil)
        player.play()
    }
}

/// Maps machine events to sounds.
public final class SoundDirector {
    public let engine: SoundEngine
    /// Current carriage pan (-1...1), set by the app from the column.
    public var carriagePan: Float = 0

    public init(engine: SoundEngine = SoundEngine()) { self.engine = engine }

    public func keyDown(isSpace: Bool) { engine.play(isSpace ? .spaceBar : .keyDown, gain: 0.9) }
    public func keyUp() { engine.play(.keyUp, gain: 0.7) }

    public func handle(_ e: MachineEvent) {
        switch e {
        case .typebar: break
        case let .strike(s):
            if s.kind != .ink { engine.play(.correction, gain: 0.8, pan: carriagePan * 0.3) }
        case let .platenImpact(force):
            engine.play(.strike, gain: Float(0.55 + 0.45 * force), pan: carriagePan * 0.15)
        case .escapement: engine.play(.escapement, gain: 0.8, pan: carriagePan)
        case let .carriageMove(from, to, duration, kind):
            switch kind {
            case .backspace: engine.play(.backspace, pan: carriagePan)
            case .space: engine.play(.escapement, pan: carriagePan)
            default:
                if abs(to - from) > 1 { engine.play(.slide(max(1, Int(duration / 0.05))), gain: 0.8, pan: carriagePan) }
            }
        case let .carriageStop(force): engine.play(.carriageStop, gain: Float(0.3 + 0.7 * force), pan: carriagePan)
        case let .platenRoll(_, _, clicks, _):
            engine.play(clicks > 1 ? .ratchetN(min(clicks, 40)) : .ratchet, gain: 0.8)
        case let .returnLever(phase): engine.play(phase == .push ? .lever : .leverRelease, pan: -0.6)
        case .bell: engine.play(.bell, gain: 0.8, pan: -0.7)
        case .marginLock: engine.play(.jam)
        case .shift: engine.play(.shift)
        case .ribbonAdvance: engine.play(.ribbon, gain: 0.5)
        case let .correctionLift(up): if up { engine.play(.release, gain: 0.3) }
        case .bail: engine.play(.bail, gain: 0.8)
        case .releaseLever: engine.play(.release, gain: 0.7, pan: 0.5)
        case .paperIn: engine.play(.insert)
        case .paperOut: engine.play(.eject)
        case .marginSet, .tabsChanged: engine.play(.marginSet)
        case .tapePunch, .clipPunch: engine.play(.punch, gain: 0.8, pan: 0.9)
        case .tapeRead: engine.play(.read, gain: 0.8, pan: 0.9)
        case .tapeSeek: engine.play(.seek, gain: 0.7, pan: 0.9)
        case .springWind: engine.play(.wind, pan: 0.9)
        case .motorRun: engine.play(.motor, gain: 0.7)
        case .vibratorLift, .paperEnd, .springLevel: break
        }
    }
}

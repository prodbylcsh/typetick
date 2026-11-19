import AppKit
import Combine
import Foundation
import RealityKit
import simd
import TypetickCore

/// The assembled 3D typewriter. Owns every moving part as a `Channel`,
/// plays `MachineEvent`s on a timeline and paints the sheet.
@MainActor
public final class MachineRig {
    public let root = Entity()
    public private(set) var layout: MachineLayout
    public private(set) var spec: MachineSpec
    public private(set) var variants: [ComponentKind: VariantManifest]
    public var onEvent: ((MachineEvent) -> Void)?

    // structure
    private var carriage = Entity()        // moves in X
    private var carriageLift = Entity()    // moves in Y for carriage shift
    private var basket = Entity()          // moves in Y for segment shift
    private var platen: Entity?
    private var knobs: [Entity] = []
    private var returnLever: Entity?
    private var bail: Entity?
    private var releaseLever: Entity?
    private var keyEntities: [String: Entity] = [:]
    private var keyBase: [String: Transform] = [:]
    private var typebars: [Entity] = []
    private var typebarPoses: [MachineLayout.TypebarPose] = []
    private var vibrator: Entity?
    private var vibratorBase = Transform()
    private var lifter: Entity?
    private var lifterBase = Transform()
    private var spools: [Entity] = []
    private var corrSpools: [Entity] = []
    private var hammer: Entity?
    private var hammerBase = Transform()
    private var marginStops: [Entity] = []
    private var marginRack: Entity?
    private var tabTemplate: Entity?
    private var tabEntities: [Entity] = []
    private var ribbonStrips: [ModelEntity] = []
    private var tapeStrip: ModelEntity?
    private var paperEntity = ModelEntity()
    private var selectionEntity = ModelEntity()
    private var selectionRects: [CGRect] = []
    // recorder
    private var recorder = Entity()
    private var recorderParts: [String: Entity] = [:]
    private var recorderBase: [String: Transform] = [:]
    private var medium: ModelEntity?
    private var mediumTexture: TextureResource?

    // motion
    private var carriageX = Channel()
    private var shift = Channel()
    private var feed = Channel(-200)      // points
    private var paperShake = Channel()
    private var keyChannels: [String: Channel] = [:]
    private var typebarChannels: [Channel] = []
    private var vib = Channel()
    private var corr = Channel()
    private var lever = Channel()
    private var bailCh = Channel()
    private var releaseCh = Channel()
    private var hammerCh = Channel()
    private var spoolAngle = Channel()
    private var punchCh = Channel()
    private var readerCh = Channel()
    private var reelAngle = Channel()
    private var gauge = Channel(0.6)
    private var barrel = Channel()
    private var ribbonUsed: Double = 0.35
    private var tapeUsed: Double = 0.2

    // paper
    private var paperRenderer: PaperRenderer?
    private var colorTex: DynamicTexture?
    private var roughTex: DynamicTexture?
    private var metalTex: DynamicTexture?
    private var normalTex: DynamicTexture?
    private var paperStyle = PaperStyle()
    private var pageSizeMeters = SIMD2<Float>(0.2159, 0.2794)
    private var paperVisible = false
    private var paperDirty = false
    private var meshDirty = true
    private var dpi: CGFloat = 300

    // timeline
    private var clock: Double = 0
    private var pending: [(at: Double, event: MachineEvent)] = []
    private var journal: [UInt8] = []
    private var clip: [UInt8] = []
    private var readHead = 0
    private var inkColor = RGB(0.05, 0.05, 0.06)
    private var secondInk = RGB(0.6, 0.1, 0.1)
    private var physicallyHeld: Set<String> = []

    public init(variants: [ComponentKind: VariantManifest], spec: MachineSpec, library: ComponentLibrary = .shared) {
        self.variants = variants
        self.spec = spec
        layout = MachineLayout(chassis: variants[.chassis]!, carriage: variants[.carriage]!)
        root.name = "Typewriter"
        WoundBase.registerComponent()
        build(library: library)
    }

    // MARK: - assembly

    private func load(_ kind: ComponentKind, library: ComponentLibrary) -> (Entity, VariantManifest)? {
        guard let v = variants[kind], let url = library.modelURL(kind, v) else { return nil }
        do {
            let e = try Entity.load(contentsOf: url)
            Materials.apply(to: e, palette: v.palette)
            return (e, v)
        } catch {
            NSLog("Typetick: failed to load \(kind.rawValue)/\(v.id): \(error)")
            return nil
        }
    }

    /// Detaches a named part (top level prim) from a loaded model.
    private func part(_ name: String, in model: Entity) -> Entity? {
        guard let p = model.findEntity(named: name) else { return nil }
        let t = p.transform
        p.removeFromParent()
        p.transform = t
        return p
    }

    private func build(library: ComponentLibrary) {
        root.children.removeAll()
        let L = layout

        // chassis
        if case let (m, v)? = load(.chassis, library: library) {
            for name in v.parts {
                if name == "Segment", let seg = part(name, in: m) { basket.addChild(seg) } else if let p = part(name, in: m) { root.addChild(p) }
            }
        }
        root.addChild(basket)

        // carriage + paper
        carriage.position = L.carriageAnchor
        root.addChild(carriage)
        carriage.addChild(carriageLift)
        if case let (m, v)? = load(.carriage, library: library) {
            for name in v.parts {
                if let p = part(name, in: m) {
                    carriageLift.addChild(p)
                    if name == "pivot_Platen" { platen = p }
                }
            }
        }
        paperEntity.name = "Paper"
        carriageLift.addChild(paperEntity)
        paperEntity.isEnabled = false
        selectionEntity.name = "Selection"
        carriageLift.addChild(selectionEntity)

        // knobs
        if case let (m, _)? = load(.knobs, library: library), let knob = part("Knob", in: m) {
            let right = knob
            right.position = L.carriageAnchor("knobRight")
            let left = knob.clone(recursive: true)
            left.position = L.carriageAnchor("knobLeft")
            left.orientation = simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))
            carriageLift.addChild(right)
            carriageLift.addChild(left)
            knobs = [left, right]
        }

        // return lever
        if case let (m, v)? = load(.returnLever, library: library) {
            let holder = Entity()
            holder.position = L.carriageAnchor("returnLever")
            carriageLift.addChild(holder)
            for name in v.parts { if let p = part(name, in: m) { holder.addChild(p); if name == "pivot_ReturnLever" { returnLever = p } } }
        }

        // bail + release lever
        if case let (m, v)? = load(.paperBail, library: library) {
            let width = Float(v.mechanics["nominalWidth"].double(0.24))
            if let b = part("pivot_Bail", in: m) {
                let holder = Entity()
                holder.scale = SIMD3(L.platenLength / width, 1, 1)
                // keep the rollers on the paper for any platen radius
                holder.position = SIMD3(0, 0, L.platenRadius - 0.0165)
                holder.addChild(b)
                carriageLift.addChild(holder)
                bail = b
            }
            if let r = part("pivot_ReleaseLever", in: m) {
                let holder = Entity()
                holder.position = L.carriageAnchor("releaseLever")
                holder.addChild(r)
                carriageLift.addChild(holder)
                releaseLever = r
            }
        }

        // margin rack
        if case let (m, v)? = load(.marginRack, library: library) {
            let width = Float(v.mechanics["nominalWidth"].double(0.24))
            let holder = Entity()
            holder.position = L.carriageAnchor("marginRack")
            carriageLift.addChild(holder)
            marginRack = holder
            if let rack = part("Rack", in: m) { rack.scale = SIMD3(L.platenLength / width, 1, 1); holder.addChild(rack) }
            if let stop = part("MarginStop", in: m) {
                let other = stop.clone(recursive: true)
                holder.addChild(stop); holder.addChild(other)
                marginStops = [stop, other]
            }
            tabTemplate = part("TabStop", in: m)
        }

        // keys
        if case let (m, v)? = load(.keys, library: library), let key = part("Key", in: m) {
            let tilt = Float(v.mechanics["tilt"].double(5)) * .pi / 180
            let legendStyle = v.mechanics["legend"].string ?? "printed"
            let topColor = v.palette["keyTop"].map { RGB($0[0], $0[1], $0[2]) } ?? RGB(0.05, 0.05, 0.05)
            let ink: RGB = topColor.luminance > 0.5 ? RGB(0.08, 0.08, 0.08) : RGB(0.95, 0.94, 0.9)
            let keyRoot = Entity()
            root.addChild(keyRoot)
            func place(_ id: String, _ pos: SIMD3<Float>, legend: String, sub: String?) {
                let k = key.clone(recursive: true)
                k.position = pos
                k.orientation = simd_quatf(angle: -tilt, axis: SIMD3(1, 0, 0))
                if let top = findRole("keyTop", in: k), let img = ProceduralTextures.keyLegend(legend, sub: sub, ink: ink, ground: topColor, style: legendStyle),
                   let tex = try? TextureResource.generate(from: img, options: .init(semantic: .color)) {
                    var mat = Materials.material(role: "keyTop", palette: v.palette)
                    mat.baseColor = .init(tint: .white, texture: .init(tex))
                    if var model = top.components[ModelComponent.self] {
                        model.materials = [Materials.realistic(mat, role: "keyTop")]
                        top.components.set(model)
                    }
                }
                keyRoot.addChild(k)
                keyEntities[id] = k
                keyBase[id] = k.transform
                keyChannels[id] = Channel()
            }
            for tk in KeyboardLayout.keys {
                let isLetter = tk.lower != tk.upper.lowercased() || tk.lower.rangeOfCharacter(from: .letters) == nil
                place(tk.id, L.keyPosition(tk), legend: isLetter ? tk.lower : tk.upper, sub: isLetter ? tk.upper : nil)
            }
            for fk in FunctionKey.allCases where fk != .space {
                place(fk.rawValue, L.functionKeyPosition(fk), legend: fk.legend, sub: nil)
            }
            if let space = part("SpaceBar", in: m) {
                space.position = L.functionKeyPosition(.space)
                keyRoot.addChild(space)
                keyEntities[FunctionKey.space.rawValue] = space
                keyBase[FunctionKey.space.rawValue] = space.transform
                keyChannels[FunctionKey.space.rawValue] = Channel()
            }
        }

        // typebars
        if case let (m, _)? = load(.typebars, library: library), let bar = part("Typebar", in: m) {
            let count = KeyboardLayout.slotOrder.count
            for slot in 0..<count {
                let pose = L.typebarPose(slot: slot, count: count)
                let b = bar.clone(recursive: true)
                b.position = pose.pivot
                b.orientation = pose.rest
                b.scale = SIMD3(1, 1, pose.length / 0.11)
                basket.addChild(b)
                typebars.append(b)
                typebarPoses.append(pose)
                typebarChannels.append(Channel())
            }
        }

        // ribbon
        let P = L.printPoint
        if case let (m, v)? = load(.ribbon, library: library) {
            let lift = Float(v.mechanics["vibratorLift"].double(0.0065))
            for name in v.parts {
                guard let p = part(name, in: m) else { continue }
                let holder = Entity()
                if name.contains("Left") { holder.position = L.anchor("spoolLeft") }
                else if name.contains("Right") { holder.position = L.anchor("spoolRight") }
                else { holder.position = SIMD3(P.x, P.y - lift, P.z + 0.003) }
                holder.addChild(p)
                root.addChild(holder)
                if name == "pivot_SpoolLeft" || name == "pivot_SpoolRight" { spools.append(p) }
                if name == "pivot_Vibrator" { vibrator = p; vibratorBase = p.transform }
            }
            let twoColor = v.mechanics["twoColor"].bool ?? false
            for i in 0..<(twoColor ? 2 : 1) {
                let strip = ModelEntity()
                strip.name = "RibbonStrip\(i)"
                root.addChild(strip)
                ribbonStrips.append(strip)
            }
        }

        // correction
        if case let (m, v)? = load(.correction, library: library) {
            for name in v.parts {
                guard let p = part(name, in: m) else { continue }
                let holder = Entity()
                if name.contains("Left") { holder.position = L.anchor("correctionLeft") }
                else if name.contains("Right") { holder.position = L.anchor("correctionRight") }
                else { holder.position = SIMD3(P.x, P.y - 0.013, P.z + 0.005) }
                holder.addChild(p)
                root.addChild(holder)
                if name.hasPrefix("pivot_CorrSpool") { corrSpools.append(p) }
                if name == "pivot_Lifter" { lifter = p; lifterBase = p.transform }
            }
            let strip = ModelEntity()
            strip.name = "CorrectionStrip"
            root.addChild(strip)
            tapeStrip = strip
        }

        // bell
        if case let (m, v)? = load(.bell, library: library) {
            let holder = Entity()
            holder.position = L.anchor("bell")
            root.addChild(holder)
            for name in v.parts { if let p = part(name, in: m) { holder.addChild(p); if name == "pivot_Hammer" { hammer = p; hammerBase = p.transform } } }
        }

        // recorder
        recorder.position = L.anchor("recorder")
        root.addChild(recorder)
        if case let (m, v)? = load(.recorder, library: library) {
            for name in v.parts {
                guard let p = part(name, in: m) else { continue }
                recorder.addChild(p)
                recorderParts[name] = p
                recorderBase[name] = p.transform
            }
            if let med = findRole("medium", in: recorder) as? ModelEntity { medium = med }
        }

        updateMarginStops(left: spec.defaultLeftMargin, right: spec.defaultRightMargin)
        updateTabs(spec.defaultTabs)
        applyPose(all: true)
        redrawMedium()
    }

    private func findRole(_ role: String, in e: Entity) -> Entity? {
        if e.components[ModelComponent.self] != nil, Materials.roleName(of: e) == role { return e }
        for c in e.children { if let f = findRole(role, in: c) { return f } }
        return nil
    }

    // MARK: - ink & paper

    public func setInk(_ style: StrikeStyle) {
        inkColor = style.ink.color
        secondInk = style.ink.secondColor
        let mats = [Materials.solid(inkColor, roughness: 0.85), Materials.solid(secondInk, roughness: 0.85)]
        for (i, s) in ribbonStrips.enumerated() {
            if var model = s.components[ModelComponent.self] { model.materials = [mats[min(i, 1)]]; s.components.set(model) }
        }
        meshDirty = true
    }

    /// Paints the sheet in the background and puts it on the platen.
    public func loadSheet(_ sheet: Sheet?, dpi: CGFloat) async {
        self.dpi = dpi
        guard let sheet = sheet else {
            paperRenderer = nil
            paperVisible = false
            paperEntity.isEnabled = false
            return
        }
        let spec = self.spec
        let renderer = await Task.detached(priority: .userInitiated) { () -> PaperRenderer? in
            PaperRenderer(sheet: sheet, dpi: dpi, spec: spec)
        }.value
        guard let r = renderer else { return }
        paperRenderer = r
        paperStyle = sheet.paper
        pageSizeMeters = SIMD2(Float(Units.meters(sheet.pageSize.width)), Float(Units.meters(sheet.pageSize.height)))
        let W = Int(r.size.width), H = Int(r.size.height)
        colorTex = DynamicTexture(width: W, height: H, format: .rgba8sRGB)
        roughTex = DynamicTexture(width: W / 2, height: H / 2, format: .r8)
        metalTex = DynamicTexture(width: W / 2, height: H / 2, format: .r8)
        normalTex = DynamicTexture(width: W / 2, height: H / 2, format: .rgba8)
        uploadPaper(full: true)
        applyPaperMaterial()
        feed.set(sheet.feed)
        paperVisible = true
        paperEntity.isEnabled = true
        meshDirty = true
    }

    public func updateSheetStyles(_ styles: [StrikeStyle]) { paperRenderer?.update(styles: styles) }

    public var sheetSnapshot: CGImage? { paperRenderer?.snapshot() }

    private func applyPaperMaterial() {
        guard let colorRes = colorTex?.resource else { return }
        var front = PhysicallyBasedMaterial()
        front.baseColor = .init(tint: .white, texture: Materials.texture(colorRes, sampler: Materials.sharpSampler))
        if let r = roughTex?.resource { front.roughness = .init(scale: 1, texture: Materials.texture(r, sampler: Materials.sharpSampler)) }
        else { front.roughness = .init(floatLiteral: Float(paperStyle.finish.surfaceRoughness)) }
        if let m = metalTex?.resource { front.metallic = .init(scale: 1, texture: Materials.texture(m, sampler: Materials.sharpSampler)) }
        if let n = normalTex?.resource { front.normal = .init(texture: Materials.texture(n, sampler: Materials.sharpSampler)) }
        if paperStyle.finish == .glossy {
            front.clearcoat = .init(floatLiteral: 0.6)
            front.clearcoatRoughness = .init(floatLiteral: 0.12)
        }
        if paperStyle.finish == .onionskin || paperStyle.weight < 0.25 {
            // thin sheets glow a little where light passes through
            front.sheen = .init(tint: Materials.nsColor(paperStyle.color.mixed(with: .white, 0.5)))
        }
        var back = PhysicallyBasedMaterial()
        back.baseColor = .init(tint: Materials.nsColor(paperStyle.color.mixed(with: RGB(0.5, 0.5, 0.5), 0.08)))
        back.roughness = .init(floatLiteral: Float(paperStyle.finish.surfaceRoughness))
        paperEntity.model = ModelComponent(mesh: paperEntity.model?.mesh ?? MeshResource.generatePlane(width: 0.01, depth: 0.01),
                                           materials: [front, back])
    }

    private func uploadPaper(full: Bool = false) {
        guard let r = paperRenderer else { return }
        let dirty = r.takeDirty()
        let hadResource = colorTex?.resource != nil
        if full || dirty.color != nil { colorTex?.upload(from: r.color, rect: full ? nil : dirty.color) }
        if full || dirty.aux != nil {
            roughTex?.upload(from: r.roughness, rect: full ? nil : dirty.aux)
            metalTex?.upload(from: r.metal, rect: full ? nil : dirty.aux)
            normalTex?.upload(from: r.normal, rect: full ? nil : dirty.aux)
        }
        if !hadResource && colorTex?.resource != nil { applyPaperMaterial() }
    }

    // MARK: - margins & tabs

    private func stopX(_ column: Int) -> Float { -pageSizeMeters.x / 2 + Float(column) * layout.pitch + layout.pitch / 2 }

    public func updateMarginStops(left: Int, right: Int) {
        guard marginStops.count == 2 else { return }
        marginStops[0].position = SIMD3(stopX(left), 0.004, 0)
        marginStops[1].position = SIMD3(stopX(right), 0.004, 0)
    }

    public func updateTabs(_ tabs: [Int]) {
        tabEntities.forEach { $0.removeFromParent() }
        tabEntities = []
        guard let t = tabTemplate, let rack = marginRack else { return }
        for c in tabs {
            let e = t.clone(recursive: true)
            e.position = SIMD3(stopX(c), 0.004, 0)
            rack.addChild(e)
            tabEntities.append(e)
        }
    }

    // MARK: - direct control

    /// Place the carriage/platen without animation (loading a note).
    public func setPose(column: Int, feed f: Double) {
        carriageX.set(Double(layout.carriageX(column: Double(column), pageWidth: pageSizeMeters.x)))
        feed.set(f)
        meshDirty = true
        applyPose(all: true)
    }

    /// Physical key press from the Mac keyboard (independent of mechanics).
    public func press(key id: String, down: Bool) {
        guard let ch = keyChannels[id] else { return }
        let speed = variants[.keys]?.anim("speed", 1) ?? 1
        if down {
            physicallyHeld.insert(id)
            ch.animate(to: 1, duration: 0.028 / speed, curve: .easeIn)
        } else {
            physicallyHeld.remove(id)
            ch.animate(to: 0, duration: 0.07 / speed, curve: .overshoot(variants[.keys]?.anim("overshoot", 0.1) ?? 0.1))
        }
    }

    // MARK: - timeline

    public func play(_ events: [TimedEvent], delay: Double = 0) {
        for e in events { pending.append((clock + delay + e.at, e.event)) }
        pending.sort { $0.at < $1.at }
    }

    public var isBusy: Bool { !pending.isEmpty }

    public func tick(_ dt: Double) {
        clock += dt
        while let first = pending.first, first.at <= clock {
            pending.removeFirst()
            handle(first.event)
            onEvent?(first.event)
        }
        applyPose(dt: dt)
        if paperDirty {
            uploadPaper()
            paperDirty = false
        }
    }

    private func handle(_ event: MachineEvent) {
        let swing = spec.typebarSwing
        switch event {
        case let .typebar(slot, keyID):
            if typebarChannels.indices.contains(slot) {
                let ch = typebarChannels[slot]
                let over = variants[.typebars]?.anim("overshoot", 0.06) ?? 0.06
                ch.animate(to: 1, duration: swing, curve: .easeIn).then(to: 0, duration: spec.typebarReturn, curve: .overshoot(over))
            }
            if !physicallyHeld.contains(keyID), let k = keyChannels[keyID] {
                k.animate(to: 1, duration: 0.025, curve: .easeIn).then(to: 0, duration: 0.07, curve: .easeOut, delay: 0.02)
            }
        case let .vibratorLift(up):
            vib.animate(to: up ? 1 : 0, duration: up ? swing * 0.6 : 0.05, curve: up ? .easeOut : .easeInOut)
        case let .strike(s):
            paperRenderer?.draw(s)
            paperDirty = true
        case let .platenImpact(force):
            paperShake.kick(amplitude: 0.00035 * force * (1.2 - paperStyle.hardness * 0.6), frequency: 38, decay: 30)
            carriageX.kick(amplitude: 0.00004 * force, frequency: 55, decay: 40)
        case let .escapement(_, to):
            let x = Double(layout.carriageX(column: Double(to), pageWidth: pageSizeMeters.x))
            carriageX.animate(to: x, duration: spec.escapementSnap, curve: .overshoot(0.08))
        case let .carriageMove(_, to, duration, kind):
            let x = Double(layout.carriageX(column: Double(to), pageWidth: pageSizeMeters.x))
            let curve: Curve = kind == .carriageReturn || kind == .tab ? .easeIn : .easeInOut
            carriageX.animate(to: x, duration: duration, curve: curve)
        case let .carriageStop(force):
            carriageX.kick(amplitude: 0.0006 * force, frequency: 18, decay: 14)
        case let .platenRoll(_, to, _, duration):
            feed.animate(to: to, duration: duration, curve: .easeInOut)
        case let .returnLever(phase):
            lever.animate(to: phase == .push ? 1 : 0, duration: phase == .push ? 0.08 : 0.16, curve: phase == .push ? .easeOut : .overshoot(0.12))
        case .bell:
            let strikes = max(1, spec.bellStrikes)
            hammerCh.animate(to: 1, duration: 0.018, curve: .easeIn).then(to: 0, duration: 0.08, curve: .easeOut)
            for _ in 1..<strikes { hammerCh.then(to: 1, duration: 0.02, curve: .easeIn).then(to: 0, duration: 0.08, curve: .easeOut) }
        case .marginLock:
            carriageX.kick(amplitude: 0.0002, frequency: 30, decay: 25)
        case let .shift(down):
            shift.animate(to: down ? 1 : 0, duration: 0.06, curve: down ? .easeOut : .bounce(0.1))
        case let .ribbonAdvance(amount):
            spoolAngle.animate(to: spoolAngle.target + 0.09 * amount, duration: 0.04, curve: .easeOut)
            ribbonUsed = min(1, ribbonUsed + 0.0004 * amount)
            if ribbonUsed >= 1 { ribbonUsed = 0 }   // auto reverse
        case let .correctionLift(up):
            corr.animate(to: up ? 1 : 0, duration: up ? 0.05 : 0.08, curve: .easeOut)
            if up { tapeUsed = min(1, tapeUsed + 0.003) }
        case let .bail(lifted):
            bailCh.animate(to: lifted ? 1 : 0, duration: 0.14, curve: lifted ? .easeOut : .bounce(0.12))
        case let .releaseLever(open):
            releaseCh.animate(to: open ? 1 : 0, duration: 0.12, curve: .easeInOut)
        case .paperIn:
            paperEntity.isEnabled = paperVisible
        case .paperOut:
            paperEntity.isEnabled = false
            paperVisible = false
        case .paperEnd, .motorRun:
            break
        case let .marginSet(left, right):
            updateMarginStops(left: left, right: right)
        case let .tabsChanged(tabs):
            updateTabs(tabs)
        case let .tapePunch(bytes):
            journal.append(contentsOf: bytes)
            if journal.count > 512 { journal.removeFirst(journal.count - 512) }
            punchCh.animate(to: 1, duration: 0.015, curve: .easeIn).then(to: 0, duration: 0.04, curve: .easeOut)
            reelAngle.animate(to: reelAngle.target + 0.12 * Double(bytes.count), duration: 0.05, curve: .easeOut)
            redrawMedium()
        case let .tapeSeek(frames):
            reelAngle.animate(to: reelAngle.target + 0.05 * Double(frames), duration: 0.25, curve: .easeInOut)
        case let .clipPunch(bytes):
            clip.append(contentsOf: bytes)
            punchCh.animate(to: 1, duration: 0.01, curve: .easeIn).then(to: 0, duration: 0.03, curve: .easeOut)
            redrawMedium(showClip: true)
        case let .tapeRead(byte):
            readHead += 1
            _ = byte
            readerCh.animate(to: 1, duration: 0.012, curve: .easeOut).then(to: 0, duration: 0.03, curve: .easeIn)
            reelAngle.animate(to: reelAngle.target + 0.12, duration: 0.05, curve: .easeOut)
            redrawMedium(showClip: true)
        case let .springWind(level):
            barrel.animate(to: barrel.target + 6, duration: 0.7, curve: .easeInOut)
            gauge.animate(to: level, duration: 0.7)
        case let .springLevel(level):
            gauge.animate(to: level, duration: 0.2)
            barrel.animate(to: barrel.target + 0.2, duration: 0.2)
        }
    }

    /// Highlight (page rects in points) drawn as a tinted celluloid overlay on the sheet.
    public func setSelection(_ rects: [CGRect]) {
        selectionRects = rects
        rebuildSelection()
    }

    private func rebuildSelection() {
        guard paperVisible, !selectionRects.isEmpty else {
            selectionEntity.isEnabled = false
            return
        }
        let feedM = Float(Units.meters(feed.output))
        var pos: [SIMD3<Float>] = []
        var idx: [UInt32] = []
        for r in selectionRects {
            let x0 = Float(Units.meters(Double(r.minX))) - pageSizeMeters.x / 2
            let x1 = Float(Units.meters(Double(r.maxX))) - pageSizeMeters.x / 2
            let steps = 6
            let base = UInt32(pos.count)
            for k in 0...steps {
                let y = Float(Units.meters(Double(r.minY + (r.maxY - r.minY) * CGFloat(k) / CGFloat(steps))))
                let (p, n) = layout.paperPoint(feedM - y)
                let lifted = p + n * 0.0004
                pos.append(SIMD3(x0, lifted.x, lifted.y))
                pos.append(SIMD3(x1, lifted.x, lifted.y))
            }
            for k in 0..<UInt32(steps) {
                let a = base + k * 2
                idx += [a, a + 3, a + 1, a, a + 2, a + 3]
            }
        }
        var d = MeshDescriptor(name: "selection")
        d.positions = MeshBuffers.Positions(pos)
        d.primitives = .triangles(idx)
        guard let mesh = try? MeshResource.generate(from: [d]) else { return }
        var mat = UnlitMaterial(color: NSColor(srgbRed: 0.25, green: 0.55, blue: 1.0, alpha: 1))
        mat.blending = .transparent(opacity: .init(floatLiteral: 0.22))
        selectionEntity.model = ModelComponent(mesh: mesh, materials: [mat])
        selectionEntity.isEnabled = true
    }

    var paperEntityForHitTest: Entity? { paperVisible ? paperEntity : nil }
    var currentFeedMeters: Float { Float(Units.meters(feed.output)) }
    var pageMeters: SIMD2<Float> { pageSizeMeters }

    public func clearClipLoop() {
        clip = []
        readHead = 0
    }

    // MARK: - pose

    private func applyPose(dt: Double = 0, all: Bool = false) {
        let L = layout
        var paperNeeds = meshDirty
        if carriageX.step(dt) || all { carriage.position = L.carriageAnchor + SIMD3(Float(carriageX.output), 0, 0) }
        if shift.step(dt) || all {
            let s = Float(shift.output) * L.shiftTravel
            if L.shiftType == .carriage { carriageLift.position = SIMD3(0, s, 0); basket.position = .zero }
            else { basket.position = SIMD3(0, -s, 0); carriageLift.position = .zero }
        }
        if feed.step(dt) || all {
            let angle = Float(Units.meters(feed.output)) / L.platenRadius
            platen?.orientation = simd_quatf(angle: -angle, axis: SIMD3(1, 0, 0))
            if knobs.count == 2 {
                knobs[1].orientation = simd_quatf(angle: -angle, axis: SIMD3(1, 0, 0))
                knobs[0].orientation = simd_quatf(angle: -angle, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))
            }
            paperNeeds = true
        }
        if paperShake.step(dt) { paperNeeds = true }
        if paperNeeds && paperVisible {
            let originTop = colorTex?.originTop ?? false
            if let mesh = MeshFactory.paper(layout: L, pageWidth: pageSizeMeters.x, pageHeight: pageSizeMeters.y,
                                            feed: Float(Units.meters(feed.output)), originTop: originTop,
                                            shake: Float(paperShake.output)) {
                paperEntity.model?.mesh = mesh
            }
            meshDirty = false
            rebuildSelection()
        }
        let travel = Float(spec.keyTravel)
        for (id, ch) in keyChannels where ch.step(dt) || all {
            guard let e = keyEntities[id], var t = keyBase[id] else { continue }
            t.translation.y -= travel * Float(ch.output)
            e.transform = t
        }
        for (slot, ch) in typebarChannels.enumerated() where ch.step(dt) || all {
            let pose = typebarPoses[slot]
            typebars[slot].orientation = simd_slerp(pose.rest, pose.strike, Float(min(max(ch.output, -0.1), 1)))
        }
        var ribbonNeeds = all
        if vib.step(dt) || all, let v = vibrator {
            var t = vibratorBase
            t.translation.y += Float(vib.output) * Float(variants[.ribbon]?.mechanics["vibratorLift"].double(0.0065) ?? 0.0065)
            v.transform = t
            ribbonNeeds = true
        }
        if corr.step(dt) || all, let l = lifter {
            var t = lifterBase
            t.translation.y += Float(corr.output) * Float(variants[.correction]?.mechanics["lifterLift"].double(0.011) ?? 0.011)
            l.transform = t
            ribbonNeeds = true
        }
        if spoolAngle.step(dt) || all {
            for (i, s) in spools.enumerated() {
                s.orientation = simd_quatf(angle: Float(spoolAngle.output) * (i == 0 ? 1 : -1), axis: SIMD3(0, 1, 0))
                scaleWound(in: s, fraction: i == 0 ? 1 - ribbonUsed : ribbonUsed, maxRadius: 0.019)
            }
            for (i, s) in corrSpools.enumerated() {
                s.orientation = simd_quatf(angle: Float(tapeUsed * 40) * (i == 0 ? 1 : -1), axis: SIMD3(0, 1, 0))
                scaleWound(in: s, fraction: i == 0 ? 1 - tapeUsed : tapeUsed, maxRadius: 0.011)
            }
        }
        if ribbonNeeds { rebuildStrips() }
        if lever.step(dt) || all, let l = returnLever {
            let deg = Float(variants[.returnLever]?.mechanics["swingDegrees"].double(30) ?? 30)
            l.orientation = simd_quatf(angle: -Float(lever.output) * deg * .pi / 180, axis: SIMD3(0, 1, 0))
        }
        if bailCh.step(dt) || all, let b = bail {
            let deg = Float(variants[.paperBail]?.mechanics["bailLiftDegrees"].double(35) ?? 35)
            b.orientation = simd_quatf(angle: -Float(bailCh.output) * deg * .pi / 180, axis: SIMD3(1, 0, 0))
        }
        if releaseCh.step(dt) || all, let r = releaseLever {
            let deg = Float(variants[.paperBail]?.mechanics["releaseLeverDegrees"].double(40) ?? 40)
            r.orientation = simd_quatf(angle: Float(releaseCh.output) * deg * .pi / 180, axis: SIMD3(1, 0, 0))
        }
        if hammerCh.step(dt) || all, let h = hammer {
            let deg = Float(variants[.bell]?.mechanics["hammerDegrees"].double(28) ?? 28)
            var t = hammerBase
            t.rotation = simd_quatf(angle: Float(hammerCh.output) * deg * .pi / 180, axis: SIMD3(1, 0, 0)) * hammerBase.rotation
            h.transform = t
        }
        applyRecorder(dt: dt, all: all)
    }

    private func scaleWound(in spool: Entity, fraction: Double, maxRadius: Float) {
        guard let wound = findWound(spool) else { return }
        let r = max(0.0055, Float(0.006 + (Double(maxRadius) - 0.006) * fraction))
        // Wound meshes are unit cylinders scaled by their authored radius; normalize to the maximum.
        if wound.components[WoundBase.self] == nil { wound.components.set(WoundBase(scale: wound.scale)) }
        let base = wound.components[WoundBase.self]!.scale
        let k = r / maxRadius
        wound.scale = SIMD3(base.x * k, base.y, base.z * k)
    }

    private func findWound(_ e: Entity) -> Entity? {
        if e.name.hasPrefix("Wound") || (e.parent?.name.hasPrefix("Wound") ?? false && e.components[ModelComponent.self] != nil) { return e }
        for c in e.children { if let w = findWound(c) { return w } }
        return nil
    }

    private func rebuildStrips() {
        let P = layout.printPoint
        let lift = Float(variants[.ribbon]?.mechanics["vibratorLift"].double(0.0065) ?? 0.0065)
        let width = Float(variants[.ribbon]?.mechanics["ribbonWidth"].double(0.013) ?? 0.013)
        let ribbonY = P.y - lift + Float(vib.output) * lift
        let z = P.z + 0.0035
        let height = layout.anchor("spoolLeft").y + 0.007
        if !spools.isEmpty {
            let lc = layout.anchor("spoolLeft"), rc = layout.anchor("spoolRight")
            let radius = Float(0.006 + 0.013 * (1 - ribbonUsed)), radiusR = Float(0.006 + 0.013 * ribbonUsed)
            let gl = SIMD3<Float>(-0.03, ribbonY, z - 0.004), gr = SIMD3<Float>(0.03, ribbonY, z - 0.004)
            let a = MeshFactory.spoolTangent(center: lc, radius: radius, toward: gl, height: height)
            let b = MeshFactory.spoolTangent(center: rc, radius: radiusR, toward: gr, height: height)
            let mid = [SIMD3<Float>(-0.012, ribbonY, z), SIMD3<Float>(0.012, ribbonY, z)]
            let half = width / Float(max(ribbonStrips.count, 1))
            for (i, strip) in ribbonStrips.enumerated() {
                let off = ribbonStrips.count > 1 ? (i == 0 ? half / 2 : -half / 2) : 0
                let path = [a + SIMD3(0, off, 0), gl + SIMD3(0, off, 0)] + mid.map { $0 + SIMD3(0, off, 0) } + [gr + SIMD3(0, off, 0), b + SIMD3(0, off, 0)]
                if let mesh = MeshFactory.band(path: path, width: half) {
                    let mat = Materials.solid(i == 0 ? inkColor : secondInk, roughness: 0.85)
                    strip.model = ModelComponent(mesh: mesh, materials: [mat])
                }
            }
        }
        if let strip = tapeStrip, corrSpools.count == 2 {
            let lc = layout.anchor("correctionLeft"), rc = layout.anchor("correctionRight")
            let y = P.y - 0.013 + Float(corr.output) * 0.011 + 0.002
            let zz = P.z + 0.0055
            let h = lc.y + 0.005
            let gl = SIMD3<Float>(-0.02, y, zz - 0.003), gr = SIMD3<Float>(0.02, y, zz - 0.003)
            let a = MeshFactory.spoolTangent(center: lc, radius: Float(0.004 + 0.007 * (1 - tapeUsed)), toward: gl, height: h)
            let b = MeshFactory.spoolTangent(center: rc, radius: Float(0.004 + 0.007 * tapeUsed), toward: gr, height: h)
            let path = [a, gl, SIMD3(-0.008, y, zz), SIMD3(0.008, y, zz), gr, b]
            let width = Float(variants[.correction]?.mechanics["tapeWidth"].double(0.008) ?? 0.008)
            if let mesh = MeshFactory.band(path: path, width: width) {
                let tint = paperStyle.color.mixed(with: .white, 0.4).offset(spec.correctionTint)
                strip.model = ModelComponent(mesh: mesh, materials: [Materials.solid(tint, roughness: 0.92)])
            }
        }
    }

    // MARK: - recorder

    private func applyRecorder(dt: Double, all: Bool) {
        if punchCh.step(dt) || all, let p = recorderParts["pivot_Punch"], var t = recorderBase["pivot_Punch"] {
            t.translation.y -= Float(punchCh.output) * 0.004
            p.transform = t
        }
        if readerCh.step(dt) || all, let p = recorderParts["pivot_Reader"], var t = recorderBase["pivot_Reader"] {
            t.translation.y += Float(readerCh.output) * 0.002
            p.transform = t
        }
        if reelAngle.step(dt) || all {
            let a = Float(reelAngle.output)
            for (name, axis, k) in [("pivot_ReelSupply", SIMD3<Float>(0, 1, 0), Float(1)), ("pivot_ReelTakeup", SIMD3<Float>(0, 1, 0), Float(-1.2)),
                                    ("pivot_Gear1", SIMD3<Float>(0, 1, 0), Float(0.6)), ("pivot_Gear2", SIMD3<Float>(0, 1, 0), Float(-1.1)),
                                    ("pivot_Loop", SIMD3<Float>(0, 1, 0), Float(0.25)), ("pivot_Drum", SIMD3<Float>(1, 0, 0), Float(0.35))] {
                guard let p = recorderParts[name], let base = recorderBase[name] else { continue }
                var ax = axis
                // drum style gears are authored rotated onto X
                if name.hasPrefix("pivot_Gear"), recorderParts["pivot_Drum"] != nil { ax = SIMD3(1, 0, 0) }
                var t = base
                t.rotation = simd_quatf(angle: a * k, axis: ax) * base.rotation
                p.transform = t
            }
        }
        if gauge.step(dt) || all, let p = recorderParts["pivot_GaugeNeedle"], let base = recorderBase["pivot_GaugeNeedle"] {
            var t = base
            t.rotation = simd_quatf(angle: Float(-2.2 + 4.4 * gauge.output), axis: SIMD3(0, 1, 0))
            p.transform = t
        }
        if barrel.step(dt) || all, let p = recorderParts["pivot_SpringBarrel"], let base = recorderBase["pivot_SpringBarrel"] {
            var t = base
            t.rotation = simd_quatf(angle: Float(barrel.output), axis: SIMD3(0, 1, 0))
            p.transform = t
        }
    }

    /// Paints the visible window of the recorder medium: 8 data tracks + sprocket.
    private func redrawMedium(showClip: Bool = false) {
        guard let med = medium else { return }
        let framesVisible = Int(variants[.recorder]?.mechanics["framesVisible"].double(40) ?? 40)
        let along = variants[.recorder]?.mechanics["framesAlong"].string ?? "u"
        let W = along == "u" ? 1024 : 256
        let H = along == "u" ? 256 : 1024
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        let palette = variants[.recorder]?.palette["medium"]
        let base = palette.map { RGB($0[0], $0[1], $0[2]) } ?? RGB(0.93, 0.88, 0.70)
        ctx.setFillColor(CGColor(srgbRed: base.r, green: base.g, blue: base.b, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let frames: [UInt8] = showClip && !clip.isEmpty ? clip : journal
        let lenAxis = CGFloat(along == "u" ? W : H)
        let crossAxis = CGFloat(along == "u" ? H : W)
        let step = lenAxis / CGFloat(framesVisible)
        let visible = frames.suffix(framesVisible)
        ctx.setFillColor(CGColor(gray: 0.08, alpha: 0.95))
        for (i, byte) in visible.enumerated() {
            let pos = CGFloat(i) * step + step / 2
            for bit in 0..<9 {
                let track = bit < 3 ? bit : bit + 0       // tracks 0-2, sprocket at 3, 4-8 data
                let cross = crossAxis * (0.12 + 0.76 * CGFloat(track) / 8)
                let isSprocket = bit == 3
                let on = isSprocket || ((byte >> UInt8(bit < 3 ? bit : bit - 1)) & 1) == 1
                guard on else { continue }
                let r = isSprocket ? step * 0.14 : step * 0.26
                let center = along == "u" ? CGPoint(x: pos, y: cross) : CGPoint(x: cross, y: pos)
                ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            }
        }
        guard let img = ctx.makeImage() else { return }
        if let tex = mediumTexture {
            try? tex.replace(withImage: img, options: .init(semantic: .color))
        } else if let tex = try? TextureResource.generate(from: img, options: .init(semantic: .color)) {
            mediumTexture = tex
            var mat = Materials.material(role: "medium", palette: variants[.recorder]?.palette ?? [:])
            mat.baseColor = .init(tint: .white, texture: .init(tex))
            med.model?.materials = [mat]
        }
    }
}

/// Remembers the authored scale of a wound ribbon/tape cylinder.
struct WoundBase: Component {
    var scale: SIMD3<Float>
}

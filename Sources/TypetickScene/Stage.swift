import AppKit
import Combine
import RealityKit
import simd
import TypetickCore

/// Fixed viewpoints. The writing view never orbits: these are three seats at
/// the desk, picked in settings.
public enum StageFraming: String, CaseIterable, Codable, Sendable, Identifiable {
    case close, seated, desk
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .close: return "Close (Paper)"
        case .seated: return "Seated"
        case .desk: return "Whole Desk"
        }
    }
    var eye: SIMD3<Float> {
        switch self {
        case .close: return SIMD3(0, 0.40, 0.27)
        case .seated: return SIMD3(0, 0.50, 0.44)
        case .desk: return SIMD3(0.06, 0.68, 0.72)
        }
    }
    var target: SIMD3<Float> {
        switch self {
        case .close: return SIMD3(0, 0.175, -0.07)
        case .seated: return SIMD3(0, 0.13, -0.03)
        case .desk: return SIMD3(0.06, 0.07, 0.0)
        }
    }
    var fov: Float {
        switch self {
        case .close: return 32
        case .seated: return 36
        case .desk: return 38
        }
    }
}

/// The RealityKit view. Keyboard and mouse are forwarded to closures so the
/// app layer decides what they mean.
public final class StageView: ARView {
    public var onKeyDown: ((NSEvent) -> Bool)?
    public var onKeyUp: ((NSEvent) -> Void)?
    public var onFlags: ((NSEvent) -> Void)?
    public var onMouse: ((NSEvent, StageView) -> Void)?
    public var turntable = false
    public var onTurntable: ((CGVector, CGFloat) -> Void)?

    public override var acceptsFirstResponder: Bool { true }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    public override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true { super.keyDown(with: event) }
    }

    public override func keyUp(with event: NSEvent) { onKeyUp?(event) }

    public override func flagsChanged(with event: NSEvent) { onFlags?(event) }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Let menu shortcuts through; plain Control combos reach the machine.
        if event.modifierFlags.contains(.control) && !event.modifierFlags.contains(.command) {
            return onKeyDown?(event) ?? false
        }
        return super.performKeyEquivalent(with: event)
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if !turntable { onMouse?(event, self) }
    }

    public override func mouseDragged(with event: NSEvent) {
        if turntable { onTurntable?(CGVector(dx: event.deltaX, dy: event.deltaY), 0) } else { onMouse?(event, self) }
    }

    public override func mouseUp(with event: NSEvent) { if !turntable { onMouse?(event, self) } }

    public override func scrollWheel(with event: NSEvent) {
        if turntable { onTurntable?(.zero, event.scrollingDeltaY) } else { super.scrollWheel(with: event) }
    }

    /// World space ray through a point given in window coordinates.
    public func worldRay(windowPoint: NSPoint) -> (SIMD3<Float>, SIMD3<Float>)? {
        let p = convert(windowPoint, from: nil)
        return ray(through: p)
    }
}

/// Desk, lamps, window light, environment reflections and the camera.
@MainActor
public final class StageEnvironment {
    public let root = Entity()
    private let desk = ModelEntity()
    private let lamp = SpotLight()
    private let fill = PointLight()
    private let window = DirectionalLight()
    private let camera = PerspectiveCamera()
    private var turntableYaw: Float = 0.5
    private var turntablePitch: Float = 0.45
    private var turntableDistance: Float = 0.85
    private var lastDesk: DeskStyle?
    private let motes = Entity()
    private var envGeneration = 0
    private var showMotes = true
    public private(set) var lampWorldPosition = SIMD3<Float>(-0.42, 0.42, -0.22)
    public private(set) var lampColor = SIMD3<Float>(1, 0.8, 0.6)

    public init() {
        root.addChild(motes)
        setUpMotes()
        root.addChild(desk)
        root.addChild(lamp)
        root.addChild(fill)
        root.addChild(window)
        root.addChild(camera)
        desk.model = ModelComponent(mesh: .generatePlane(width: 2.4, depth: 1.6, cornerRadius: 0.02),
                                    materials: [Materials.solid(RGB(0.3, 0.18, 0.1))])
        desk.position = SIMD3(0, -0.0005, 0)
    }

    private func installEnvironment(_ img: CGImage, generation: Int, view: ARView) async {
        guard generation == envGeneration,
              let res = try? await EnvironmentResource(equirectangular: img) else { return }
        guard generation == envGeneration else { return }
        view.environment.lighting.resource = res
    }

    /// Dust floating in the lamp light. Tiny additive specks drifting slowly.
    private func setUpMotes() {
        var p = ParticleEmitterComponent()
        p.emitterShape = .box
        p.emitterShapeSize = SIMD3(0.7, 0.45, 0.5)
        p.birthLocation = .volume
        p.speed = 0.002
        p.mainEmitter.birthRate = 35
        p.mainEmitter.lifeSpan = 14
        p.mainEmitter.size = 0.00045
        p.mainEmitter.color = .constant(.single(NSColor(white: 1, alpha: 0.35)))
        p.mainEmitter.blendMode = .additive
        p.mainEmitter.noiseStrength = 0.004
        p.mainEmitter.noiseScale = 0.5
        p.mainEmitter.opacityCurve = .gradualFadeInOut
        motes.components.set(p)
        motes.position = SIMD3(-0.12, 0.3, -0.1)
    }

    public func setDustMotes(_ on: Bool) {
        showMotes = on
        motes.isEnabled = on
    }

    public func setFraming(_ f: StageFraming) {
        camera.camera.fieldOfViewInDegrees = f.fov
        camera.camera.near = 0.02
        camera.camera.far = 20
        camera.look(at: f.target, from: f.eye, relativeTo: nil)
    }

    public func turntable(delta: CGVector, zoom: CGFloat) {
        turntableYaw -= Float(delta.dx) * 0.008
        turntablePitch = min(1.35, max(0.05, turntablePitch + Float(delta.dy) * 0.006))
        turntableDistance = min(2.0, max(0.35, turntableDistance * (1 - Float(zoom) * 0.01)))
        updateTurntable()
    }

    public func updateTurntable() {
        let target = SIMD3<Float>(0.03, 0.1, 0)
        let eye = target + turntableDistance * SIMD3(sin(turntableYaw) * cos(turntablePitch), sin(turntablePitch),
                                                      cos(turntableYaw) * cos(turntablePitch))
        camera.camera.fieldOfViewInDegrees = 35
        camera.look(at: target, from: eye, relativeTo: nil)
    }

    public func apply(desk style: DeskStyle) {
        guard style != lastDesk else { return }
        lastDesk = style
        Task.detached(priority: .utility) {
            let set = ProceduralTextures.desk(style)
            await MainActor.run { [weak self] in
                guard let self = self, let set = set else { return }
                self.applyDeskTextures(set, style: style)
            }
        }
    }

    private func applyDeskTextures(_ set: ProceduralTextures.SurfaceSet, style: DeskStyle) {
        guard let color = try? TextureResource.generate(from: set.color, options: .init(semantic: .color)),
              let rough = try? TextureResource.generate(from: set.roughness, options: .init(semantic: .scalar)),
              let normal = try? TextureResource.generate(from: set.normal, options: .init(semantic: .normal)) else { return }
        var m = PhysicallyBasedMaterial()
        let s = Materials.repeatSampler
        m.baseColor = .init(tint: .white, texture: Materials.texture(color, sampler: s))
        m.roughness = .init(scale: 1, texture: Materials.texture(rough, sampler: s))
        m.normal = .init(texture: Materials.texture(normal, sampler: s))
        m.metallic = .init(floatLiteral: set.metallic)
        if style.material == .glass || style.gloss > 0.6 {
            m.clearcoat = .init(floatLiteral: Float(style.gloss))
            m.clearcoatRoughness = .init(floatLiteral: 0.05)
        }
        let repeats = set.tilesPerMeter
        m.textureCoordinateTransform = .init(offset: .zero, scale: SIMD2(2.4 * repeats, 1.6 * repeats), rotation: 0)
        desk.model?.materials = [m]
    }

    public func apply(environment env: EnvironmentStyle, to view: ARView) {
        let lampRGB = env.lamp == .neon ? env.neonColor : EnvironmentStyle.kelvinToRGB(env.lampKelvin)
        lamp.light.color = Materials.nsColor(lampRGB)
        lamp.light.intensity = env.lamp == .none ? 0 : Float(14000 * env.lampIntensity)
        lamp.light.innerAngleInDegrees = env.lamp == .architect ? 28 : 40
        lamp.light.outerAngleInDegrees = env.lamp == .architect ? 55 : 75
        lamp.light.attenuationRadius = 4
        if env.shadows { lamp.shadow = SpotLightComponent.Shadow() } else { lamp.shadow = nil }
        let lampPos: SIMD3<Float>
        switch env.lamp {
        case .bankers: lampPos = SIMD3(-0.42, 0.42, -0.22)
        case .architect: lampPos = SIMD3(-0.32, 0.62, 0.1)
        case .candle: lampPos = SIMD3(0.38, 0.22, -0.12)
        case .edison: lampPos = SIMD3(0.05, 0.9, -0.1)
        case .neon: lampPos = SIMD3(0.4, 0.6, -0.6)
        case .fluorescent: lampPos = SIMD3(0, 1.2, 0.1)
        case .none: lampPos = SIMD3(0, 1, 0)
        }
        lamp.look(at: SIMD3(0.0, 0.08, -0.02), from: lampPos, relativeTo: nil)

        // soft bounce near the lamp
        fill.light.color = Materials.nsColor(lampRGB)
        fill.light.intensity = env.lamp == .none ? 0 : Float(1800 * env.lampIntensity)
        fill.light.attenuationRadius = 1.5
        fill.position = lampPos + SIMD3(0, 0.1, 0)

        let sun: (RGB, Float)
        switch env.timeOfDay {
        case .dawn: sun = (RGB(1.0, 0.78, 0.6), 1400)
        case .day: sun = (RGB(1.0, 0.98, 0.94), 3200)
        case .dusk: sun = (RGB(1.0, 0.6, 0.38), 900)
        case .night: sun = (RGB(0.55, 0.65, 0.95), 120)
        }
        window.light.color = Materials.nsColor(sun.0)
        window.light.intensity = env.windowLight ? sun.1 : 0
        if env.shadows && env.windowLight {
            window.shadow = DirectionalLightComponent.Shadow(maximumDistance: 1.5, depthBias: 2)
        } else {
            window.shadow = nil
        }
        let sunDir: SIMD3<Float> = env.timeOfDay == .day ? SIMD3(-0.8, 1.6, -0.6) : SIMD3(-1.2, 0.6, -0.5)
        window.look(at: .zero, from: sunDir, relativeTo: nil)

        // The HDR room takes a moment to paint: do it off the main thread.
        envGeneration += 1
        let generation = envGeneration
        Task.detached(priority: .utility) {
            let img = ProceduralTextures.environmentHDR(env) ?? ProceduralTextures.environment(env)
            guard let img = img else { return }
            await self.installEnvironment(img, generation: generation, view: view)
        }
        lampWorldPosition = lampPos
        lampColor = SIMD3(Float(lampRGB.r), Float(lampRGB.g), Float(lampRGB.b)) * (env.lamp == .none ? 0 : 1)
        motes.isEnabled = showMotes && env.lamp != .none
        let exposure: Float
        switch env.timeOfDay {
        case .day: exposure = -0.4
        case .dawn, .dusk: exposure = -0.6
        case .night: exposure = -0.8
        }
        view.environment.lighting.intensityExponent = exposure + Float(env.ambient - 0.5)
        let bg = env.timeOfDay == .night ? RGB(0.02, 0.02, 0.025) : RGB(0.09, 0.08, 0.075)
        view.environment.background = .color(Materials.nsColor(bg))
    }
}

/// Glue: one view, one environment, one machine.
@MainActor
public final class Stage {
    public let view: StageView
    public let environment = StageEnvironment()
    public private(set) var rig: MachineRig?
    private let anchor = AnchorEntity(world: .zero)
    private var updates: Cancellable?
    private let turntableRoot = Entity()
    public let post = PostProcessor()

    public init(turntable: Bool = false) {
        view = StageView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.turntable = turntable
        post.install(on: view)
        anchor.addChild(environment.root)
        anchor.addChild(turntableRoot)
        view.scene.addAnchor(anchor)
        if turntable {
            environment.updateTurntable()
            view.onTurntable = { [weak self] delta, zoom in self?.environment.turntable(delta: delta, zoom: zoom) }
        }
        updates = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                self.rig?.tick(event.deltaTime)
                self.updateLampProjection()
            }
        }
    }

    /// Camera, film and surface wear settings.
    public func apply(look: RenderLook) {
        post.look = look
        Materials.wear = Float(look.surfaceWear)
        environment.setDustMotes(look.dustMotes)
    }

    private func updateLampProjection() {
        let b = view.bounds
        guard b.width > 0, b.height > 0, let p = view.project(environment.lampWorldPosition) else { return }
        var uv = SIMD2<Float>(Float(p.x / b.width), Float(p.y / b.height))
        if !view.isFlipped { uv.y = 1 - uv.y }
        post.setLamp(uv: uv, color: environment.lampColor)
    }

    public func install(_ rig: MachineRig) {
        self.rig?.root.removeFromParent()
        self.rig = rig
        turntableRoot.addChild(rig.root)
    }
}

extension MachineRig {
    /// Page point (in points) under a world space ray, if it hits the sheet.
    public func pagePoint(rayOrigin o: SIMD3<Float>, direction d: SIMD3<Float>, carriageEntity: Entity? = nil) -> CGPoint? {
        guard let paper = paperEntityForHitTest else { return nil }
        let lo = paper.convert(position: o, from: nil)
        let ld = simd_normalize(paper.convert(direction: d, from: nil))
        let feedM = currentFeedMeters
        let H = pageMeters.y, W = pageMeters.x
        var best: (t: Float, y: Float, x: Float)? = nil
        var y: Float = 0
        var prev = layout.paperPoint(feedM - y).position
        while y < H {
            let y2 = min(H, y + 0.001)
            let cur = layout.paperPoint(feedM - y2).position
            // plane through the segment, containing the X axis
            let seg = cur - prev
            let n = SIMD2(-seg.y, seg.x)
            let denom = n.x * ld.y + n.y * ld.z
            if abs(denom) > 1e-7 {
                let t = (n.x * (prev.x - lo.y) + n.y * (prev.y - lo.z)) / denom
                if t > 0 {
                    let hit = lo + ld * t
                    let along = simd_dot(SIMD2(hit.y, hit.z) - prev, seg) / max(simd_length_squared(seg), 1e-12)
                    if along >= 0 && along <= 1 && abs(hit.x) <= W / 2 && (best == nil || t < best!.t) {
                        best = (t, y + (y2 - y) * along, hit.x + W / 2)
                    }
                }
            }
            prev = cur
            y = y2
        }
        guard let b = best else { return nil }
        return CGPoint(x: Units.points(Double(b.x)), y: Units.points(Double(b.y)))
    }
}

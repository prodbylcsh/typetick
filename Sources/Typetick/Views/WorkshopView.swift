import AppKit
import SwiftUI
import TypetickCore
import TypetickScene

struct WorkshopView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(WorkshopSection.allCases, selection: Binding<WorkshopSection?>(get: { model.workshopSection },
                                                                                set: { model.workshopSection = $0 ?? .machine })) { s in
                Label(s.title, systemImage: s.symbol).tag(s)
            }
            .navigationSplitViewColumnWidth(170)
        } detail: {
            switch model.workshopSection {
            case .machine: MachineEditor()
            case .paper: PaperEditor()
            case .ink: InkEditor()
            case .typeface: TypefaceEditor()
            case .desk: DeskEditor()
            case .lighting: LightingEditor()
            }
        }
        .navigationTitle("Workshop")
    }
}

// MARK: - Machine

/// Separate turntable stage so the writing view keeps its fixed camera.
@MainActor
final class WorkshopPreview {
    let stage = Stage(turntable: true)
    private var config: MachineConfiguration?

    func show(_ config: MachineConfiguration, desk: DeskStyle, environment: EnvironmentStyle) {
        if config != self.config {
            self.config = config
            let lib = ComponentLibrary.shared
            let variants = lib.resolve(config)
            guard variants[.chassis] != nil, variants[.carriage] != nil else { return }
            let rig = MachineRig(variants: variants, spec: lib.spec(for: config), library: lib)
            stage.install(rig)
            rig.setPose(column: 30, feed: -200)
        }
        stage.environment.apply(desk: desk)
        stage.environment.apply(environment: environment, to: stage.view)
    }
}

struct MachineEditor: View {
    @Environment(AppModel.self) private var model
    @State private var kind: ComponentKind = .chassis
    @State private var preview = WorkshopPreview()
    private let library = ComponentLibrary.shared

    var body: some View {
        HStack(spacing: 0) {
            List(ComponentKind.allCases, selection: Binding<ComponentKind?>(get: { kind }, set: { kind = $0 ?? .chassis })) { k in
                HStack {
                    Image(systemName: k.symbol).frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(k.title)
                        Text(library.variant(k, model.preferences.machine[k])?.name ?? "—")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tag(k)
            }
            .frame(width: 200)

            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    StageContainer(stage: preview.stage)
                    Text("Drag to turn · scroll to zoom")
                        .font(.caption).padding(6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                }
                .frame(minHeight: 300)
                HStack {
                    Button("Shuffle") { shuffle() }
                    Button("Factory Standard") { model.preferences.machine = .standard }
                    Spacer()
                    Button("Reload Library") {
                        library.reload()
                        model.preferences.machine[kind] = model.preferences.machine[kind]
                    }
                    Button("Custom Components Folder") {
                        let url = ComponentLibrary.userComponentsFolder
                        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(url)
                    }
                }
                .padding(10)
            }
            .frame(minWidth: 360)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let k = library.kinds[kind] {
                        Text(k.title).font(.title2.weight(.semibold))
                        Text(k.summary).foregroundStyle(.secondary).font(.callout)
                    }
                    ForEach(library.variants(kind)) { v in
                        VariantCard(variant: v, selected: model.preferences.machine[kind] == v.id)
                            .onTapGesture { model.preferences.machine[kind] = v.id }
                    }
                }
                .padding(14)
            }
            .frame(width: 320)
            .background(.background.secondary)
        }
        .onAppear { refresh() }
        .onChange(of: model.preferences.machine) { _, _ in refresh() }
        .onChange(of: model.preferences.desk) { _, _ in refresh() }
    }

    private func refresh() {
        preview.show(model.preferences.machine, desk: model.preferences.desk, environment: model.preferences.environment)
    }

    private func shuffle() {
        var c = model.preferences.machine
        for k in ComponentKind.allCases {
            if let v = library.variants(k).randomElement() { c[k] = v.id }
        }
        model.preferences.machine = c
    }
}

struct VariantCard: View {
    let variant: VariantManifest
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(variant.name).font(.headline)
                Spacer()
                Text(variant.era).font(.caption.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Text(variant.summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let tags = variant.tags, !tags.isEmpty {
                HStack { ForEach(tags, id: \.self) { Text($0).font(.caption2).foregroundStyle(.tertiary) } }
            }
            HStack(spacing: 4) {
                ForEach(Array(variant.palette.keys.sorted().prefix(4)), id: \.self) { key in
                    if let c = variant.palette[key], c.count >= 3 {
                        Circle().fill(Color(rgb: RGB(c[0], c[1], c[2]))).frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.quaternary))
                    }
                }
                Spacer()
                SoundBars(variant: variant)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
    }
}

/// Tiny visual of the voice: pitch, body, brightness, ring.
struct SoundBars: View {
    let variant: VariantManifest
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(["pitch", "body", "brightness", "ring"], id: \.self) { k in
                let v = min(1.4, variant.sound(k, 0.5))
                RoundedRectangle(cornerRadius: 1).fill(.secondary)
                    .frame(width: 3, height: 3 + 12 * v / 1.4)
                    .help(k)
            }
        }
    }
}

// MARK: - Paper

struct PaperEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(alignment: .top, spacing: 20) {
            Form {
                Section("Presets") {
                    PresetRow(names: PaperStyle.presets.map(\.0)) { i in model.preferences.paper = PaperStyle.presets[i].1 }
                }
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(30)), count: 10), spacing: 8) {
                        ForEach(PaperTint.allCases) { t in
                            Swatch(color: t.shades[2], selected: model.preferences.paper.tint == t)
                                .onTapGesture { model.preferences.paper.tint = t }
                                .help(t.title)
                        }
                    }
                    HStack {
                        Text("Shade")
                        ForEach(0..<5, id: \.self) { i in
                            Swatch(color: model.preferences.paper.tint.shades[i], selected: model.preferences.paper.shade == i)
                                .onTapGesture { model.preferences.paper.shade = i }
                        }
                    }
                }
                Section("Surface") {
                    Picker("Finish", selection: $model.preferences.paper.finish) {
                        ForEach(PaperFinish.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Size", selection: $model.preferences.paper.size) {
                        ForEach(PaperSize.allCases) { Text($0.title).tag($0) }
                    }
                    LabeledSlider("Hardness", value: $model.preferences.paper.hardness, help: "Soft paper takes deep impressions and lets ink spread")
                    LabeledSlider("Tooth", value: $model.preferences.paper.tooth)
                    LabeledSlider("Fibers", value: $model.preferences.paper.fibers)
                    LabeledSlider("Wrinkles", value: $model.preferences.paper.wrinkle)
                    LabeledSlider("Age", value: $model.preferences.paper.age)
                    LabeledSlider("Weight", value: $model.preferences.paper.weight, help: "Thin sheets glow slightly in the lamp light")
                }
                Section {
                    Text("New sheets use this paper. Sheets already typed keep theirs.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Apply to the Sheet in the Machine") { model.controller.restyleCurrentSheet(paper: model.preferences.paper) }
                        .disabled(model.selectedNoteID == nil)
                }
            }
            .formStyle(.grouped)
            .frame(width: 400)
            PreviewPane()
        }
    }
}

// MARK: - Ink

struct InkEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(alignment: .top, spacing: 20) {
            Form {
                Section("Presets") {
                    PresetRow(names: InkStyle.presets.map(\.0)) { i in model.preferences.ink = InkStyle.presets[i].1 }
                }
                Section("Ribbon") {
                    Picker("Ink", selection: $model.preferences.ink.kind) {
                        ForEach(InkKind.allCases) { Text($0.title).tag($0) }
                    }
                    Text(model.preferences.ink.kind.summary).font(.caption).foregroundStyle(.secondary)
                    ColorPicker("Color", selection: Binding(get: { Color(rgb: model.preferences.ink.color) },
                                                             set: { model.preferences.ink.color = RGB($0) }), supportsOpacity: false)
                    ColorPicker("Second color (two-color ribbon)", selection: Binding(get: { Color(rgb: model.preferences.ink.secondColor) },
                                                                                      set: { model.preferences.ink.secondColor = RGB($0) }),
                                supportsOpacity: false)
                    InkSwatches { model.preferences.ink.color = $0 }
                }
                Section("Behavior") {
                    LabeledSlider("Bleed", value: $model.preferences.ink.bleed, help: "How far ink wicks into the fibers")
                    LabeledSlider("Density", value: $model.preferences.ink.density)
                    LabeledSlider("Unevenness", value: $model.preferences.ink.variance)
                    LabeledSlider("Ribbon wear", value: $model.preferences.ink.wear)
                    LabeledSlider("Halo", value: $model.preferences.ink.halo)
                    LabeledSlider("Sheen", value: $model.preferences.ink.sheen, help: "Shine of pearl, foil, flake and iridescent inks")
                }
                Text("A new ribbon only affects what you type from now on.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .frame(width: 400)
            PreviewPane()
        }
    }
}

struct InkSwatches: View {
    var pick: (RGB) -> Void
    private let colors: [RGB] = [RGB(hex: 0x16161A), RGB(hex: 0x3A3A40), RGB(hex: 0x1C2A55), RGB(hex: 0x2B4C8C), RGB(hex: 0x1F4D3A),
                                 RGB(hex: 0xA3241E), RGB(hex: 0x6E1F3A), RGB(hex: 0x4A2E1E), RGB(hex: 0x5C3D8A), RGB(hex: 0xF4F1E8),
                                 RGB(hex: 0xC9A045), RGB(hex: 0xC8CACC)]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, c in
                Swatch(color: c, selected: false, size: 18).onTapGesture { pick(c) }
            }
        }
    }
}

// MARK: - Typeface

struct TypefaceEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(alignment: .top, spacing: 20) {
            Form {
                Section("Type slugs") {
                    ForEach(TypefaceStyle.presets, id: \.fontName) { t in
                        HStack {
                            Text(t.displayName)
                                .font(.custom(t.fontName == "system-mono" ? "Menlo" : t.fontName, size: 15))
                            Spacer()
                            if model.preferences.typeface.fontName == t.fontName { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            var nt = t
                            nt.scale = model.preferences.typeface.scale
                            nt.baselineJitter = model.preferences.typeface.baselineJitter
                            nt.rotationJitter = model.preferences.typeface.rotationJitter
                            model.preferences.typeface = nt
                        }
                    }
                }
                Section("Alignment") {
                    LabeledSlider("Size", value: $model.preferences.typeface.scale, range: 0.7...1.3)
                    LabeledSlider("Baseline wander", value: $model.preferences.typeface.baselineJitter, range: 0...1.5)
                    LabeledSlider("Tilt wander", value: $model.preferences.typeface.rotationJitter, range: 0...3)
                }
                Text("The escapement pitch comes from the carriage (pica or elite).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .frame(width: 400)
            PreviewPane()
        }
    }
}

// MARK: - Desk & lighting

struct DeskEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Surface") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: 10) {
                    ForEach(DeskMaterial.allCases) { m in
                        Button {
                            model.preferences.desk.material = m
                        } label: {
                            VStack {
                                RoundedRectangle(cornerRadius: 8).fill(Color(rgb: deskSwatch(m))).frame(height: 44)
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .stroke(model.preferences.desk.material == m ? Color.accentColor : .clear, lineWidth: 2))
                                Text(m.title).font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Section("Finish") {
                Toggle("Tint", isOn: Binding(get: { model.preferences.desk.tint != nil },
                                             set: { model.preferences.desk.tint = $0 ? RGB(0.6, 0.6, 0.6) : nil }))
                if model.preferences.desk.tint != nil {
                    ColorPicker("Tint color", selection: Binding(get: { Color(rgb: model.preferences.desk.tint ?? RGB(0.6, 0.6, 0.6)) },
                                                                 set: { model.preferences.desk.tint = RGB($0) }), supportsOpacity: false)
                }
                LabeledSlider("Grain scale", value: $model.preferences.desk.grainScale, range: 0.4...2.5)
                LabeledSlider("Gloss", value: $model.preferences.desk.gloss)
                LabeledSlider("Wear", value: $model.preferences.desk.wear)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
    }

    private func deskSwatch(_ m: DeskMaterial) -> RGB {
        switch m {
        case .walnut: return RGB(0.28, 0.16, 0.09)
        case .oak: return RGB(0.6, 0.43, 0.25)
        case .cherry: return RGB(0.48, 0.2, 0.11)
        case .ebony: return RGB(0.07, 0.06, 0.05)
        case .pine: return RGB(0.78, 0.6, 0.38)
        case .marble: return RGB(0.88, 0.87, 0.84)
        case .slate: return RGB(0.2, 0.21, 0.23)
        case .leather: return RGB(0.25, 0.13, 0.07)
        case .felt: return RGB(0.1, 0.25, 0.15)
        case .linoleum: return RGB(0.4, 0.48, 0.42)
        case .steel: return RGB(0.6, 0.6, 0.62)
        case .concrete: return RGB(0.55, 0.55, 0.53)
        case .glass: return RGB(0.1, 0.13, 0.13)
        }
    }
}

struct LightingEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Room") {
                Picker("Time of day", selection: $model.preferences.environment.timeOfDay) {
                    ForEach(TimeOfDay.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Window light", isOn: $model.preferences.environment.windowLight)
                LabeledSlider("Ambient", value: $model.preferences.environment.ambient)
                Toggle("Shadows", isOn: $model.preferences.environment.shadows)
            }
            Section("Lamp") {
                Picker("Lamp", selection: Binding(get: { model.preferences.environment.lamp }, set: { lamp in
                    model.preferences.environment.lamp = lamp
                    if lamp.kelvin > 0 { model.preferences.environment.lampKelvin = lamp.kelvin }
                })) {
                    ForEach(LampKind.allCases) { Text($0.title).tag($0) }
                }
                if model.preferences.environment.lamp == .neon {
                    ColorPicker("Neon color", selection: Binding(get: { Color(rgb: model.preferences.environment.neonColor) },
                                                                 set: { model.preferences.environment.neonColor = RGB($0) }), supportsOpacity: false)
                } else {
                    LabeledSlider("Color temperature", value: $model.preferences.environment.lampKelvin, range: 1800...6500, format: "%.0f K")
                }
                LabeledSlider("Brightness", value: $model.preferences.environment.lampIntensity, range: 0...2)
            }
            Section("View") {
                Picker("Seat", selection: $model.preferences.framing) {
                    ForEach(StageFraming.allCases) { Text($0.title).tag($0) }
                }
                Text("The writing view never moves; pick where you sit.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
    }
}

// MARK: - shared bits

struct PreviewPane: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Proof").font(.headline)
            SamplePreview(paper: model.preferences.paper, ink: model.preferences.ink, typeface: model.preferences.typeface,
                          spec: ComponentLibrary.shared.spec(for: model.preferences.machine))
                .frame(maxWidth: 560)
            Spacer()
        }
        .padding(.vertical, 20)
        .padding(.trailing, 20)
    }
}

struct Swatch: View {
    let color: RGB
    let selected: Bool
    var size: CGFloat = 26
    var body: some View {
        Circle().fill(Color(rgb: color))
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Color.secondary.opacity(0.35)))
            .overlay(Circle().stroke(Color.accentColor, lineWidth: selected ? 2.5 : 0).padding(-3))
    }
}

struct PresetRow: View {
    let names: [String]
    let pick: (Int) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(Array(names.enumerated()), id: \.offset) { i, n in
                    Button(n) { pick(i) }.buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var format: String = "%.2f"
    var help: String? = nil

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double> = 0...1, format: String = "%.2f", help: String? = nil) {
        self.title = title
        _value = value
        self.range = range
        self.format = format
        self.help = help
    }

    var body: some View {
        HStack {
            Text(title).frame(width: 130, alignment: .leading)
            Slider(value: $value, in: range)
            Text(String(format: format, value)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
        }
        .help(help ?? title)
    }
}

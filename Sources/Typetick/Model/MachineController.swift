import AppKit
import Foundation
import Observation
import TypetickAudio
import TypetickCore
import TypetickScene

/// Connects the keyboard, the mechanical model, the 3D rig, the sound and the
/// note being typed on.
@MainActor
@Observable
final class MachineController {
    // observable state for the HUD
    private(set) var column = 0
    private(set) var leftMargin = 10
    private(set) var rightMargin = 75
    private(set) var lineSpacing = 1.0
    private(set) var springLevel = 0.6
    private(set) var selectionLength = 0
    private(set) var autoTyping = false
    private(set) var hasPaper = false
    private(set) var secondColor = false
    private(set) var status: String?

    @ObservationIgnored let stage = Stage()
    @ObservationIgnored private(set) var machine: TypewriterMachine
    @ObservationIgnored private let director = SoundDirector()
    @ObservationIgnored private let library = ComponentLibrary.shared
    @ObservationIgnored private weak var store: NoteStore?
    @ObservationIgnored private(set) var noteID: UUID?
    @ObservationIgnored private var prefs: Preferences
    @ObservationIgnored private var selAnchor: CellKey?
    @ObservationIgnored private var selHead: CellKey?
    @ObservationIgnored private var dragMoved = false
    @ObservationIgnored private var autoTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var heldKeys: Set<UInt16> = []

    init(preferences: Preferences, store: NoteStore) {
        prefs = preferences
        self.store = store
        let spec = ComponentLibrary.shared.spec(for: preferences.machine)
        machine = TypewriterMachine(spec: spec, style: StrikeStyle(ink: preferences.ink, typeface: preferences.typeface))
        machine.settings = preferences.machineSettings
        stage.view.onKeyDown = { [weak self] e in self?.keyDown(e) ?? false }
        stage.view.onKeyUp = { [weak self] e in self?.keyUp(e) }
        stage.view.onFlags = { [weak self] e in self?.flags(e) }
        stage.view.onMouse = { [weak self] e, v in self?.mouse(e, view: v) }
        rebuildMachine()
        applyScene(preferences, force: true)
        syncHUD()
    }

    // MARK: - configuration

    func apply(_ p: Preferences) {
        let old = prefs
        prefs = p
        machine.settings = p.machineSettings
        machine.style = StrikeStyle(ink: p.ink, typeface: p.typeface)
        stage.rig?.setInk(machine.style)
        if p.machine != old.machine { rebuildMachine() }
        applyScene(p, force: false, old: old)
        director.engine.volume = p.soundEnabled ? Float(p.volume) : 0
        director.engine.enabled = p.soundEnabled
        director.engine.setRoom(wet: Float(p.roomReverb))
        var voice = director.engine.voice
        voice.paperHardness = p.paper.hardness
        director.engine.configure(voice)
    }

    private func applyScene(_ p: Preferences, force: Bool, old: Preferences? = nil) {
        if force || p.framing != old?.framing { stage.environment.setFraming(p.framing) }
        if force || p.desk != old?.desk { stage.environment.apply(desk: p.desk) }
        if force || p.environment != old?.environment { stage.environment.apply(environment: p.environment, to: stage.view) }
        if force || p.look != old?.look {
            let rebuild = old != nil && p.look.surfaceWear != old?.look.surfaceWear
            stage.apply(look: p.look)
            if rebuild { rebuildMachine() }
        }
    }

    private func rebuildMachine() {
        let variants = library.resolve(prefs.machine)
        guard variants[.chassis] != nil, variants[.carriage] != nil else {
            status = "Component library missing. Run Tools/ModelForge/build.py."
            return
        }
        let spec = library.spec(for: prefs.machine)
        let snapshot = machine.snapshotSheet()
        machine.update(spec: spec)
        let rig = MachineRig(variants: variants, spec: spec, library: library)
        rig.onEvent = { [weak self] e in self?.event(e) }
        rig.setInk(machine.style)
        stage.install(rig)
        rig.updateMarginStops(left: machine.leftMargin, right: machine.rightMargin)
        rig.updateTabs(machine.tabs)
        director.engine.configure(voice(variants: variants, spec: spec))
        if let s = snapshot {
            Task { await rig.loadSheet(s, dpi: CGFloat(prefs.paperDPI)); rig.setPose(column: machine.column, feed: machine.feed) }
        } else {
            rig.setPose(column: machine.column, feed: -200)
        }
    }

    private func voice(variants: [ComponentKind: VariantManifest], spec: MachineSpec) -> MachineVoice {
        var v = MachineVoice()
        for (k, m) in variants {
            v.profiles[k] = SoundProfile(pitch: m.sound("pitch", 1), body: m.sound("body", 0.5), brightness: m.sound("brightness", 0.6),
                                         decay: m.sound("decay", 1), ring: m.sound("ring", 0.3))
        }
        if let bell = variants[.bell] {
            v.bellPartials = bell.mechanics["partials"].array?.compactMap { $0.array?.compactMap(\.double) } ?? v.bellPartials
            v.bellDispersion = bell.mechanics["dispersion"].double(0)
        }
        v.frameResonance = variants[.chassis]?.mechanics["frameResonance"].double(0.5) ?? 0.5
        v.platenHardness = variants[.carriage]?.mechanics["platenHardness"].double(0.75) ?? 0.75
        v.paperHardness = prefs.paper.hardness
        v.powerReturn = spec.powerReturn
        v.musicBoxRecorder = variants[.recorder]?.mechanics["plucksComb"].bool ?? false
        return v
    }

    // MARK: - notes & sheets

    /// Rolls the note's current sheet into the machine.
    func open(note: Note) {
        commitSheet()
        noteID = note.id
        clearSelection()
        let sheet = note.sheets[min(note.currentSheet, note.sheets.count - 1)]
        insert(sheet)
    }

    func closeNote() {
        commitSheet()
        noteID = nil
        perform(.eject)
        Task { await stage.rig?.loadSheet(nil, dpi: 300) }
    }

    private func insert(_ sheet: Sheet) {
        guard let rig = stage.rig else { return }
        Task {
            if machine.paperInserted {
                rig.play(machine.perform(.eject))
                try? await Task.sleep(nanoseconds: 1_100_000_000)
            }
            let startColumn = machine.column
            let events = machine.perform(.insert(sheet))
            await rig.loadSheet(sheet, dpi: CGFloat(prefs.paperDPI))
            rig.setPose(column: startColumn, feed: -60)
            rig.updateSheetStyles(sheet.styles)
            rig.play(events)
            syncHUD()
        }
    }

    /// Feeds a fresh sheet of the current paper into the open note.
    func newSheet() {
        guard var note = currentNote() else { return }
        commitSheet()
        note = currentNote() ?? note
        var sheet = Sheet(paper: prefs.paper, lineHeight: machine.lineHeightPoints)
        sheet.carriageColumn = machine.leftMargin
        note.sheets.append(sheet)
        note.currentSheet = note.sheets.count - 1
        store?.update(note)
        sheet = note.sheets[note.currentSheet]
        insert(sheet)
    }

    func showSheet(_ index: Int) {
        guard var note = currentNote(), note.sheets.indices.contains(index), index != note.currentSheet else { return }
        commitSheet()
        note = currentNote() ?? note
        note.currentSheet = index
        store?.update(note, touch: false)
        clearSelection()
        insert(note.sheets[index])
    }

    private func currentNote() -> Note? { store?.note(noteID) }

    /// Writes the sheet in the machine back into its note.
    func commitSheet() {
        guard var note = currentNote(), let sheet = machine.snapshotSheet(),
              let i = note.sheets.firstIndex(where: { $0.id == sheet.id }) else { return }
        note.sheets[i] = sheet
        store?.update(note)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            if Task.isCancelled { return }
            self?.commitSheet()
        }
    }

    var sheetImage: CGImage? { stage.rig?.sheetSnapshot }

    // MARK: - performing

    @discardableResult
    private func perform(_ action: MachineAction, delay: Double = 0) -> [TimedEvent] {
        let events = machine.perform(action)
        if let styles = machine.snapshotSheet()?.styles { stage.rig?.updateSheetStyles(styles) }
        stage.rig?.play(events, delay: delay)
        syncHUD()
        if !events.isEmpty { scheduleSave() }
        return events
    }

    private func event(_ e: MachineEvent) {
        director.carriagePan = Float((Double(machine.column) / Double(max(machine.maxColumn, 1))) * -1.6 + 0.8)
        director.handle(e)
        switch e {
        case .paperEnd:
            if prefs.machineSettings.autoFeedSheets && !autoTyping { newSheet() }
        case let .springLevel(l), let .springWind(l):
            springLevel = l
        default: break
        }
    }

    private func syncHUD() {
        column = machine.column
        leftMargin = machine.leftMargin
        rightMargin = machine.rightMargin
        lineSpacing = machine.lineSpacing
        hasPaper = machine.paperInserted
        secondColor = machine.useSecondColor
        springLevel = machine.recorder.spring / machine.recorder.capacity
    }

    // MARK: - keyboard

    private func keyID(for keyCode: UInt16) -> String? {
        if let k = KeyboardLayout.byKeyCode[keyCode] { return k.id }
        if let b = KeyboardLayout.borrowed[keyCode] { return b }
        if let f = KeyboardLayout.functionKeyCodes[keyCode] { return f.rawValue }
        return nil
    }

    private func keyDown(_ e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.command) { return false }
        if mods.contains(.control) {
            guard prefs.controlClipboard else { return false }
            switch (e.charactersIgnoringModifiers ?? "").lowercased() {
            case "c": copy(); return true
            case "x": cut(); return true
            case "v": paste(); return true
            case "a": selectAll(); return true
            default: return false
            }
        }
        if autoTyping {
            if e.keyCode == 53 { stopAutoTyping() }
            return true
        }
        let repeatable: Set<UInt16> = [51, 49, 123, 124, 125, 126, 117]
        if e.isARepeat && !repeatable.contains(e.keyCode) { return true }
        if !e.isARepeat, let id = keyID(for: e.keyCode) {
            heldKeys.insert(e.keyCode)
            stage.rig?.press(key: id, down: true)
            director.keyDown(isSpace: e.keyCode == 49)
        }
        let shiftSel = mods.contains(.shift)
        switch e.keyCode {
        case 36, 76: clearSelection(); perform(.carriageReturn)
        case 48: perform(.tab)
        case 51:
            clearSelection()
            perform(mods.contains(.option) ? .backspace : .erase)
        case 117:
            let key = SheetText.key(for: machine.feed, column: machine.column, halfLine: machine.lineHeightPoints / 2)
            perform(.correct(key))
        case 49: perform(.space)
        case 53: clearSelection()
        case 123: shiftSel ? extendSelection(dx: -1, dy: 0) : perform(.backspace)
        case 124: shiftSel ? extendSelection(dx: 1, dy: 0) : perform(.space)
        case 125:
            if shiftSel { extendSelection(dx: 0, dy: 2) } else { perform(.rollPlaten(lines: mods.contains(.option) ? 0.5 : 1)) }
        case 126:
            if shiftSel { extendSelection(dx: 0, dy: -2) } else { perform(.rollPlaten(lines: mods.contains(.option) ? -0.5 : -1)) }
        default:
            guard let chars = e.characters, let ch = chars.first, !chars.isEmpty else { return false }
            let s = String(ch)
            if s.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) }) { return false }
            clearSelection()
            let id = keyID(for: e.keyCode)
            perform(.type(s, keyID: KeyboardLayout.byID[id ?? ""] != nil ? id : nil))
        }
        return true
    }

    private func keyUp(_ e: NSEvent) {
        guard heldKeys.remove(e.keyCode) != nil, let id = keyID(for: e.keyCode) else { return }
        stage.rig?.press(key: id, down: false)
        director.keyUp()
    }

    private func flags(_ e: NSEvent) {
        let mods = e.modifierFlags
        switch e.keyCode {
        case 56, 60:
            let down = mods.contains(.shift)
            stage.rig?.press(key: e.keyCode == 56 ? FunctionKey.shiftLeft.rawValue : FunctionKey.shiftRight.rawValue, down: down)
            perform(.shift(down))
        case 57:
            stage.rig?.press(key: FunctionKey.shiftLock.rawValue, down: mods.contains(.capsLock))
            if mods.contains(.capsLock) != machine.shiftLocked { perform(.shiftLock) }
        case 58, 61:
            let down = mods.contains(.option)
            stage.rig?.press(key: FunctionKey.marginRelease.rawValue, down: down)
            perform(.marginRelease(down))
        default: break
        }
    }

    // MARK: - menu actions

    func carriageReturn() { perform(.carriageReturn) }
    func setLeftMargin() { perform(.setLeftMargin) }
    func setRightMargin() { perform(.setRightMargin) }
    func setMargins(left: Int, right: Int) { perform(.setMargins(left: left, right: right)) }
    func toggleTab() { perform(.toggleTabStop) }
    func clearTabs() { perform(.clearTabs) }
    func cycleLineSpacing() { perform(.cycleLineSpacing) }
    func toggleRibbonColor() { perform(.toggleRibbonColor) }

    func ejectSheet() {
        commitSheet()
        perform(.eject)
    }

    // MARK: - selection (mouse + shift-arrows)

    private func cellKey(at p: CGPoint) -> CellKey {
        let col = max(0, Int(p.x / machine.pitchPoints))
        let half = machine.lineHeightPoints / 2
        // the click is somewhere on the glyph body; the baseline sits a bit lower
        let line = Int(((p.y + machine.lineHeightPoints * 0.3) / half).rounded())
        return CellKey(line: line, column: col)
    }

    private func mouse(_ e: NSEvent, view: StageView) {
        guard let rig = stage.rig, let ray = view.worldRay(windowPoint: e.locationInWindow),
              let p = rig.pagePoint(rayOrigin: ray.0, direction: ray.1) else {
            if e.type == .leftMouseDown { clearSelection() }
            return
        }
        let key = cellKey(at: p)
        switch e.type {
        case .leftMouseDown:
            dragMoved = false
            if e.clickCount == 2, let sheet = machine.snapshotSheet(), let word = sheet.text.wordRange(around: key) {
                selAnchor = word.0; selHead = word.1
                updateSelection()
                dragMoved = true
                return
            }
            if e.clickCount == 3 {
                selAnchor = CellKey(line: key.line, column: 0); selHead = CellKey(line: key.line, column: machine.maxColumn)
                updateSelection()
                dragMoved = true
                return
            }
            selAnchor = key; selHead = key
            updateSelection(highlight: false)
        case .leftMouseDragged:
            dragMoved = true
            selHead = key
            updateSelection()
        case .leftMouseUp:
            if !dragMoved {
                // A click positions the carriage and platen at that spot.
                clearSelection()
                moveTo(key)
            }
        default: break
        }
    }

    private func moveTo(_ key: CellKey) {
        let targetFeed = Double(key.line) * machine.lineHeightPoints / 2
        let lines = (targetFeed - machine.feed) / machine.lineHeightPoints
        if abs(lines) > 0.01 { perform(.rollPlaten(lines: lines)) }
        perform(.moveCarriage(to: key.column), delay: 0.1)
    }

    private func extendSelection(dx: Int, dy: Int) {
        if selAnchor == nil {
            let k = SheetText.key(for: machine.feed, column: machine.column, halfLine: machine.lineHeightPoints / 2)
            selAnchor = CellKey(line: k.line, column: dx < 0 ? k.column - 1 : k.column)
            selHead = selAnchor
        }
        if var h = selHead {
            h.column = max(0, min(machine.maxColumn, h.column + dx))
            h.line += dy
            selHead = h
        }
        updateSelection()
    }

    private var orderedSelection: (CellKey, CellKey)? {
        guard let a = selAnchor, let b = selHead else { return nil }
        return a <= b ? (a, b) : (b, a)
    }

    private func updateSelection(highlight: Bool = true) {
        guard highlight, let range = orderedSelection, let sheet = machine.snapshotSheet() else {
            stage.rig?.setSelection([])
            selectionLength = 0
            return
        }
        let (a, b) = range
        let text = sheet.text
        selectionLength = text.text(from: a, to: b).count
        let half = machine.lineHeightPoints / 2
        let pitch = machine.pitchPoints
        var rects: [CGRect] = []
        let lines = Set(text.sortedKeys.filter { $0 >= a && $0 <= b }.map(\.line)).union([a.line, b.line])
        for line in lines.sorted() {
            let c0 = line == a.line ? a.column : text.sortedKeys.filter { $0.line == line }.map(\.column).min() ?? 0
            let c1 = line == b.line ? b.column : text.sortedKeys.filter { $0.line == line }.map(\.column).max() ?? c0
            guard c1 >= c0 else { continue }
            let baseline = Double(line) * half
            rects.append(CGRect(x: Double(c0) * pitch, y: baseline - machine.lineHeightPoints * 0.78,
                                width: Double(c1 - c0 + 1) * pitch, height: machine.lineHeightPoints))
        }
        stage.rig?.setSelection(rects)
    }

    func clearSelection() {
        selAnchor = nil
        selHead = nil
        selectionLength = 0
        stage.rig?.setSelection([])
    }

    func selectAll() {
        guard let sheet = machine.snapshotSheet(), let first = sheet.text.sortedKeys.first, let last = sheet.text.sortedKeys.last else { return }
        selAnchor = first
        selHead = last
        updateSelection()
    }

    // MARK: - mechanical clipboard

    private func selectedText() -> String? {
        guard let range = orderedSelection, let sheet = machine.snapshotSheet() else { return nil }
        let t = sheet.text.text(from: range.0, to: range.1)
        return t.isEmpty ? nil : t
    }

    /// Copy: the recorder rewinds its journal to the selection and the
    /// duplicating punch copies it onto the clip loop.
    func copy() {
        guard let text = selectedText() else { NSSound.beep(); return }
        stage.rig?.clearClipLoop()
        stage.rig?.play(machine.copy(text))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        status = "Copied \(text.count) characters to the clip loop"
    }

    /// Cut: copy, then the carriage walks back over the selection and strikes
    /// every character again through the correction tape.
    func cut() {
        guard let range = orderedSelection, let sheet = machine.snapshotSheet() else { NSSound.beep(); return }
        let a = range.0
        copy()
        let cells = sheet.text.cells(from: range.0, to: range.1)
        clearSelection()
        guard !cells.isEmpty else { return }
        runAutomation { controller in
            try await controller.wait(0.6)
            for cell in cells {
                try Task.checkCancellation()
                let ev = controller.perform(.correct(cell.key))
                try await controller.wait((ev.map(\.at).max() ?? 0) + 0.03)
            }
            // leave the carriage where the cut began, ready for Paste
            controller.moveTo(a)
        }
    }

    /// Paste: the spring motor pulls the clip loop over the reading needles,
    /// each frame trips a typebar latch.
    func paste() {
        var text = machine.recorder.clipText
        if let board = NSPasteboard.general.string(forType: .string), board != text {
            // External text arrives over the teleprinter line and is punched first.
            text = board
            stage.rig?.clearClipLoop()
            stage.rig?.play(machine.copy(board))
        }
        guard !text.isEmpty else { NSSound.beep(); return }
        clearSelection()
        let cps = machine.spec.recorderCPS
        runAutomation { controller in
            try await controller.wait(0.4)
            for ch in text {
                try Task.checkCancellation()
                if !controller.machine.consumeSpring() {
                    controller.status = "Winding the recorder spring…"
                    controller.stage.rig?.play(controller.machine.rewindSpring())
                    try await controller.wait(0.8)
                    controller.status = nil
                    _ = controller.machine.consumeSpring()
                }
                controller.springLevel = controller.machine.recorder.spring / controller.machine.recorder.capacity
                for byte in String(ch).utf8 { controller.stage.rig?.play([TimedEvent(0, .tapeRead(byte: byte))]) }
                let ev: [TimedEvent]
                switch ch {
                case "\n", "\r", "\r\n": ev = controller.perform(.carriageReturn)
                case "\t": ev = controller.perform(.tab)
                case " ": ev = controller.perform(.space)
                default: ev = controller.perform(.type(String(ch), keyID: nil))
                }
                let mechanical = ev.map(\.at).max() ?? 0
                try await controller.wait(max(1 / cps, ch.isNewline ? mechanical + 0.05 : 0))
            }
        }
    }

    private func runAutomation(_ body: @escaping @MainActor (MachineController) async throws -> Void) {
        autoTask?.cancel()
        autoTyping = true
        autoTask = Task { [weak self] in
            guard let self = self else { return }
            do { try await body(self) } catch {}
            self.autoTyping = false
            self.status = nil
            self.commitSheet()
        }
    }

    func stopAutoTyping() {
        autoTask?.cancel()
        autoTyping = false
    }

    private func wait(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }

    /// Re-renders the sheet with the current paper (used from the paper editor).
    func restyleCurrentSheet(paper: PaperStyle) {
        guard var note = currentNote(), var sheet = machine.snapshotSheet(),
              let i = note.sheets.firstIndex(where: { $0.id == sheet.id }) else { return }
        sheet.paper = paper
        note.sheets[i] = sheet
        store?.update(note)
        insert(sheet)
    }
}

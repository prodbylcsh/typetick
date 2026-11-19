import Foundation

/// Something the machine physically does. The scene animates it, the audio
/// engine voices it. `TimedEvent.at` is seconds after the action started.
public enum MachineEvent: Sendable, Equatable {
    case typebar(slot: Int, keyID: String)
    case vibratorLift(up: Bool)
    case strike(Strike)                         // ink (or correction) reaches the paper
    case platenImpact(force: Double)            // the blow shakes paper and platen
    case escapement(from: Int, to: Int)         // carriage steps one tooth
    case carriageMove(from: Int, to: Int, duration: Double, kind: CarriageMoveKind)
    case carriageStop(force: Double)            // carriage hits a margin or tab stop
    case platenRoll(fromFeed: Double, toFeed: Double, clicks: Int, duration: Double)
    case returnLever(phase: LeverPhase)
    case bell
    case marginLock
    case shift(down: Bool)
    case ribbonAdvance(amount: Double)
    case correctionLift(up: Bool)
    case bail(lifted: Bool)
    case releaseLever(open: Bool)
    case paperIn(sheetID: UUID)
    case paperOut(sheetID: UUID)
    case paperEnd
    case marginSet(left: Int, right: Int)
    case tabsChanged([Int])
    case tapePunch(bytes: [UInt8])              // journal tape records a keystroke
    case tapeSeek(frames: Int)                  // reader sled travels (negative = rewind)
    case clipPunch(bytes: [UInt8])              // duplicating punch writes the clip loop
    case tapeRead(byte: UInt8)                  // reader needles sense a frame
    case springWind(level: Double)
    case springLevel(Double)
    case motorRun(duration: Double)             // power return / recorder motor
}

public enum CarriageMoveKind: String, Sendable { case space, backspace, tab, carriageReturn, direct }
public enum LeverPhase: String, Sendable { case push, release }

public struct TimedEvent: Sendable, Equatable {
    public var at: Double
    public var event: MachineEvent
    public init(_ at: Double, _ event: MachineEvent) { self.at = at; self.event = event }
}

public enum MachineAction: Sendable {
    case type(String, keyID: String?)
    case space
    case backspace
    case erase                      // backspace + correction strike over what is there
    case correct(CellKey)           // move to a cell and cover it (used by Cut)
    case carriageReturn
    case lineFeed
    case reverseLine
    case rollPlaten(lines: Double)
    case tab
    case setLeftMargin
    case setRightMargin
    case setMargins(left: Int, right: Int)
    case toggleTabStop
    case clearTabs
    case moveCarriage(to: Int)
    case shift(Bool)
    case shiftLock
    case marginRelease(Bool)
    case cycleLineSpacing
    case toggleRibbonColor
    case insert(Sheet)
    case eject
}

/// Mechanical clipboard: an endless journal tape that records every keystroke
/// as UTF-8 frames, plus a short clip loop the duplicating punch copies onto.
public struct Recorder: Sendable {
    public var journal: [UInt8] = []
    public var clipLoop: [UInt8] = []
    public var spring: Double
    public let capacity: Double
    public static let journalWindow = 4096

    public init(capacity: Int) {
        self.capacity = Double(capacity)
        spring = Double(capacity) * 0.6
    }

    public var clipText: String { String(decoding: clipLoop, as: UTF8.self) }

    public mutating func punch(_ bytes: [UInt8]) {
        journal.append(contentsOf: bytes)
        if journal.count > Recorder.journalWindow { journal.removeFirst(journal.count - Recorder.journalWindow) }
    }
}

public struct MachineSettings: Codable, Hashable, Sendable {
    /// When the carriage locks at the right margin, return automatically
    /// instead of jamming (bell still rings).
    public var autoReturn = true
    /// Insert a fresh sheet when the page runs out.
    public var autoFeedSheets = true
    public init() {}
}

/// The mechanical state of the typewriter. Every action mutates the state
/// immediately and returns the physical events that make it happen.
public final class TypewriterMachine {
    public private(set) var spec: MachineSpec
    public var settings = MachineSettings()
    public private(set) var sheet: Sheet?
    public private(set) var column: Int
    /// Baseline (points from top of sheet) currently on the printing line.
    public private(set) var feed: Double
    public private(set) var leftMargin: Int
    public private(set) var rightMargin: Int
    public private(set) var tabs: [Int]
    public private(set) var shiftDown = false
    public private(set) var shiftLocked = false
    public private(set) var marginReleased = false
    public private(set) var lineSpacing: Double = 1
    public private(set) var useSecondColor = false
    public var recorder: Recorder
    public var style: StrikeStyle
    private var rng = SplitMix64(seed: 0x7E57_71C4)

    public init(spec: MachineSpec, style: StrikeStyle) {
        self.spec = spec
        self.style = style
        column = spec.defaultLeftMargin
        feed = -1000
        leftMargin = spec.defaultLeftMargin
        rightMargin = spec.defaultRightMargin
        tabs = spec.defaultTabs
        recorder = Recorder(capacity: spec.springCapacity)
    }

    public func update(spec newSpec: MachineSpec) {
        let ratio = newSpec.pitch > 0 ? spec.pitch / newSpec.pitch : 1
        spec = newSpec
        if abs(ratio - 1) > 0.01 {
            column = Int((Double(column) * ratio).rounded())
            leftMargin = Int((Double(leftMargin) * ratio).rounded())
            rightMargin = Int((Double(rightMargin) * ratio).rounded())
            tabs = tabs.map { Int((Double($0) * ratio).rounded()) }
        }
        column = min(column, maxColumn)
        rightMargin = min(rightMargin, maxColumn)
    }

    // MARK: derived

    public var pitchPoints: Double { spec.pitchPoints }
    public var lineHeightPoints: Double { spec.lineHeightPoints }
    public var pageWidth: Double { sheet?.pageSize.width ?? PaperSize.letter.points.width }
    public var pageHeight: Double { sheet?.pageSize.height ?? PaperSize.letter.points.height }
    public var maxColumn: Int { spec.columns(forPageWidth: pageWidth) }
    public var paperInserted: Bool { sheet != nil }
    public var currentLineKey: Int { Int((feed / (lineHeightPoints / 2)).rounded()) }
    public var bellColumn: Int { rightMargin - spec.bellOffsetColumns }
    public var shifted: Bool { shiftDown || shiftLocked }

    /// Hand the sheet back (for saving) without ejecting it.
    public func snapshotSheet() -> Sheet? {
        guard var s = sheet else { return nil }
        s.carriageColumn = column
        s.feed = feed
        return s
    }

    // MARK: actions

    @discardableResult
    public func perform(_ action: MachineAction) -> [TimedEvent] {
        switch action {
        case let .type(ch, keyID): return type(ch, keyID: keyID)
        case .space: return space()
        case .backspace: return backspace()
        case .erase: return erase()
        case let .correct(key): return correct(key)
        case .carriageReturn: return carriageReturn()
        case .lineFeed: return roll(lines: lineSpacing, lever: true)
        case .reverseLine: return roll(lines: -1, lever: false)
        case let .rollPlaten(lines): return roll(lines: lines, lever: false)
        case .tab: return tab()
        case .setLeftMargin:
            leftMargin = min(column, rightMargin - 5)
            return [TimedEvent(0, .marginSet(left: leftMargin, right: rightMargin))]
        case .setRightMargin:
            rightMargin = max(column, leftMargin + 5)
            return [TimedEvent(0, .marginSet(left: leftMargin, right: rightMargin))]
        case let .setMargins(l, r):
            leftMargin = max(0, min(l, maxColumn - 5))
            rightMargin = max(leftMargin + 5, min(r, maxColumn))
            return [TimedEvent(0, .marginSet(left: leftMargin, right: rightMargin))]
        case .toggleTabStop:
            if let i = tabs.firstIndex(of: column) { tabs.remove(at: i) } else { tabs.append(column); tabs.sort() }
            return [TimedEvent(0, .tabsChanged(tabs))]
        case .clearTabs:
            tabs.removeAll()
            return [TimedEvent(0, .tabsChanged(tabs))]
        case let .moveCarriage(to): return moveCarriage(to: to, kind: .direct)
        case let .shift(down):
            guard down != shiftDown else { return [] }
            shiftDown = down
            if shiftLocked { return [] }
            return [TimedEvent(0, .shift(down: down))]
        case .shiftLock:
            shiftLocked.toggle()
            return shiftDown ? [] : [TimedEvent(0, .shift(down: shiftLocked))]
        case let .marginRelease(on):
            marginReleased = on
            return []
        case .cycleLineSpacing:
            let opts = spec.lineSpacingOptions.isEmpty ? [1] : spec.lineSpacingOptions
            let i = opts.firstIndex(of: lineSpacing) ?? -1
            lineSpacing = opts[(i + 1) % opts.count]
            return [TimedEvent(0, .returnLever(phase: .release))]
        case .toggleRibbonColor:
            useSecondColor.toggle()
            return [TimedEvent(0, .vibratorLift(up: false))]
        case let .insert(s): return insert(s)
        case .eject: return eject()
        }
    }

    // MARK: typing

    private func strikeEvents(char: String, keyID: String?, kind: StrikeKind, at start: Double) -> (events: [TimedEvent], strike: Strike?) {
        let key = keyID.flatMap { KeyboardLayout.byID[$0] } ?? KeyboardLayout.key(for: char)
        let slot = KeyboardLayout.slotIndex[key.id] ?? 0
        var ev: [TimedEvent] = []
        let swing = spec.typebarSwing
        ev.append(TimedEvent(start, .typebar(slot: slot, keyID: key.id)))
        if kind == .ink {
            ev.append(TimedEvent(start + swing * 0.35, .vibratorLift(up: true)))
            ev.append(TimedEvent(start + swing + spec.typebarReturn * 0.5, .vibratorLift(up: false)))
        } else {
            ev.append(TimedEvent(start, .correctionLift(up: true)))
            ev.append(TimedEvent(start + swing + spec.typebarReturn, .correctionLift(up: false)))
        }
        var made: Strike? = nil
        if var s = sheet, column >= 0, column <= maxColumn, feed > -lineHeightPoints, feed < pageHeight + lineHeightPoints {
            let pressure = spec.impactForce * (0.82 + 0.3 * rng.nextUnit())
            var st = style
            st.useSecondColor = useSecondColor && spec.twoColorRibbon
            let styleIdx = s.styleIndex(for: st)
            let x = Double(column) * pitchPoints
            let seed = UInt32(truncatingIfNeeded: rng.next())
            let strike = s.append { id in
                Strike(id: id, character: char, column: column, x: x, baseline: feed, pitch: pitchPoints, style: styleIdx,
                       kind: kind, pressure: pressure, seed: seed)
            }
            sheet = s
            made = strike
            ev.append(TimedEvent(start + swing, .strike(strike)))
        }
        ev.append(TimedEvent(start + swing, .platenImpact(force: spec.impactForce)))
        if kind == .ink { ev.append(TimedEvent(start + swing + 0.01, .ribbonAdvance(amount: 1))) }
        return (ev, made)
    }

    private func type(_ char: String, keyID: String?) -> [TimedEvent] {
        var events: [TimedEvent] = []
        var t = 0.0
        if column >= rightMargin && !marginReleased {
            if settings.autoReturn {
                events += carriageReturn()
                t = (events.map(\.at).max() ?? 0) + 0.05
            } else {
                return [TimedEvent(0, .marginLock)]
            }
        }
        if column >= maxColumn { return events + [TimedEvent(t, .marginLock)] }
        let (ev, _) = strikeEvents(char: char, keyID: keyID, kind: .ink, at: t)
        events += ev
        events += advance(by: 1, at: t + spec.typebarSwing + spec.escapementSnap * 0.5)
        let bytes = Array(char.utf8)
        recorder.punch(bytes)
        events.append(TimedEvent(t + 0.004, .tapePunch(bytes: bytes)))
        return events
    }

    /// Escapement: the carriage moves one (or more) teeth to the left on the page.
    private func advance(by n: Int, at t: Double) -> [TimedEvent] {
        let from = column
        let to = min(column + n, maxColumn)
        column = to
        var ev = [TimedEvent(t, .escapement(from: from, to: to))]
        if from < bellColumn && to >= bellColumn && !marginReleased {
            ev.append(TimedEvent(t + 0.01, .bell))
        }
        return ev
    }

    private func space() -> [TimedEvent] {
        if column >= rightMargin && !marginReleased {
            return settings.autoReturn ? carriageReturn() : [TimedEvent(0, .marginLock)]
        }
        recorder.punch([0x20])
        return advance(by: 1, at: 0.03) + [TimedEvent(0.0, .tapePunch(bytes: [0x20]))]
    }

    private func backspace() -> [TimedEvent] {
        guard column > 0 else { return [TimedEvent(0, .carriageStop(force: 0.3))] }
        let from = column
        column -= 1
        recorder.punch([0x08])
        return [TimedEvent(0.02, .carriageMove(from: from, to: column, duration: 0.06, kind: .backspace)),
                TimedEvent(0, .tapePunch(bytes: [0x08]))]
    }

    /// Backspace, then strike the same character through the correction tape.
    private func erase() -> [TimedEvent] {
        var events = backspace()
        let key = SheetText.key(for: feed, column: column, halfLine: lineHeightPoints / 2)
        guard let sheet = sheet else { return events }
        let visible = SheetText(sheet: sheet).visibleCharacters(at: key)
        guard !visible.isEmpty else { return events }
        var t = 0.12
        for glyph in visible.reversed() {
            let (ev, _) = strikeEvents(char: glyph.character, keyID: nil, kind: correctionKind, at: t)
            events += ev
            t += spec.typebarSwing + spec.typebarReturn + 0.02
        }
        return events
    }

    private var correctionKind: StrikeKind { spec.correctionMode == .liftOff ? .liftOff : .coverUp }

    /// Travel to a cell and cover it (Cut).
    private func correct(_ key: CellKey) -> [TimedEvent] {
        var events: [TimedEvent] = []
        var t = 0.0
        let targetFeed = Double(key.line) * lineHeightPoints / 2
        if abs(targetFeed - feed) > 0.01 {
            let ev = roll(lines: (targetFeed - feed) / lineHeightPoints, lever: false)
            events += ev
            t = (ev.map(\.at).max() ?? 0) + 0.05
        }
        if key.column != column {
            let ev = moveCarriage(to: key.column, kind: .direct).map { TimedEvent($0.at + t, $0.event) }
            events += ev
            t = (ev.map(\.at).max() ?? t) + 0.04
        }
        guard let sheet = sheet else { return events }
        let visible = SheetText(sheet: sheet).visibleCharacters(at: key)
        for glyph in visible.reversed() {
            let (ev, _) = strikeEvents(char: glyph.character, keyID: nil, kind: correctionKind, at: t)
            events += ev
            t += spec.typebarSwing + spec.typebarReturn + 0.02
        }
        return events
    }

    // MARK: carriage

    private func moveCarriage(to target: Int, kind: CarriageMoveKind) -> [TimedEvent] {
        let to = max(0, min(target, maxColumn))
        let from = column
        guard to != from else { return [] }
        column = to
        let distance = Double(abs(to - from)) * spec.pitch
        let duration = max(0.05, distance / max(spec.returnSpeed, 0.1))
        return [TimedEvent(0, .carriageMove(from: from, to: to, duration: duration, kind: kind)),
                TimedEvent(duration, .carriageStop(force: min(1, distance * 6)))]
    }

    private func tab() -> [TimedEvent] {
        let next = tabs.first(where: { $0 > column }) ?? (column < rightMargin ? rightMargin : nil)
        guard let target = next else { return [TimedEvent(0, .marginLock)] }
        recorder.punch([0x09])
        let from = column
        var ev = moveCarriage(to: target, kind: .tab)
        if from < bellColumn && target >= bellColumn && !marginReleased { ev.append(TimedEvent(0.05, .bell)) }
        ev.append(TimedEvent(0, .tapePunch(bytes: [0x09])))
        return ev
    }

    public func carriageReturn() -> [TimedEvent] {
        var events: [TimedEvent] = [TimedEvent(0, .returnLever(phase: .push))]
        var t = 0.0
        if spec.powerReturn {
            events.append(TimedEvent(0.02, .motorRun(duration: 0.35)))
            t = 0.04
        }
        if spec.feedBeforeReturn || spec.powerReturn {
            events += roll(lines: lineSpacing, lever: true).map { TimedEvent($0.at + t, $0.event) }
            t += 0.09
        }
        let from = column
        column = leftMargin
        let distance = Double(abs(from - column)) * spec.pitch
        let duration = max(0.08, distance / max(spec.returnSpeed, 0.1))
        if from != column {
            events.append(TimedEvent(t, .carriageMove(from: from, to: column, duration: duration, kind: .carriageReturn)))
            events.append(TimedEvent(t + duration, .carriageStop(force: min(1, distance * 5))))
        }
        if !spec.feedBeforeReturn && !spec.powerReturn {
            events += roll(lines: lineSpacing, lever: true).map { TimedEvent($0.at + t + duration, $0.event) }
        }
        events.append(TimedEvent(t + duration + 0.05, .returnLever(phase: .release)))
        // Throwing the carriage winds the recorder spring.
        let wind = Double(from - column) * 0.5
        if wind > 0 {
            recorder.spring = min(recorder.capacity, recorder.spring + wind)
            events.append(TimedEvent(t, .springLevel(recorder.spring / recorder.capacity)))
        }
        recorder.punch([0x0D])
        events.append(TimedEvent(0, .tapePunch(bytes: [0x0D])))
        return events
    }

    private func roll(lines: Double, lever: Bool) -> [TimedEvent] {
        let from = feed
        feed += lines * lineHeightPoints
        let clicks = max(1, Int((abs(lines) * Double(spec.detentsPerLine)).rounded()))
        let duration = lever ? 0.08 : 0.05 * Double(clicks) / Double(max(spec.detentsPerLine, 1)) + 0.04
        var ev = [TimedEvent(0, .platenRoll(fromFeed: from, toFeed: feed, clicks: clicks, duration: duration))]
        if sheet != nil && feed > pageHeight - lineHeightPoints * 2 {
            ev.append(TimedEvent(duration, .paperEnd))
        }
        return ev
    }

    // MARK: paper

    private func insert(_ s: Sheet) -> [TimedEvent] {
        var events: [TimedEvent] = []
        var t = 0.0
        if sheet != nil {
            events += eject()
            t = (events.map(\.at).max() ?? 0) + 0.2
        }
        sheet = s
        let target = s.feed
        events.append(TimedEvent(t, .releaseLever(open: true)))
        events.append(TimedEvent(t + 0.12, .bail(lifted: true)))
        events.append(TimedEvent(t + 0.25, .paperIn(sheetID: s.id)))
        let start = -60.0
        feed = start
        events.append(TimedEvent(t + 0.3, .platenRoll(fromFeed: start, toFeed: target, clicks: Int((target - start) / lineHeightPoints) * spec.detentsPerLine,
                                                     duration: 0.9)))
        feed = target
        events.append(TimedEvent(t + 1.25, .releaseLever(open: false)))
        events.append(TimedEvent(t + 1.4, .bail(lifted: false)))
        let to = s.carriageColumn
        let mv = moveCarriage(to: to, kind: .carriageReturn).map { TimedEvent($0.at + t + 1.5, $0.event) }
        events += mv
        return events
    }

    private func eject() -> [TimedEvent] {
        guard let s = snapshotSheet() else { return [] }
        sheet = nil
        let from = feed
        feed = s.pageSize.height + 80
        return [TimedEvent(0, .bail(lifted: true)), TimedEvent(0.05, .releaseLever(open: true)),
                TimedEvent(0.1, .platenRoll(fromFeed: from, toFeed: feed, clicks: 24, duration: 0.7)),
                TimedEvent(0.8, .paperOut(sheetID: s.id)),
                TimedEvent(0.9, .releaseLever(open: false)), TimedEvent(1.0, .bail(lifted: false))]
    }

    // MARK: recorder (clipboard)

    /// Copy: the reader sled rewinds the journal to the selection while the
    /// duplicating punch copies the frames onto the clip loop.
    public func copy(_ text: String) -> [TimedEvent] {
        let bytes = Array(text.utf8)
        recorder.clipLoop = bytes
        let rewind = min(Recorder.journalWindow, max(bytes.count, 8))
        var ev: [TimedEvent] = [TimedEvent(0, .tapeSeek(frames: -rewind))]
        let per = 0.012
        for (i, chunk) in stride(from: 0, to: bytes.count, by: 4).enumerated() {
            let part = Array(bytes[chunk..<min(chunk + 4, bytes.count)])
            ev.append(TimedEvent(0.25 + Double(i) * per * 4, .clipPunch(bytes: part)))
        }
        ev.append(TimedEvent(0.3 + Double(bytes.count) * per, .tapeSeek(frames: rewind)))
        return ev
    }

    public func consumeSpring() -> Bool {
        if recorder.spring >= 1 {
            recorder.spring -= 1
            return true
        }
        return false
    }

    public func rewindSpring() -> [TimedEvent] {
        recorder.spring = recorder.capacity
        return [TimedEvent(0, .springWind(level: 1))]
    }
}

/// Small deterministic RNG so strikes look the same every time a sheet renders.
public struct SplitMix64: Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    public mutating func nextUnit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

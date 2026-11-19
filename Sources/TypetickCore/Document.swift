import Foundation

/// 1 inch = 72 points; the page model works in points, the 3D scene in meters.
public enum Units {
    public static let metersPerPoint = 0.0254 / 72.0
    public static func points(_ meters: Double) -> Double { meters / metersPerPoint }
    public static func meters(_ points: Double) -> Double { points * metersPerPoint }
}

public enum StrikeKind: String, Codable, Sendable {
    /// Ribbon ink.
    case ink
    /// Chalk/film tape deposited over earlier ink.
    case coverUp
    /// Adhesive tape that lifted earlier ink off (leaves a faint ghost).
    case liftOff
}

/// One impact of a type slug on the sheet.
public struct Strike: Codable, Hashable, Identifiable, Sendable {
    public var id: UInt32
    public var character: String
    public var column: Int
    /// Left edge of the character cell, points from the left paper edge.
    public var x: Double
    /// Baseline, points from the top paper edge.
    public var baseline: Double
    /// Width of the character cell (escapement pitch) in points.
    public var pitch: Double
    /// Index into `Sheet.styles`.
    public var style: Int
    public var kind: StrikeKind
    /// Relative strike force (heavier = darker and deeper impression).
    public var pressure: Double
    /// Deterministic per-strike randomness (jitter, ink texture).
    public var seed: UInt32
    public var date: Date

    public init(id: UInt32, character: String, column: Int, x: Double, baseline: Double, pitch: Double, style: Int,
                kind: StrikeKind, pressure: Double, seed: UInt32, date: Date = Date()) {
        self.id = id; self.character = character; self.column = column; self.x = x; self.baseline = baseline
        self.pitch = pitch; self.style = style; self.kind = kind; self.pressure = pressure; self.seed = seed; self.date = date
    }
}

/// A physical sheet of paper and everything that was ever struck on it.
public struct Sheet: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var created: Date
    public var paper: PaperStyle
    public var styles: [StrikeStyle]
    public var strikes: [Strike]
    public var nextStrikeID: UInt32
    /// Where the carriage and platen were when the sheet was last in the machine.
    public var carriageColumn: Int
    /// Baseline (points from top) sitting on the printing line.
    public var feed: Double
    public var lineHeight: Double

    public init(paper: PaperStyle, lineHeight: Double = 12, topMargin: Double = 72) {
        id = UUID()
        created = Date()
        self.paper = paper
        styles = []
        strikes = []
        nextStrikeID = 1
        carriageColumn = 10
        feed = topMargin
        self.lineHeight = lineHeight
    }

    public var pageSize: (width: Double, height: Double) { paper.size.points }

    public mutating func styleIndex(for style: StrikeStyle) -> Int {
        if let i = styles.firstIndex(of: style) { return i }
        styles.append(style)
        return styles.count - 1
    }

    public mutating func append(_ make: (UInt32) -> Strike) -> Strike {
        let s = make(nextStrikeID)
        nextStrikeID &+= 1
        strikes.append(s)
        return s
    }

    public var text: SheetText { SheetText(sheet: self) }
}

/// A note is a stack of sheets.
public struct Note: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var created: Date
    public var modified: Date
    public var sheets: [Sheet]
    public var currentSheet: Int
    public var pinned: Bool
    public var customTitle: String?

    public init(paper: PaperStyle) {
        id = UUID()
        created = Date()
        modified = created
        sheets = [Sheet(paper: paper)]
        currentSheet = 0
        pinned = false
    }

    public var plainText: String {
        sheets.map { $0.text.plainText() }.joined(separator: "\n\u{000C}\n")
    }

    public var title: String {
        if let t = customTitle, !t.isEmpty { return t }
        for sheet in sheets {
            for line in sheet.text.plainText().split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { return String(trimmed.prefix(60)) }
            }
        }
        return "Blank Sheet"
    }

    public var excerpt: String {
        let lines = plainText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.dropFirst().prefix(3).joined(separator: " ")
    }
}

// MARK: - Reading text back off the paper

/// Grid position used to read text: `line` is in half-line units so that
/// half-line rolls (super/subscripts) stay distinguishable.
public struct CellKey: Hashable, Comparable, Codable, Sendable {
    public var line: Int
    public var column: Int
    public init(line: Int, column: Int) { self.line = line; self.column = column }
    public static func < (a: CellKey, b: CellKey) -> Bool {
        a.line != b.line ? a.line < b.line : a.column < b.column
    }
}

public struct TextCell: Hashable, Sendable {
    public var key: CellKey
    /// Glyphs still visible in this cell (overstrikes compose).
    public var visible: [Strike]
    /// Every strike that landed here, including corrected ones.
    public var history: [Strike]
    public var string: String { visible.map(\.character).joined().precomposedStringWithCanonicalMapping }
    public var isEmpty: Bool { visible.isEmpty }
}

public struct SheetText: Sendable {
    public let cells: [CellKey: TextCell]
    public let sortedKeys: [CellKey]
    public let halfLine: Double

    public init(sheet: Sheet) {
        halfLine = sheet.lineHeight / 2
        var map: [CellKey: TextCell] = [:]
        for s in sheet.strikes.sorted(by: { $0.id < $1.id }) {
            let key = SheetText.key(for: s.baseline, column: s.column, halfLine: sheet.lineHeight / 2)
            var cell = map[key] ?? TextCell(key: key, visible: [], history: [])
            cell.history.append(s)
            switch s.kind {
            case .ink:
                cell.visible.append(s)
            case .coverUp, .liftOff:
                // Correction removes the glyph it was struck with (or everything if unspecified).
                if let i = cell.visible.lastIndex(where: { $0.character == s.character }) {
                    cell.visible.remove(at: i)
                } else {
                    cell.visible.removeAll()
                }
            }
            map[key] = cell
        }
        cells = map
        sortedKeys = map.keys.filter { !(map[$0]?.isEmpty ?? true) }.sorted()
    }

    public static func key(for baseline: Double, column: Int, halfLine: Double) -> CellKey {
        CellKey(line: Int((baseline / halfLine).rounded()), column: column)
    }

    public func visibleCharacters(at key: CellKey) -> [Strike] { cells[key]?.visible ?? [] }

    public var minColumn: Int { sortedKeys.map(\.column).min() ?? 0 }

    public func plainText() -> String { text(from: nil, to: nil) }

    /// Text between two positions in reading order (inclusive), with spaces for
    /// untouched cells and newlines between lines.
    public func text(from start: CellKey?, to end: CellKey?) -> String {
        let keys = sortedKeys.filter { k in
            (start.map { k >= $0 } ?? true) && (end.map { k <= $0 } ?? true)
        }
        guard !keys.isEmpty else { return "" }
        let base = start?.column ?? minColumn
        var out = ""
        var lineKey: Int? = nil
        var col = 0
        for k in keys {
            if lineKey != k.line {
                if let prev = lineKey {
                    let gap = max(1, Int((Double(k.line - prev) / 2).rounded()))
                    out += String(repeating: "\n", count: gap)
                    col = min(base, minColumn)
                } else {
                    col = start != nil ? base : minColumn
                }
                lineKey = k.line
            }
            if k.column > col { out += String(repeating: " ", count: k.column - col) }
            out += cells[k]?.string ?? ""
            col = k.column + 1
        }
        return out
    }

    /// Visible cells inside a selection, in reading order.
    public func cells(from start: CellKey, to end: CellKey) -> [TextCell] {
        let a = min(start, end), b = max(start, end)
        return sortedKeys.filter { $0 >= a && $0 <= b }.compactMap { cells[$0] }
    }

    public func wordRange(around key: CellKey) -> (CellKey, CellKey)? {
        let line = sortedKeys.filter { $0.line == key.line }
        guard !line.isEmpty else { return nil }
        let isWord: (CellKey) -> Bool = { k in
            guard let c = cells[k] else { return false }
            return c.string.rangeOfCharacter(from: .whitespaces) == nil && !c.isEmpty
        }
        var lo = key.column, hi = key.column
        let cols = Set(line.filter(isWord).map(\.column))
        guard cols.contains(key.column) else { return nil }
        while cols.contains(lo - 1) { lo -= 1 }
        while cols.contains(hi + 1) { hi += 1 }
        return (CellKey(line: key.line, column: lo), CellKey(line: key.line, column: hi))
    }
}

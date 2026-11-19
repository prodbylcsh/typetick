import Foundation

/// One printing key on the machine: a key lever and its typebar.
public struct TypeKey: Hashable, Sendable, Identifiable {
    public let id: String          // unique id, the unshifted legend
    public let lower: String
    public let upper: String
    public let row: Int            // 0 = front row
    public let index: Int          // position in its row
    public let keyCode: UInt16     // macOS virtual key code (ANSI position)
}

/// Function keys that exist on the machine but have no typebar.
public enum FunctionKey: String, CaseIterable, Sendable {
    case shiftLeft, shiftRight, shiftLock, tab, backspace, marginRelease, space

    public var legend: String {
        switch self {
        case .shiftLeft, .shiftRight: return "SHIFT"
        case .shiftLock: return "LOCK"
        case .tab: return "TAB"
        case .backspace: return "BACK"
        case .marginRelease: return "MAR"
        case .space: return ""
        }
    }
}

public enum KeyboardLayout {
    public static let rows: [[(String, String, UInt16)]] = [
        [("z", "Z", 6), ("x", "X", 7), ("c", "C", 8), ("v", "V", 9), ("b", "B", 11), ("n", "N", 45), ("m", "M", 46),
         (",", "<", 43), (".", ">", 47), ("/", "?", 44)],
        [("a", "A", 0), ("s", "S", 1), ("d", "D", 2), ("f", "F", 3), ("g", "G", 5), ("h", "H", 4), ("j", "J", 38),
         ("k", "K", 40), ("l", "L", 37), (";", ":", 41), ("'", "\"", 39)],
        [("q", "Q", 12), ("w", "W", 13), ("e", "E", 14), ("r", "R", 15), ("t", "T", 17), ("y", "Y", 16), ("u", "U", 32),
         ("i", "I", 34), ("o", "O", 31), ("p", "P", 35), ("[", "{", 33), ("]", "}", 30)],
        [("1", "!", 18), ("2", "@", 19), ("3", "#", 20), ("4", "$", 21), ("5", "%", 23), ("6", "^", 22), ("7", "&", 26),
         ("8", "*", 28), ("9", "(", 25), ("0", ")", 29), ("-", "_", 27), ("=", "+", 24)],
    ]

    public static let keys: [TypeKey] = {
        var out: [TypeKey] = []
        for (r, row) in rows.enumerated() {
            for (i, k) in row.enumerated() {
                out.append(TypeKey(id: k.0, lower: k.0, upper: k.1, row: r, index: i, keyCode: k.2))
            }
        }
        return out
    }()

    public static let byKeyCode: [UInt16: TypeKey] = Dictionary(uniqueKeysWithValues: keys.map { ($0.keyCode, $0) })
    public static let byID: [String: TypeKey] = Dictionary(uniqueKeysWithValues: keys.map { ($0.id, $0) })

    /// Physical keys of a Mac keyboard that have no matching key on the
    /// machine borrow the nearest typebar.
    public static let borrowed: [UInt16: String] = [50: "1", 42: "]", 10: "z"]

    public static let functionKeyCodes: [UInt16: FunctionKey] = [48: .tab, 51: .backspace, 49: .space, 53: .marginRelease]

    /// Typebar for a character that arrives without a key (pasted text).
    public static func key(for character: String) -> TypeKey {
        let base = character.decomposedStringWithCanonicalMapping.unicodeScalars.first.map { String($0) } ?? character
        for k in keys where k.lower == base || k.upper == base || k.lower == base.lowercased() {
            return k
        }
        // Spread anything exotic over the basket deterministically.
        let h = base.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return keys[h % keys.count]
    }

    /// Typebar slot order around the segment (left to right across the arc).
    public static let slotOrder: [String] = keys
        .sorted { a, b in
            let ax = Double(a.index) - Double(rows[a.row].count - 1) / 2 - 0.25 * Double(a.row)
            let bx = Double(b.index) - Double(rows[b.row].count - 1) / 2 - 0.25 * Double(b.row)
            return ax == bx ? a.row < b.row : ax < bx
        }
        .map(\.id)

    public static let slotIndex: [String: Int] = Dictionary(uniqueKeysWithValues: slotOrder.enumerated().map { ($1, $0) })
}

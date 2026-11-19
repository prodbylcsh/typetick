import XCTest
@testable import TypetickCore

final class MachineTests: XCTestCase {
    private func machine() -> TypewriterMachine {
        let m = TypewriterMachine(spec: MachineSpec(), style: StrikeStyle(ink: InkStyle(), typeface: TypefaceStyle()))
        var sheet = Sheet(paper: PaperStyle())
        sheet.carriageColumn = 10
        m.perform(.insert(sheet))
        return m
    }

    func testTypingAdvancesCarriageAndRecordsStrikes() {
        let m = machine()
        for ch in "Hi" { m.perform(.type(String(ch), keyID: nil)) }
        XCTAssertEqual(m.column, 12)
        XCTAssertEqual(m.snapshotSheet()?.strikes.count, 2)
        XCTAssertEqual(m.snapshotSheet()?.text.plainText(), "Hi")
    }

    func testCarriageReturnFeedsALine() {
        let m = machine()
        let feed = m.feed
        m.perform(.type("a", keyID: nil))
        m.perform(.carriageReturn)
        m.perform(.type("b", keyID: nil))
        XCTAssertEqual(m.column, m.leftMargin + 1)
        XCTAssertEqual(m.feed, feed + m.lineHeightPoints, accuracy: 0.001)
        XCTAssertEqual(m.snapshotSheet()?.text.plainText(), "a\nb")
    }

    func testBellRingsBeforeRightMargin() {
        let m = machine()
        m.perform(.moveCarriage(to: m.bellColumn - 1))
        let events = m.perform(.type("x", keyID: nil))
        XCTAssertTrue(events.contains { $0.event == .bell })
    }

    func testEraseCoversTheLastCharacter() {
        let m = machine()
        for ch in "cat" { m.perform(.type(String(ch), keyID: nil)) }
        m.perform(.erase)
        XCTAssertEqual(m.column, 12)
        XCTAssertEqual(m.snapshotSheet()?.text.plainText(), "ca")
        m.perform(.type("r", keyID: nil))
        XCTAssertEqual(m.snapshotSheet()?.text.plainText(), "car")
    }

    func testMarginAutoReturn() {
        let m = machine()
        m.perform(.setMargins(left: 10, right: 15))
        for ch in "abcdefg" { m.perform(.type(String(ch), keyID: nil)) }
        XCTAssertEqual(m.snapshotSheet()?.text.plainText(), "abcde\nfg")
    }

    func testCopyFillsClipLoop() {
        let m = machine()
        _ = m.copy("hello")
        XCTAssertEqual(m.recorder.clipText, "hello")
    }

    func testTabStops() {
        let m = machine()
        m.perform(.tab)
        XCTAssertEqual(m.column, 15)
        m.perform(.toggleTabStop)
        XCTAssertFalse(m.tabs.contains(15))
    }

    func testSelectionText() {
        let m = machine()
        for ch in "one two" { m.perform(ch == " " ? .space : .type(String(ch), keyID: nil)) }
        let text = m.snapshotSheet()!.text
        let line = text.sortedKeys.first!.line
        XCTAssertEqual(text.text(from: CellKey(line: line, column: 14), to: CellKey(line: line, column: 16)), "two")
        XCTAssertEqual(text.wordRange(around: CellKey(line: line, column: 15))?.0.column, 14)
    }

    func testSlotOrderCoversEveryKey() {
        XCTAssertEqual(Set(KeyboardLayout.slotOrder).count, KeyboardLayout.keys.count)
    }
}

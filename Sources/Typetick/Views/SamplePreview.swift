import AppKit
import SwiftUI
import TypetickCore
import TypetickScene

/// Renders a swatch of real typewriting with the given paper, ink and type
/// through the same renderer used on the machine.
struct SamplePreview: View {
    var paper: PaperStyle
    var ink: InkStyle
    var typeface: TypefaceStyle
    var spec: MachineSpec
    @State private var image: CGImage?

    nonisolated private static let lines = [
        "The quick brown fox jumps over",
        "the lazy dog. 0123456789 &$%@",
        "",
        "Dear Diary,  — corrections: abc",
        "\"Pack my box with five dozen",
        "liquor jugs!\" said the typist.",
    ]

    var body: some View {
        ZStack {
            if let img = image {
                Image(nsImage: NSImage(cgImage: img, size: NSSize(width: img.width / 2, height: img.height / 2)))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
        .task(id: Key(paper: paper, ink: ink, typeface: typeface)) {
            try? await Task.sleep(nanoseconds: 120_000_000)
            if Task.isCancelled { return }
            let paper = paper, ink = ink, typeface = typeface, spec = spec
            let img = await Task.detached(priority: .userInitiated) { SamplePreview.render(paper: paper, ink: ink, typeface: typeface, spec: spec) }.value
            if !Task.isCancelled { image = img }
        }
    }

    struct Key: Hashable { var paper: PaperStyle; var ink: InkStyle; var typeface: TypefaceStyle }

    nonisolated static func render(paper: PaperStyle, ink: InkStyle, typeface: TypefaceStyle, spec: MachineSpec) -> CGImage? {
        var sheet = Sheet(paper: paper, lineHeight: spec.lineHeightPoints)
        let style = sheet.styleIndex(for: StrikeStyle(ink: ink, typeface: typeface))
        let red = sheet.styleIndex(for: StrikeStyle(ink: ink, typeface: typeface, useSecondColor: true))
        var rng = SplitMix64(seed: 42)
        let pitch = spec.pitchPoints
        for (row, line) in lines.enumerated() {
            let baseline = 40 + Double(row) * spec.lineHeightPoints
            for (i, ch) in line.enumerated() where ch != " " {
                let col = 4 + i
                let st = (row == 3 && i < 11) ? red : style
                _ = sheet.append { id in
                    Strike(id: id, character: String(ch), column: col, x: Double(col) * pitch, baseline: baseline, pitch: pitch,
                           style: st, kind: .ink, pressure: 0.75 + 0.35 * rng.nextUnit(), seed: UInt32(truncatingIfNeeded: rng.next()))
                }
            }
        }
        // a corrected word at the end of row 3
        let corrected = "abc"
        for (i, ch) in corrected.enumerated() {
            let col = 4 + 29 + i
            _ = sheet.append { id in
                Strike(id: id, character: String(ch), column: col, x: Double(col) * pitch, baseline: 40 + 3 * spec.lineHeightPoints, pitch: pitch,
                       style: style, kind: spec.correctionMode == .liftOff ? .liftOff : .coverUp, pressure: 0.9, seed: UInt32(i))
            }
        }
        guard let r = PaperRenderer(sheet: sheet, dpi: 220, spec: spec), let full = r.snapshot() else { return nil }
        let scale = 220.0 / 72.0
        let crop = CGRect(x: 0, y: 0, width: 300 * scale, height: 150 * scale)
        return full.cropping(to: crop)
    }
}

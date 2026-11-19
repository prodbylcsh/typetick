import SwiftUI
import TypetickCore

/// Quiet instrument strip over the stage: carriage scale, spacing, ribbon,
/// recorder spring and clipboard state. Kept small so the machine is the UI.
struct MachineHUD: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let c = model.controller
        VStack {
            HStack(spacing: 10) {
                CarriageScale(column: c.column, left: c.leftMargin, right: c.rightMargin)
                    .frame(width: 220, height: 22)
                Divider().frame(height: 16)
                chip(icon: "line.3.horizontal", text: spacingText(c.lineSpacing), help: "Line spacing (⌥⌘L)") { c.cycleLineSpacing() }
                chip(icon: "circle.lefthalf.filled", text: c.secondColor ? "Red" : "Black", help: "Ribbon color (⌥⌘R)") { c.toggleRibbonColor() }
                SpringGauge(level: c.springLevel)
                    .help("Recorder spring. Carriage returns wind it; Paste unwinds it.")
                if c.selectionLength > 0 {
                    Label("\(c.selectionLength)", systemImage: "text.cursor")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.blue)
                }
                if c.autoTyping {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Recorder").font(.caption)
                        Button("Stop") { c.stopAutoTyping() }.controlSize(.mini)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.08)))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            .padding(.top, 10)
            Spacer()
            if let status = c.status {
                Text(status)
                    .font(.callout)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: c.status)
    }

    private func spacingText(_ s: Double) -> String {
        s == 1 ? "1" : (s == 1.5 ? "1½" : String(format: "%g", s))
    }

    private func chip(icon: String, text: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(text, systemImage: icon)
                .font(.caption.weight(.medium))
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Miniature of the margin scale: margins, bell zone and carriage pointer.
struct CarriageScale: View {
    let column: Int
    let left: Int
    let right: Int
    var total: Int = 85

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x: (Int) -> CGFloat = { CGFloat($0) / CGFloat(max(total, right + 1)) * w }
            ZStack(alignment: .topLeading) {
                Path { p in
                    for i in stride(from: 0, through: max(total, right + 1), by: 5) {
                        let px = x(i)
                        p.move(to: CGPoint(x: px, y: 12))
                        p.addLine(to: CGPoint(x: px, y: i % 10 == 0 ? 4 : 8))
                    }
                }
                .stroke(.secondary.opacity(0.6), lineWidth: 1)
                Rectangle().fill(.orange.opacity(0.25))
                    .frame(width: max(0, x(right) - x(max(left, right - 7))), height: 4)
                    .offset(x: x(max(left, right - 7)), y: 14)
                ForEach([left, right], id: \.self) { m in
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                        .offset(x: x(m) - 3.5, y: -3)
                }
                Capsule().fill(.tint).frame(width: 2, height: 18)
                    .offset(x: x(column) - 1, y: 2)
                    .animation(.easeOut(duration: 0.08), value: column)
            }
        }
        .help("Column \(column) · margins \(left)–\(right)")
    }
}

struct SpringGauge: View {
    let level: Double
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "recordingtape").font(.caption)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(width: 40, height: 5)
                Capsule().fill(level < 0.15 ? Color.orange : Color.green.opacity(0.8))
                    .frame(width: 40 * max(0.02, min(1, level)), height: 5)
            }
        }
    }
}

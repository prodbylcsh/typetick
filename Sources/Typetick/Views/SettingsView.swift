import SwiftUI
import TypetickCore
import TypetickScene

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Sound") {
                Toggle("Mechanical sounds", isOn: $model.preferences.soundEnabled)
                LabeledSlider("Volume", value: $model.preferences.volume)
                LabeledSlider("Room", value: $model.preferences.roomReverb, range: 0...40, format: "%.0f%%")
            }
            Section("Typing") {
                Toggle("Return automatically at the right margin", isOn: $model.preferences.machineSettings.autoReturn)
                Toggle("Feed a new sheet when the page runs out", isOn: $model.preferences.machineSettings.autoFeedSheets)
                Toggle("Control-C / X / V drive the recorder", isOn: $model.preferences.controlClipboard)
                Toggle("Show instrument strip", isOn: $model.preferences.showHUD)
            }
            Section("Rendering") {
                Picker("Paper resolution", selection: $model.preferences.paperDPI) {
                    Text("Standard (200 dpi)").tag(200.0)
                    Text("Fine (300 dpi)").tag(300.0)
                    Text("Ultra (400 dpi)").tag(400.0)
                }
                Picker("Seat", selection: $model.preferences.framing) {
                    ForEach(StageFraming.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Keys") {
                Grid(alignment: .leading, verticalSpacing: 4) {
                    row("Return", "Carriage return + line feed")
                    row("Delete", "Back up and strike over with correction tape")
                    row("⌥ Delete / ←", "Backspace only")
                    row("→ / Space", "Space")
                    row("↑ ↓  (⌥ for half line)", "Roll the platen")
                    row("⇧ arrows, drag, double-click", "Select on the sheet")
                    row("Click on the sheet", "Move carriage and platen there")
                    row("⌥ (hold)", "Margin release")
                    row("⌘[ / ⌘]", "Set left / right margin")
                    row("⌥⌘T", "Set or clear a tab stop")
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 640)
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).font(.callout.monospaced()).foregroundStyle(.secondary)
            Text(v)
        }
    }
}

import AppKit
import SwiftUI
import TypetickCore

/// Flat, scrollable view of what is on paper, plus a plain-text transcript.
struct ReaderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $mode) {
                    Text("Sheet").tag(0)
                    Text("Transcript").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                Spacer()
                if let note = model.selectedNote {
                    Button("Copy Text") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(note.plainText, forType: .string)
                    }
                    Button("Export Text…") { model.exportText(note) }
                    Button("Export Image…") { model.exportImage() }
                }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            if mode == 0 {
                ScrollView([.vertical, .horizontal]) {
                    if let img = model.controller.sheetImage {
                        Image(nsImage: NSImage(cgImage: img, size: NSSize(width: img.width / 2, height: img.height / 2)))
                            .interpolation(.high)
                            .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                            .padding(30)
                    } else {
                        Text("No sheet in the machine").foregroundStyle(.secondary).padding(40)
                    }
                }
                .background(Color(nsColor: .underPageBackgroundColor))
            } else {
                ScrollView {
                    Text(model.selectedNote?.plainText ?? "")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 640)
        .onAppear { model.controller.commitSheet() }
    }
}

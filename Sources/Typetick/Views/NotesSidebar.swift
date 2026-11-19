import AppKit
import SwiftUI
import TypetickCore

struct NotesSidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedNoteID) {
            let notes = model.store.search(model.search)
            let pinned = notes.filter(\.pinned)
            if !pinned.isEmpty {
                Section("Pinned") { ForEach(pinned) { NoteRow(note: $0).tag($0.id) } }
            }
            Section(pinned.isEmpty ? "Notes" : "All Notes") {
                ForEach(notes.filter { !$0.pinned }) { NoteRow(note: $0).tag($0.id) }
            }
            if let note = model.selectedNote, note.sheets.count > 1 {
                Section("Sheets in “\(note.title)”") {
                    ForEach(Array(note.sheets.enumerated()), id: \.element.id) { i, sheet in
                        Button {
                            model.controller.showSheet(i)
                        } label: {
                            HStack {
                                Image(systemName: i == note.currentSheet ? "doc.fill" : "doc")
                                Text("Sheet \(i + 1)")
                                Spacer()
                                Circle().fill(Color(rgb: sheet.paper.color)).frame(width: 10, height: 10)
                                    .overlay(Circle().stroke(.quaternary))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $model.search, placement: .sidebar, prompt: "Search typed text")
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first {
                Button(model.store.note(id)?.pinned == true ? "Unpin" : "Pin") { model.store.togglePin(id) }
                if let n = model.store.note(id) { Button("Export as Text…") { model.exportText(n) } }
                Divider()
                Button("Delete", role: .destructive) { model.delete(id) }
            }
        }
        .onDeleteCommand { if let id = model.selectedNoteID { model.delete(id) } }
    }
}

struct NoteRow: View {
    let note: Note
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(rgb: note.sheets.first?.paper.color ?? RGB(1, 1, 1)))
                .frame(width: 22, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(.quaternary))
                .overlay(alignment: .bottomTrailing) {
                    if note.sheets.count > 1 {
                        Text("\(note.sheets.count)").font(.system(size: 8, weight: .bold)).padding(2)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .lineLimit(1)
                Text(note.excerpt.isEmpty ? note.modified.formatted(date: .abbreviated, time: .shortened) : note.excerpt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }
}

extension Color {
    init(rgb: RGB) { self.init(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1) }
}

extension RGB {
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
    }
}

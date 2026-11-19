import AppKit
import Foundation
import UniformTypeIdentifiers
import Observation
import SwiftUI
import TypetickCore
import TypetickScene

@MainActor
@Observable
final class AppModel {
    var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            preferences.save()
            controller.apply(preferences)
        }
    }
    let store: NoteStore
    let controller: MachineController
    var selectedNoteID: UUID? {
        didSet {
            guard selectedNoteID != oldValue else { return }
            if let id = selectedNoteID, let note = store.note(id) { controller.open(note: note) } else { controller.closeNote() }
        }
    }
    var search = ""
    var showReader = false
    var workshopSection: WorkshopSection = .machine

    init() {
        let prefs = Preferences.load()
        let store = NoteStore()
        self.store = store
        preferences = prefs
        controller = MachineController(preferences: prefs, store: store)
        controller.apply(prefs)
        if let first = store.notes.first {
            selectedNoteID = first.id
            controller.open(note: first)
        }
    }

    var selectedNote: Note? { store.note(selectedNoteID) }

    func newNote() {
        controller.commitSheet()
        let n = store.create(paper: preferences.paper)
        selectedNoteID = n.id
    }

    func delete(_ id: UUID) {
        if selectedNoteID == id {
            selectedNoteID = nil
        }
        store.delete(id)
    }

    func exportText(_ note: Note) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(note.title).txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? note.plainText.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func exportImage() {
        guard let image = controller.sheetImage else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(selectedNote?.title ?? "Sheet").png"
        panel.allowedContentTypes = [.png]
        if panel.runModal() == .OK, let url = panel.url {
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
}

enum WorkshopSection: String, CaseIterable, Identifiable {
    case machine, paper, ink, typeface, desk, lighting
    var id: String { rawValue }
    var title: String {
        switch self {
        case .machine: return "Machine"
        case .paper: return "Paper"
        case .ink: return "Ink & Ribbon"
        case .typeface: return "Typeface"
        case .desk: return "Desk"
        case .lighting: return "Lighting"
        }
    }
    var symbol: String {
        switch self {
        case .machine: return "gearshape.2"
        case .paper: return "doc"
        case .ink: return "drop"
        case .typeface: return "textformat"
        case .desk: return "rectangle.split.3x1"
        case .lighting: return "lamp.desk"
        }
    }
}

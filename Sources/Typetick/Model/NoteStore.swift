import Foundation
import Observation
import TypetickCore

/// Notes live as one JSON file each in Application Support. Everything is
/// local; nothing ever leaves the Mac.
@MainActor
@Observable
final class NoteStore {
    private(set) var notes: [Note] = []
    let folder: URL
    private var pendingSaves: [UUID: Task<Void, Never>] = [:]

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = base.appendingPathComponent("Typetick/Notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        load()
    }

    private func url(for id: UUID) -> URL { folder.appendingPathComponent("\(id.uuidString).typetick.json") }

    func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        notes = files.filter { $0.lastPathComponent.hasSuffix(".typetick.json") }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(Note.self, from: data)
        }
        sort()
    }

    private func sort() {
        notes.sort { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.modified > b.modified
        }
    }

    func note(_ id: UUID?) -> Note? { notes.first { $0.id == id } }

    @discardableResult
    func create(paper: PaperStyle) -> Note {
        let n = Note(paper: paper)
        notes.insert(n, at: 0)
        save(n, immediately: true)
        return n
    }

    func update(_ note: Note, touch: Bool = true) {
        var n = note
        if touch { n.modified = Date() }
        if let i = notes.firstIndex(where: { $0.id == n.id }) { notes[i] = n } else { notes.insert(n, at: 0) }
        save(n)
    }

    func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: url(for: id))
    }

    func togglePin(_ id: UUID) {
        guard var n = note(id) else { return }
        n.pinned.toggle()
        update(n, touch: false)
        sort()
    }

    /// Debounced, off-main-thread write.
    func save(_ note: Note, immediately: Bool = false) {
        pendingSaves[note.id]?.cancel()
        let target = url(for: note.id)
        pendingSaves[note.id] = Task.detached(priority: .utility) {
            if !immediately { try? await Task.sleep(nanoseconds: 600_000_000) }
            if Task.isCancelled { return }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(note) { try? data.write(to: target, options: .atomic) }
        }
    }

    func search(_ query: String) -> [Note] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return notes }
        return notes.filter { $0.plainText.localizedCaseInsensitiveContains(q) || $0.title.localizedCaseInsensitiveContains(q) }
    }
}

import Foundation
import PencilKit
import SwiftUI

enum PaperStyle: String, Codable, CaseIterable, Identifiable {
    case dotted, ruled, blank
    var id: Self { self }
    var title: String { rawValue.capitalized }
}

/// All ink and future annotation bounds use this fixed page coordinate space.
enum NotebookPage {
    static let size = CGSize(width: 1000, height: 1400)
}

struct PageViewport: Codable, Equatable {
    var zoom: Double = 0 // New pages fit the available width.
    var x: Double = 0
    var y: Double = 0
}

struct NoteRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = "Untitled note"
    var createdAt = Date()
    var updatedAt = Date()
    var text = ""
    var paper: PaperStyle = .dotted
    var viewport = PageViewport()
    var drawingRevision = 0
    var drawingFile: String?
}

struct LocalNotebook {
    let root: URL

    static func applicationStore() throws -> Self {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask, appropriateFor: nil, create: true)
        return Self(root: support.appendingPathComponent("ScribbleScout", isDirectory: true))
    }

    func folder(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }

    func load(_ id: UUID) throws -> (note: NoteRecord, drawing: PKDrawing, recovered: Bool) {
        do {
            let value = try snapshot(id, name: "note.json")
            return (value.0, value.1, false)
        } catch {
            let value = try snapshot(id, name: "previous.json")
            return (value.0, value.1, true)
        }
    }

    private func snapshot(_ id: UUID, name: String) throws -> (NoteRecord, PKDrawing) {
        let directory = folder(for: id)
        let note = try JSONDecoder().decode(NoteRecord.self, from: Data(contentsOf: directory.appendingPathComponent(name)))
        guard note.id == id, note.drawingFile.map({ $0 == URL(fileURLWithPath: $0).lastPathComponent }) ?? true else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let drawing = try note.drawingFile.map { try PKDrawing(data: Data(contentsOf: directory.appendingPathComponent($0))) } ?? PKDrawing()
        return (note, drawing)
    }

    func list() throws -> (notes: [NoteRecord], warnings: [String]) {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var notes: [NoteRecord] = []
        var warnings: [String] = []
        for directory in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            guard let id = UUID(uuidString: directory.lastPathComponent) else { continue }
            do {
                let value = try load(id)
                notes.append(value.note)
                if value.recovered { warnings.append("Recovered “\(value.note.title)” from its previous saved copy.") }
            } catch {
                warnings.append("A note could not be opened. Its files have been kept safe in \(directory.lastPathComponent).")
            }
        }
        return (notes.sorted { $0.updatedAt > $1.updatedAt }, warnings)
    }

    /// Commit the ink first, then atomically publish metadata pointing at that immutable ink.
    /// A crash between those writes leaves the previous complete snapshot readable.
    func save(_ record: NoteRecord, drawing: PKDrawing, inkChanged: Bool) throws -> NoteRecord {
        let directory = folder(for: record.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var committed = record
        if inkChanged || record.drawingFile == nil {
            let filename = "\(UUID().uuidString).drawing"
            try drawing.dataRepresentation().write(to: directory.appendingPathComponent(filename), options: .atomic)
            committed.drawingFile = filename
        }
        let currentURL = directory.appendingPathComponent("note.json")
        // Never replace the recovery copy with corrupt or incomplete data.
        if (try? snapshot(record.id, name: "note.json")) != nil {
            try Data(contentsOf: currentURL).write(to: directory.appendingPathComponent("previous.json"), options: .atomic)
        }
        try JSONEncoder().encode(committed).write(to: currentURL, options: .atomic)
        let previous = try? snapshot(record.id, name: "previous.json").0
        let retained = Set([committed.drawingFile, previous?.drawingFile].compactMap { $0 })
        // Only remove obsolete ink after both complete snapshots are on disk.
        for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        where file.pathExtension == "drawing" && !retained.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
        return committed
    }
}

@MainActor
final class NoteSession: ObservableObject, Identifiable {
    let id: UUID
    @Published private(set) var note: NoteRecord
    private(set) var drawing: PKDrawing
    @Published private(set) var saveMessage = "Saved on this iPad"
    @Published private(set) var saveError: String?
    private let repository: LocalNotebook
    private var savedRevision: Int
    private var pendingSave: Task<Void, Never>?
    private var dirty = false
    var onSave: ((NoteRecord) -> Void)?

    init(note: NoteRecord, drawing: PKDrawing, repository: LocalNotebook) {
        id = note.id
        self.note = note
        self.drawing = drawing
        self.repository = repository
        savedRevision = note.drawingRevision
    }

    func edit(_ change: (inout NoteRecord) -> Void) {
        change(&note)
        note.updatedAt = Date()
        scheduleSave()
    }

    func setDrawing(_ value: PKDrawing) {
        drawing = value
        edit { $0.drawingRevision += 1 }
    }

    func setViewport(_ value: PageViewport) {
        guard value != note.viewport else { return }
        note.viewport = value
        scheduleSave()
    }

    private func scheduleSave() {
        dirty = true
        saveMessage = "Saving…"
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            self?.flush()
        }
    }

    @discardableResult
    func flush() -> Bool {
        pendingSave?.cancel()
        guard dirty || note.drawingFile == nil else { return true }
        do {
            // ponytail: synchronous local snapshots suit a small notebook; use a serial I/O actor for large libraries.
            note = try repository.save(note, drawing: drawing, inkChanged: savedRevision != note.drawingRevision)
            savedRevision = note.drawingRevision
            dirty = false
            saveError = nil
            saveMessage = "Saved on this iPad"
            onSave?(note)
            return true
        } catch {
            saveMessage = "Couldn’t save"
            saveError = "Your latest changes are still open. Free up storage, then tap Retry. \(error.localizedDescription)"
            return false
        }
    }
}

@MainActor
final class NotebookStore: ObservableObject {
    @Published private(set) var notes: [NoteRecord] = []
    @Published private(set) var current: NoteSession?
    @Published var issue: String?
    private var repository: LocalNotebook?

    init() {
        do {
            let repository = try LocalNotebook.applicationStore()
            self.repository = repository
            let listing = try repository.list()
            notes = listing.notes
            if !listing.warnings.isEmpty { issue = listing.warnings.joined(separator: "\n\n") }
            let lastID = UserDefaults.standard.string(forKey: "lastNote").flatMap(UUID.init(uuidString:))
            if let note = notes.first(where: { $0.id == lastID }) ?? notes.first { open(note.id) }
        } catch { issue = "The local notebook could not be opened. \(error.localizedDescription)" }
    }

    func open(_ id: UUID) {
        guard current?.id != id, current?.flush() != false, let repository else { return }
        do {
            let value = try repository.load(id)
            install(NoteSession(note: value.note, drawing: value.drawing, repository: repository))
        } catch { issue = "This note couldn’t be opened. Its saved files have been preserved. \(error.localizedDescription)" }
    }

    func create() {
        guard current?.flush() != false, let repository else { return }
        let note = NoteRecord()
        let session = NoteSession(note: note, drawing: PKDrawing(), repository: repository)
        guard session.flush() else { issue = session.saveError; return }
        notes.insert(session.note, at: 0)
        install(session)
    }

    private func install(_ session: NoteSession) {
        session.onSave = { [weak self] note in
            guard let self else { return }
            if let index = self.notes.firstIndex(where: { $0.id == note.id }) { self.notes[index] = note }
            self.notes.sort { $0.updatedAt > $1.updatedAt }
        }
        current = session
        UserDefaults.standard.set(session.id.uuidString, forKey: "lastNote")
    }
}

import Foundation
import PencilKit
import SwiftUI

/// All ink and future annotation bounds use this fixed page coordinate space.
enum NotebookPage {
    static let size = CGSize(width: 1000, height: 1400)
    static let checkoutSize = CGSize(width: 1448, height: 1026)
    static func size(for note: NoteRecord) -> CGSize { note.template == .checkout ? checkoutSize : size }
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
    @Published private var storedNote: NoteRecord
    private var viewport: PageViewport
    var note: NoteRecord {
        var value = storedNote
        value.viewport = viewport
        return value
    }
    private(set) var drawing: PKDrawing
    @Published private(set) var saveMessage = "Saved on this iPad"
    @Published private(set) var saveError: String?
    private let repository: LocalNotebook
    private var savedRevision: Int
    private var pendingSave: Task<Void, Never>?
    private var dirty = false
    var onSave: ((NoteRecord) -> Void)?
    var onSearchableChange: (() -> Void)?

    init(note: NoteRecord, drawing: PKDrawing, repository: LocalNotebook) {
        id = note.id
        storedNote = note
        viewport = note.viewport
        self.drawing = drawing
        self.repository = repository
        savedRevision = note.drawingRevision
    }

    func edit(_ change: (inout NoteRecord) -> Void) {
        var updated = note
        change(&updated)
        if updated.text != storedNote.text { updated.meetingEvidence = nil }
        else if updated.title != storedNote.title {
            updated.meetingEvidence = updated.meetingEvidence?.map { source in
                var source = source
                source.title = updated.title
                return source
            }
        }
        let searchableChanged = updated.title != storedNote.title || updated.text != storedNote.text
        updated.updatedAt = Date()
        viewport = updated.viewport
        storedNote = updated
        scheduleSave()
        if searchableChanged { onSearchableChange?() }
    }

    /// Blocks retain the original source and evidence even after the ink changes.
    @discardableResult
    func insertBlock(_ suggestion: Suggestion, at bounds: CanvasBounds, undoManager: UndoManager? = nil) -> UUID {
        let block = InsertedBlock(body: suggestion.answer, caveat: suggestion.caveat,
                                  evidence: suggestion.evidence, region: suggestion.request.region,
                                  bounds: bounds, isFixture: suggestion.isFixture)
        replaceBlocks((note.blocks ?? []) + [block], undoManager: undoManager, action: "Insert AI block")
        return block.id
    }

    func updateBlock(_ id: UUID, body: String, undoManager: UndoManager? = nil) {
        var blocks = note.blocks ?? []
        guard let index = blocks.firstIndex(where: { $0.id == id }), blocks[index].body != body else { return }
        blocks[index].body = body
        blocks[index].editedAt = Date()
        replaceBlocks(blocks, undoManager: undoManager, action: "Edit AI block")
    }

    func moveBlock(_ id: UUID, to bounds: CanvasBounds, undoManager: UndoManager? = nil) {
        var blocks = note.blocks ?? []
        guard let index = blocks.firstIndex(where: { $0.id == id }), blocks[index].bounds != bounds else { return }
        blocks[index].bounds = bounds
        replaceBlocks(blocks, undoManager: undoManager, action: "Move AI block")
    }

    func deleteBlock(_ id: UUID, undoManager: UndoManager? = nil) {
        let blocks = note.blocks ?? []
        guard blocks.contains(where: { $0.id == id }) else { return }
        replaceBlocks(blocks.filter { $0.id != id }, undoManager: undoManager, action: "Delete AI block")
    }

    private func replaceBlocks(_ blocks: [InsertedBlock], undoManager: UndoManager?, action: String) {
        let previous = note.blocks ?? []
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] target in
            target.replaceBlocks(previous, undoManager: undoManager, action: action)
        }
        undoManager?.setActionName(action)
        edit { $0.blocks = blocks }
    }

    func setDrawing(_ value: PKDrawing) {
        drawing = value
        edit { $0.drawingRevision += 1 }
    }

    func setViewport(_ value: PageViewport) {
        guard value != viewport else { return }
        // Navigation persists without invalidating the entire note editor each frame.
        viewport = value
        scheduleSave(updateStatus: false)
    }

    private func scheduleSave(updateStatus: Bool = true) {
        dirty = true
        if updateStatus && saveMessage != "Saving…" { saveMessage = "Saving…" }
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
            storedNote = try repository.save(note, drawing: drawing, inkChanged: savedRevision != note.drawingRevision)
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
    @Published private(set) var searchMatches: [NoteSearchMatch] = []
    @Published private(set) var searchStatus = "Preparing on-device search…"
    @Published private(set) var isSearching = false
    private var repository: LocalNotebook?
    private var semanticSearch: LocalSemanticSearch?
    private var searchQuery = ""
    private var searchedDocuments: [NoteSearchDocument]?
    private var searchTask: Task<Void, Never>?

    var searchableNotes: [NoteRecord] {
        guard let current else { return notes }
        return notes.map { $0.id == current.id ? current.note : $0 }
    }

    init() {
        do {
            let repository = try LocalNotebook.applicationStore()
            self.repository = repository
            semanticSearch = LocalSemanticSearch(cacheURL: repository.root.appendingPathComponent("search-index.json"))
            let listing = try repository.list()
            notes = listing.notes
            for meeting in NoteRecord.fictionalMeetings where !notes.contains(where: { $0.id == meeting.id }) {
                let example = NoteSession(note: meeting, drawing: PKDrawing(), repository: repository)
                if example.flush() { notes.append(example.note) }
                else { issue = example.saveError }
            }
            if !listing.warnings.isEmpty { issue = listing.warnings.joined(separator: "\n\n") }
            // Install the reference page once; existing notes and their last-opened page stay intact.
            if !notes.contains(where: { $0.template == .checkout }) {
                let example = NoteSession(note: .checkoutExample, drawing: PKDrawing(), repository: repository)
                if example.flush() {
                    notes.insert(example.note, at: 0)
                    install(example)
                    return
                }
                issue = example.saveError
            }
            let lastID = UserDefaults.standard.string(forKey: "lastNote").flatMap(UUID.init(uuidString:))
            if let note = notes.first(where: { $0.id == lastID }) ?? notes.first { open(note.id) }
            else { search("") }
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
            self.search(self.searchQuery)
        }
        session.onSearchableChange = { [weak self] in
            guard let self else { return }
            self.search(self.searchQuery)
        }
        current = session
        UserDefaults.standard.set(session.id.uuidString, forKey: "lastNote")
        search(searchQuery)
    }

    func recall(_ query: String) async throws -> [Evidence] {
        guard let semanticSearch else { return [] }
        let documents = searchableNotes.map(\.searchDocument)
        let response = try await semanticSearch.search(query, documents: documents)
        return response.matches.filter { $0.evidence != nil }.prefix(3).flatMap { match in
            let latest = searchableNotes.first { $0.id == match.id }?.meetingEvidence ?? []
            let sources = (documents.first { $0.id == match.id }?.evidence ?? []).filter { latest.contains($0) }
            return sources.sorted { ($0.id == match.evidence?.id ? 0 : 1) < ($1.id == match.evidence?.id ? 0 : 1) }
        }
    }

    func sourceSession(_ evidence: Evidence) -> NoteSession? {
        guard let id = evidence.canvasID, let repository,
              searchableNotes.first(where: { $0.id == id })?.meetingEvidence?.contains(evidence) == true,
              let value = try? repository.load(id),
              value.note.meetingEvidence?.contains(evidence) == true else { return nil }
        return NoteSession(note: value.note, drawing: value.drawing, repository: repository)
    }

    func search(_ query: String) {
        let documents = searchableNotes.map {
            NoteSearchDocument(id: $0.id, title: $0.title,
                               text: ($0.template == .checkout ? CheckoutPaper.transcript + "\n" : "") + $0.text,
                               evidence: $0.meetingEvidence ?? [])
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        guard query != searchQuery || documents != searchedDocuments else { return }
        searchQuery = query
        searchedDocuments = documents
        searchTask?.cancel()
        searchMatches = []
        searchStatus = "Searching on this iPad…"
        guard let semanticSearch else { searchStatus = "Search unavailable"; isSearching = false; return }
        isSearching = true
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(200))
                let response = try await semanticSearch.search(query, documents: documents)
                try Task.checkCancellation()
                self?.searchMatches = response.matches
                self?.searchStatus = response.status
                self?.isSearching = false
            } catch is CancellationError {
                return
            } catch {
                self?.searchStatus = "Search unavailable"
                self?.isSearching = false
            }
        }
    }
}

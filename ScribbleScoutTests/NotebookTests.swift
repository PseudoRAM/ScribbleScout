import Testing
import PencilKit
@testable import ScribbleScout

@Suite("Notebook persistence and editing")
struct NotebookTests {
    private func drawing() -> PKDrawing {
        let points = [CGPoint(x: 80, y: 100), CGPoint(x: 160, y: 140), CGPoint(x: 240, y: 100)]
        let path = PKStrokePath(controlPoints: points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                          size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date(timeIntervalSince1970: 1_000))
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)])
    }

    private func withRepository(_ test: (LocalNotebook) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try test(LocalNotebook(root: root))
    }

    @Test(arguments: PaperStyle.allCases)
    func testRealInkAndMetadataSurviveReopeningAndNotesStaySeparate(paper: PaperStyle) throws {
        try withRepository { repository in
            var first = NoteRecord(title: "Planning", text: "Remember the decision", paper: paper,
                                   viewport: PageViewport(zoom: 1.5, x: 120, y: 240), drawingRevision: 1)
            first = try repository.save(first, drawing: drawing(), inkChanged: true)
            let second = try repository.save(NoteRecord(title: "Another canvas"), drawing: PKDrawing(), inkChanged: true)
            let reopened = try LocalNotebook(root: repository.root).load(first.id)
            #expect(reopened.note == first)
            try #require(reopened.drawing.strokes.count == 1)
            #expect(reopened.drawing.strokes[0].path[1].location == CGPoint(x: 160, y: 140))
            #expect(try repository.load(second.id).drawing.strokes.isEmpty)
            #expect(try repository.list().notes.count == 2)
            #expect(!reopened.recovered)
        }
    }

    @Test
    func testBrokenMetadataAndInterruptedInkWriteRecoverPreviousSnapshot() throws {
        try withRepository { repository in
            var note = try repository.save(NoteRecord(title: "Original"), drawing: drawing(), inkChanged: true)
            let originalFile = note.drawingFile
            note.title = "Updated"
            note = try repository.save(note, drawing: drawing(), inkChanged: false)
            #expect(note.drawingFile == originalFile, "Metadata edits must not duplicate ink")
            let folder = repository.folder(for: note.id)
            try Data("orphaned pending ink".utf8).write(to: folder.appendingPathComponent("interrupted.drawing"))
            try Data("truncated json".utf8).write(to: folder.appendingPathComponent("note.json"))
            let recovered = try repository.load(note.id)
            #expect(recovered.recovered)
            #expect(recovered.note.title == "Original")
            #expect(recovered.drawing.strokes.count == 1)
            let repaired = try repository.save(recovered.note, drawing: recovered.drawing, inkChanged: false)
            #expect(try repository.load(repaired.id).note.title == "Original")
        }
    }

    @Test
    func testCorruptedLatestInkFallsBackWithoutOverwritingRecoveryCopy() throws {
        try withRepository { repository in
            var note = try repository.save(NoteRecord(title: "Safe ink"), drawing: drawing(), inkChanged: true)
            let previousFile = try #require(note.drawingFile)
            note.drawingRevision += 1
            note = try repository.save(note, drawing: PKDrawing(), inkChanged: true)
            try Data("broken ink".utf8).write(to: repository.folder(for: note.id).appendingPathComponent(try #require(note.drawingFile)))
            let recovered = try repository.load(note.id)
            #expect(recovered.recovered)
            #expect(recovered.note.drawingFile == previousFile)
            #expect(recovered.drawing.strokes.count == 1)
        }
    }

    @Test
    func testOnlyCurrentAndPreviousInkAreRetained() throws {
        try withRepository { repository in
            var note = NoteRecord()
            for revision in 1...5 {
                note.drawingRevision = revision
                note = try repository.save(note, drawing: drawing(), inkChanged: true)
            }
            let files = try FileManager.default.contentsOfDirectory(at: repository.folder(for: note.id), includingPropertiesForKeys: nil)
            #expect(files.filter { $0.pathExtension == "drawing" }.count == 2)
            #expect(try repository.load(note.id).note.drawingRevision == 5)
        }
    }

    @Test(arguments: ["id", "drawingFile"])
    func testInvalidSnapshotRecoversPreviousCopy(field: String) throws {
        try withRepository { repository in
            var note = try repository.save(NoteRecord(title: "Safe copy"), drawing: drawing(), inkChanged: true)
            note.title = "Latest copy"
            note = try repository.save(note, drawing: drawing(), inkChanged: false)
            let currentURL = repository.folder(for: note.id).appendingPathComponent("note.json")
            var metadata = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: currentURL)) as? [String: Any])
            // A readable external drawing ensures this checks path validation, not a missing-file error.
            try drawing().dataRepresentation().write(to: repository.root.appendingPathComponent("outside.drawing"))
            metadata[field] = field == "id" ? UUID().uuidString : "../outside.drawing"
            try JSONSerialization.data(withJSONObject: metadata).write(to: currentURL)

            let recovered = try repository.load(note.id)
            #expect(recovered.recovered)
            #expect(recovered.note.title == "Safe copy")
            #expect(recovered.drawing.strokes.count == 1)
        }
    }

    @Test
    func testMissingLatestDrawingRecoversPreviousInk() throws {
        try withRepository { repository in
            var note = try repository.save(NoteRecord(), drawing: drawing(), inkChanged: true)
            let previousFile = note.drawingFile
            note = try repository.save(note, drawing: PKDrawing(), inkChanged: true)
            try FileManager.default.removeItem(at: repository.folder(for: note.id)
                .appendingPathComponent(try #require(note.drawingFile)))

            let recovered = try repository.load(note.id)
            #expect(recovered.recovered)
            #expect(recovered.note.drawingFile == previousFile)
            #expect(recovered.drawing.strokes.count == 1)
        }
    }

    @Test
    func testLibrarySortsNotesAndReportsRecoveryWithoutDeletingUnreadableFiles() throws {
        try withRepository { repository in
            let older = try repository.save(NoteRecord(title: "Older", updatedAt: Date(timeIntervalSince1970: 1)),
                                            drawing: PKDrawing(), inkChanged: true)
            var newer = try repository.save(NoteRecord(title: "Newer", updatedAt: Date(timeIntervalSince1970: 2)),
                                            drawing: drawing(), inkChanged: true)
            newer.title = "Incomplete update"
            _ = try repository.save(newer, drawing: drawing(), inkChanged: false)
            try Data("broken metadata".utf8).write(to: repository.folder(for: newer.id).appendingPathComponent("note.json"))
            let brokenID = UUID()
            let brokenFolder = repository.folder(for: brokenID)
            try FileManager.default.createDirectory(at: brokenFolder, withIntermediateDirectories: true)
            let unreadableURL = brokenFolder.appendingPathComponent("note.json")
            let unreadableData = Data("keep this for recovery".utf8)
            try unreadableData.write(to: unreadableURL)
            try Data().write(to: repository.root.appendingPathComponent("unrelated-file"))

            let listing = try repository.list()
            #expect(listing.notes.map(\.id) == [newer.id, older.id])
            #expect(listing.notes.first?.title == "Newer")
            #expect(listing.warnings.count == 2)
            #expect(listing.warnings.contains { $0.contains("Recovered") && $0.contains("Newer") })
            #expect(listing.warnings.contains { $0.contains(brokenFolder.lastPathComponent) })
            #expect(try Data(contentsOf: unreadableURL) == unreadableData)
            #expect(throws: (any Error).self) { try repository.load(brokenID) }
        }
    }

    @MainActor
    @Test
    func testViewportSavePreservesEditDateAndInkAndCleanFlushDoesNotCommitAgain() throws {
        try withRepository { repository in
            let note = try repository.save(NoteRecord(updatedAt: Date(timeIntervalSince1970: 1)),
                                           drawing: drawing(), inkChanged: true)
            let session = NoteSession(note: note, drawing: drawing(), repository: repository)
            var savedNotes: [NoteRecord] = []
            session.onSave = { savedNotes.append($0) }
            let viewport = PageViewport(zoom: 2, x: 50, y: 100)
            session.setViewport(viewport)
            #expect(session.flush())
            let reopened = try repository.load(note.id)
            #expect(reopened.note.viewport == viewport)
            #expect(reopened.note.updatedAt == note.updatedAt)
            #expect(reopened.note.drawingFile == note.drawingFile)
            #expect(reopened.drawing.strokes.count == 1)

            session.setViewport(viewport)
            #expect(session.flush())
            #expect(savedNotes.count == 1)
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func testAutosaveCommitsLatestTextAndInk() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalNotebook(root: root)
        let session = NoteSession(note: NoteRecord(updatedAt: Date(timeIntervalSince1970: 1)),
                                  drawing: PKDrawing(), repository: repository)
        await confirmation("Autosave publishes the latest edits once") { saved in
            var committed: NoteRecord?
            session.onSave = { committed = $0; saved() }
            session.edit { $0.text = "First draft" }
            session.edit { $0.text = "Latest draft" }
            session.setDrawing(drawing())
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(5))
            while committed == nil && clock.now < deadline {
                try? await clock.sleep(for: .milliseconds(20))
            }
            #expect(committed?.text == "Latest draft")
            #expect(session.saveError == nil)
        }
        let reopened = try repository.load(session.id)
        #expect(reopened.note.text == "Latest draft")
        #expect(reopened.note.updatedAt > Date(timeIntervalSince1970: 1))
        #expect(reopened.note.drawingRevision == 1)
        #expect(reopened.drawing.strokes.count == 1)
    }

    @MainActor
    @Test
    func testFailedSaveKeepsEditsAndRetryCommitsThem() throws {
        try withRepository { repository in
            try FileManager.default.createDirectory(at: repository.root, withIntermediateDirectories: true)
            let note = NoteRecord()
            try Data().write(to: repository.folder(for: note.id)) // A file blocks the note directory.
            let session = NoteSession(note: note, drawing: drawing(), repository: repository)
            var savedNotes: [NoteRecord] = []
            session.onSave = { savedNotes.append($0) }
            session.edit { $0.text = "Unsaved work stays here" }
            #expect(!session.flush())
            #expect(session.saveError != nil)
            #expect(session.note.text == "Unsaved work stays here")
            #expect(session.drawing.strokes.count == 1)
            #expect(savedNotes.isEmpty)

            try FileManager.default.removeItem(at: repository.folder(for: note.id))
            #expect(session.flush())
            #expect(session.saveError == nil)
            #expect(session.saveMessage == "Saved on this iPad")
            #expect(savedNotes == [session.note])
            let reopened = try repository.load(note.id)
            #expect(reopened.note.text == "Unsaved work stays here")
            #expect(reopened.drawing.strokes.count == 1)
        }
    }

    @Test
    func testReferencePageAndCardStatePersistWithoutChangingExistingPageCoordinates() throws {
        try withRepository { repository in
            var sample = NoteRecord.checkoutExample
            sample.keptResearch = true
            sample.attachment = Data([1, 2, 3])
            let saved = try repository.save(sample, drawing: drawing(), inkChanged: true)
            let reopened = try repository.load(saved.id)
            #expect(reopened.note.template == .checkout)
            #expect(reopened.note.keptResearch == true)
            #expect(reopened.note.attachment == sample.attachment)
            #expect(NotebookPage.size(for: reopened.note) == CGSize(width: 1448, height: 1026))

            var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(NoteRecord())) as? [String: Any])
            legacy.removeValue(forKey: "template")
            legacy.removeValue(forKey: "keptResearch")
            legacy.removeValue(forKey: "attachment")
            let existing = try JSONDecoder().decode(NoteRecord.self, from: JSONSerialization.data(withJSONObject: legacy))
            #expect(existing.template == nil)
            #expect(NotebookPage.size(for: existing) == CGSize(width: 1000, height: 1400))
        }
    }

    @MainActor
    @Test
    func testInsertRectangleUsesVisiblePageCoordinatesAndKeepsExistingInk() throws {
        let canvas = PKCanvasView(frame: CGRect(x: 0, y: 0, width: 600, height: 500))
        canvas.contentSize = NotebookPage.size
        canvas.drawing = drawing()
        let controls = CanvasControls()
        controls.canvas = canvas
        controls.addRectangle(color: .red, width: 3)
        #expect(canvas.drawing.strokes.count == 2)
        let stroke = try #require(canvas.drawing.strokes.last)
        let path = stroke.path
        #expect(path.count >= 3)
        #expect(path.first?.location == CGPoint(x: 80, y: 80))
        #expect(path.last?.location == path.first?.location)
        if path.count >= 3 { #expect(path[2].location == CGPoint(x: 260, y: 190)) }
    }
}

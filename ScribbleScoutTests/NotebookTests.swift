import XCTest
import PencilKit
@testable import ScribbleScout

final class NotebookTests: XCTestCase {
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

    func testRealInkAndMetadataSurviveReopeningAndNotesStaySeparate() throws {
        try withRepository { repository in
            var first = NoteRecord(title: "Planning", text: "Remember the decision", paper: .ruled,
                                   viewport: PageViewport(zoom: 1.5, x: 120, y: 240), drawingRevision: 1)
            first = try repository.save(first, drawing: drawing(), inkChanged: true)
            let second = try repository.save(NoteRecord(title: "Another canvas"), drawing: PKDrawing(), inkChanged: true)
            let reopened = try LocalNotebook(root: repository.root).load(first.id)
            XCTAssertEqual(reopened.note, first)
            XCTAssertEqual(reopened.drawing.strokes.count, 1)
            XCTAssertEqual(reopened.drawing.strokes[0].path[1].location, CGPoint(x: 160, y: 140))
            XCTAssertTrue(try repository.load(second.id).drawing.strokes.isEmpty)
            XCTAssertEqual(try repository.list().notes.count, 2)
            XCTAssertFalse(reopened.recovered)
        }
    }

    func testBrokenMetadataAndInterruptedInkWriteRecoverPreviousSnapshot() throws {
        try withRepository { repository in
            var note = try repository.save(NoteRecord(title: "Original"), drawing: drawing(), inkChanged: true)
            let originalFile = note.drawingFile
            note.title = "Updated"
            note = try repository.save(note, drawing: drawing(), inkChanged: false)
            XCTAssertEqual(note.drawingFile, originalFile, "Metadata edits must not duplicate ink")
            let folder = repository.folder(for: note.id)
            try Data("orphaned pending ink".utf8).write(to: folder.appendingPathComponent("interrupted.drawing"))
            try Data("truncated json".utf8).write(to: folder.appendingPathComponent("note.json"))
            let recovered = try repository.load(note.id)
            XCTAssertTrue(recovered.recovered)
            XCTAssertEqual(recovered.note.title, "Original")
            XCTAssertEqual(recovered.drawing.strokes.count, 1)
            let repaired = try repository.save(recovered.note, drawing: recovered.drawing, inkChanged: false)
            XCTAssertEqual(try repository.load(repaired.id).note.title, "Original")
        }
    }

    func testCorruptedLatestInkFallsBackWithoutOverwritingRecoveryCopy() throws {
        try withRepository { repository in
            var note = try repository.save(NoteRecord(title: "Safe ink"), drawing: drawing(), inkChanged: true)
            let previousFile = note.drawingFile!
            note.drawingRevision += 1
            note = try repository.save(note, drawing: PKDrawing(), inkChanged: true)
            try Data("broken ink".utf8).write(to: repository.folder(for: note.id).appendingPathComponent(note.drawingFile!))
            let recovered = try repository.load(note.id)
            XCTAssertTrue(recovered.recovered)
            XCTAssertEqual(recovered.note.drawingFile, previousFile)
            XCTAssertEqual(recovered.drawing.strokes.count, 1)
        }
    }

    func testOnlyCurrentAndPreviousInkAreRetained() throws {
        try withRepository { repository in
            var note = NoteRecord()
            for revision in 1...5 {
                note.drawingRevision = revision
                note = try repository.save(note, drawing: drawing(), inkChanged: true)
            }
            let files = try FileManager.default.contentsOfDirectory(at: repository.folder(for: note.id), includingPropertiesForKeys: nil)
            XCTAssertEqual(files.filter { $0.pathExtension == "drawing" }.count, 2)
            XCTAssertEqual(try repository.load(note.id).note.drawingRevision, 5)
        }
    }

    @MainActor
    func testFailedSaveKeepsTheEditedSessionInMemory() throws {
        try withRepository { repository in
            try FileManager.default.createDirectory(at: repository.root, withIntermediateDirectories: true)
            let note = NoteRecord()
            try Data().write(to: repository.folder(for: note.id)) // A file blocks the note directory.
            let session = NoteSession(note: note, drawing: drawing(), repository: repository)
            session.edit { $0.text = "Unsaved work stays here" }
            XCTAssertFalse(session.flush())
            XCTAssertNotNil(session.saveError)
            XCTAssertEqual(session.note.text, "Unsaved work stays here")
            XCTAssertEqual(session.drawing.strokes.count, 1)
        }
    }

    func testReferencePageAndCardStatePersistWithoutChangingExistingPageCoordinates() throws {
        try withRepository { repository in
            var sample = NoteRecord.checkoutExample
            sample.keptResearch = true
            sample.attachment = Data([1, 2, 3])
            let saved = try repository.save(sample, drawing: drawing(), inkChanged: true)
            let reopened = try repository.load(saved.id)
            XCTAssertEqual(reopened.note.template, .checkout)
            XCTAssertEqual(reopened.note.keptResearch, true)
            XCTAssertEqual(reopened.note.attachment, sample.attachment)
            XCTAssertEqual(NotebookPage.size(for: reopened.note), CGSize(width: 1448, height: 1026))

            var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(NoteRecord())) as? [String: Any])
            legacy.removeValue(forKey: "template")
            legacy.removeValue(forKey: "keptResearch")
            legacy.removeValue(forKey: "attachment")
            let existing = try JSONDecoder().decode(NoteRecord.self, from: JSONSerialization.data(withJSONObject: legacy))
            XCTAssertNil(existing.template)
            XCTAssertEqual(NotebookPage.size(for: existing), CGSize(width: 1000, height: 1400))
        }
    }

    @MainActor
    func testInsertRectangleUsesVisiblePageCoordinatesAndKeepsExistingInk() throws {
        let canvas = PKCanvasView(frame: CGRect(x: 0, y: 0, width: 600, height: 500))
        canvas.contentSize = NotebookPage.size
        canvas.drawing = drawing()
        let controls = CanvasControls()
        controls.canvas = canvas
        controls.addRectangle(color: .red, width: 3)
        XCTAssertEqual(canvas.drawing.strokes.count, 2)
        let stroke = try XCTUnwrap(canvas.drawing.strokes.last)
        let path = stroke.path
        XCTAssertGreaterThanOrEqual(path.count, 3)
        XCTAssertEqual(path.first?.location, CGPoint(x: 80, y: 80))
        XCTAssertEqual(path.last?.location, path.first?.location)
        if path.count >= 3 { XCTAssertEqual(path[2].location, CGPoint(x: 260, y: 190)) }
    }
}

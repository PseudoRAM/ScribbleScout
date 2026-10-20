import Foundation
import Testing
@testable import NotebookCore

@Suite("Note metadata")
struct NoteRecordTests {
    @Test(arguments: PaperStyle.allCases)
    func metadataSurvivesJSONRoundTrip(paper: PaperStyle) throws {
        let note = NoteRecord(
            title: "Project notes 📝", createdAt: Date(timeIntervalSinceReferenceDate: 1_000),
            updatedAt: Date(timeIntervalSinceReferenceDate: 2_000), text: "First line\n第二行",
            paper: paper, viewport: PageViewport(zoom: 1.75, x: 120, y: 240),
            drawingRevision: 3, drawingFile: "saved.drawing",
            template: .checkout, keptResearch: true, attachment: Data([1, 2, 3]))
        let data = try JSONEncoder().encode(note)
        #expect(try JSONDecoder().decode(NoteRecord.self, from: data) == note)
    }

    @Test(arguments: [false, true])
    func existingNotesWithoutInkRemainReadable(explicitNull: Bool) throws {
        // A fixed saved-format fixture catches accidental changes to field names or date encoding.
        var fields: [String: Any] = [
            "id": "27F4A7B3-ABCB-4DC9-8D44-97D70D6E877B", "title": "Existing note",
            "createdAt": 1_000, "updatedAt": 2_000, "text": "Saved text", "paper": "ruled",
            "viewport": ["zoom": 1.5, "x": 30, "y": 60], "drawingRevision": 0,
            "unknownFutureField": true
        ]
        if explicitNull { fields["drawingFile"] = NSNull() }
        let note = try JSONDecoder().decode(NoteRecord.self, from: JSONSerialization.data(withJSONObject: fields))
        #expect(note.id == UUID(uuidString: "27F4A7B3-ABCB-4DC9-8D44-97D70D6E877B"))
        #expect(note.title == "Existing note")
        #expect(note.text == "Saved text")
        #expect(note.createdAt == Date(timeIntervalSinceReferenceDate: 1_000))
        #expect(note.updatedAt == Date(timeIntervalSinceReferenceDate: 2_000))
        #expect(note.paper == .ruled)
        #expect(note.viewport == PageViewport(zoom: 1.5, x: 30, y: 60))
        #expect(note.drawingRevision == 0)
        #expect(note.drawingFile == nil)
        #expect(note.template == nil)
        #expect(note.keptResearch == nil)
        #expect(note.attachment == nil)
    }

    @Test(arguments: ["paper", "viewport"])
    func damagedMetadataIsRejected(field: String) throws {
        var fields = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(NoteRecord())) as? [String: Any])
        fields[field] = field == "paper" ? "unsupported-paper" : "invalid-viewport"
        let data = try JSONSerialization.data(withJSONObject: fields)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(NoteRecord.self, from: data) }
    }
}

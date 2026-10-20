import Foundation

enum PaperStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case dotted, ruled, blank
    var id: Self { self }
    var title: String { rawValue.capitalized }
}

enum NoteTemplate: String, Codable, Sendable { case checkout }

struct PageViewport: Codable, Equatable, Sendable {
    var zoom: Double = 0 // New pages fit the available width.
    var x: Double = 0
    var y: Double = 0
}

struct NoteRecord: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title = "Untitled note"
    var createdAt = Date()
    var updatedAt = Date()
    var text = ""
    var paper: PaperStyle = .dotted
    var viewport = PageViewport()
    var drawingRevision = 0
    var drawingFile: String?
    var template: NoteTemplate?
    var keptResearch: Bool?
    var attachment: Data?
    var blocks: [InsertedBlock]?
    var meetingEvidence: [Evidence]?

    static var checkoutExample: Self {
        let date = Date(timeIntervalSince1970: 1_792_454_400) // 20 October 2026, UTC.
        return Self(title: "Checkout architecture", createdAt: date, updatedAt: date, template: .checkout)
    }
}


extension NoteRecord {
    static let recallQuestion = "What did our previous meetings say about custom checkout for annual plans?"

    static var fictionalMeetings: [Self] {
        let records: [(String, String, String, [(String, String)])] = [
            ("00000000-0000-0000-0000-000000000020", "Fictional · Checkout proposal", "2026-10-06", [
                ("Proposal", "Custom checkout for annual plans was proposed to support a tailored payment flow. Approval is pending."),
                ("Assumption", "The team assumed custom checkout could support trials, tax and discount rules. This has not been verified.")]),
            ("00000000-0000-0000-0000-000000000021", "Fictional · Checkout follow-up", "2026-10-13", [
                ("Settled decision", "For custom checkout for annual plans, the settled decision was to validate trials, tax and discounts before choosing an implementation. No custom checkout build was approved."),
                ("Proposal", "Compare a hosted payment page with the custom checkout proposal for annual plans after requirements validation.")]),
            ("00000000-0000-0000-0000-000000000022", "Fictional · Infrastructure review", "2026-10-15", [
                ("Settled decision", "Rotate database backups weekly and alert on disk capacity. Assign an owner for restore drills.")])
        ]
        return records.map { id, title, day, chunks in
            let date = ISO8601DateFormatter().date(from: day + "T12:00:00Z")!
            let canvasID = UUID(uuidString: id)!
            let evidence = chunks.enumerated().map { offset, chunk in
                Evidence(kind: .note, title: title, excerpt: chunk.1, meetingDate: date,
                         canvasID: canvasID, bounds: CanvasBounds(x: 60, y: Double(180 + offset * 300), width: 880, height: 250),
                         revision: 1, claim: chunk.0, isFictional: true,
                         canvasBounds: CanvasBounds(width: 1000, height: 1400))
            }
            return Self(id: canvasID, title: title, createdAt: date, updatedAt: date,
                        text: evidence.map(\.excerpt).joined(separator: "\n"), meetingEvidence: evidence)
        }
    }

    var searchDocument: NoteSearchDocument {
        NoteSearchDocument(id: id, title: title, text: text, evidence: meetingEvidence ?? [])
    }
}

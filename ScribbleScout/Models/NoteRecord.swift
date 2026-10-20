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

    static var checkoutExample: Self {
        let date = Date(timeIntervalSince1970: 1_792_454_400) // 20 October 2026, UTC.
        return Self(title: "Checkout architecture", createdAt: date, updatedAt: date, template: .checkout)
    }
}

import Foundation

enum PaperStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case dotted, ruled, blank
    var id: Self { self }
    var title: String { rawValue.capitalized }
}

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
}

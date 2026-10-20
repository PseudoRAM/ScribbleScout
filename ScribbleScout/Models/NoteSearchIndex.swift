import Foundation

struct NoteSearchDocument: Equatable, Sendable {
    var id: UUID
    var title: String
    var text: String
    var evidence: [Evidence] = []
}

struct NoteSearchMatch: Identifiable, Sendable {
    var id: UUID
    var excerpt: String
    var score: Double
    var evidence: Evidence? = nil
}

/// A disposable cache. The notebook snapshots remain the source of truth.
struct NoteSearchIndex: Codable, Sendable {
    struct Chunk: Codable, Sendable {
        var text: String
        var vector: [Double]?
    }
    struct Entry: Codable, Sendable {
        var title: String
        var text: String
        var chunks: [Chunk]
    }
    var model = ""
    var dimensions = 0
    var entries: [UUID: Entry] = [:]

    /// Dates, viewport, and ink-only edits do not trigger text embeddings.
    @discardableResult
    mutating func update(_ documents: [NoteSearchDocument], model: String, dimensions: Int,
                         embed: (String) throws -> [Double]?) rethrows -> Bool {
        var changed = false
        if self.model != model || self.dimensions != dimensions {
            self.model = model
            self.dimensions = dimensions
            entries = [:]
            changed = true
        }
        let ids = Set(documents.map(\.id))
        let retained = entries.filter { ids.contains($0.key) }
        if retained.count != entries.count { entries = retained; changed = true }
        for document in documents {
            if let entry = entries[document.id], entry.title == document.title, entry.text == document.text,
               entry.chunks.allSatisfy({ dimensions == 0 ? $0.vector == nil : Self.valid($0.vector, dimensions: dimensions) }) {
                continue
            }
            let chunks = try Self.chunks(document.title + "\n" + document.text).map { text in
                let vector = try embed(text)
                return Chunk(text: text, vector: Self.valid(vector, dimensions: dimensions) ? vector : nil)
            }
            entries[document.id] = Entry(title: document.title, text: document.text, chunks: chunks)
            changed = true
        }
        return changed
    }

    func search(_ query: String, vector: [Double]?, documents: [NoteSearchDocument]) -> [NoteSearchMatch] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let terms = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let stopWords: Set<String> = ["what", "did", "our", "previous", "meetings", "meeting", "say", "about", "the", "a", "an", "for", "to", "and", "of", "in", "was", "we", "is"]
        let topicalTerms = terms.filter { !stopWords.contains($0) }
        var matches: [NoteSearchMatch] = []
        for document in documents {
            // Reject stale cache entries even while a newer indexing request is pending.
            guard let entry = entries[document.id], entry.title == document.title, entry.text == document.text else { continue }
            var best: NoteSearchMatch?
            for chunk in entry.chunks {
                let source = document.evidence.first { $0.excerpt.contains(chunk.text) }
                    ?? (chunk.text == document.title ? document.evidence.first : nil)
                if !document.evidence.isEmpty && source == nil { continue }
                let exact = chunk.text.localizedStandardContains(query)
                let allTerms = !terms.isEmpty && terms.allSatisfy { chunk.text.localizedStandardContains($0) }
                let similarity = Self.cosine(vector, chunk.vector) ?? 0
                let overlap = topicalTerms.filter { chunk.text.localizedStandardContains($0) }.count
                // Dated recall requires a topical anchor; generic meeting language is not evidence.
                if !document.evidence.isEmpty && overlap == 0 && !exact { continue }
                let datedTextMatch = !document.evidence.isEmpty && overlap >= min(2, max(1, topicalTerms.count))
                guard exact || allTerms || datedTextMatch || similarity >= 0.4 else { continue }
                let coverage = document.evidence.isEmpty || topicalTerms.isEmpty ? 0 : Double(overlap) / Double(topicalTerms.count)
                let score = (exact ? 2.0 : allTerms ? 1.0 : 0) + coverage + max(0, similarity)
                if best == nil || score > best!.score {
                    best = NoteSearchMatch(id: document.id, excerpt: source?.excerpt ?? chunk.text, score: score,
                                           evidence: source)
                }
            }
            if let best { matches.append(best) }
        }
        // ponytail: linear cosine scan suits a small notebook; add a vector database only at measured scale.
        return matches.sorted { $0.score == $1.score ? $0.id.uuidString < $1.id.uuidString : $0.score > $1.score }
    }

    static func chunks(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).flatMap { paragraph -> [String] in
            var remainder = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            var result: [String] = []
            while !remainder.isEmpty {
                let limit = remainder.index(remainder.startIndex, offsetBy: min(400, remainder.count))
                let end = limit < remainder.endIndex ? remainder[..<limit].lastIndex(of: " ") ?? limit : limit
                // A long unbroken word still advances by a full window.
                let boundary = end == remainder.startIndex ? limit : end
                result.append(String(remainder[..<boundary]))
                remainder = String(remainder[boundary...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return result
        }
    }

    static func valid(_ vector: [Double]?, dimensions: Int) -> Bool {
        guard let vector, dimensions > 0, vector.count == dimensions,
              vector.allSatisfy(\.isFinite) else { return false }
        let magnitude = vector.reduce(0) { $0 + $1 * $1 }
        return magnitude.isFinite && magnitude > 0
    }

    static func cosine(_ lhs: [Double]?, _ rhs: [Double]?) -> Double? {
        guard let lhs, let rhs, valid(lhs, dimensions: rhs.count), valid(rhs, dimensions: lhs.count) else { return nil }
        let dot = zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
        let left = sqrt(lhs.reduce(0) { $0 + $1 * $1 })
        let right = sqrt(rhs.reduce(0) { $0 + $1 * $1 })
        let value = dot / left / right
        return value.isFinite ? min(1, max(-1, value)) : nil
    }
}

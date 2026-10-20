import Foundation
import NaturalLanguage

/// Model use, cache I/O, and vector scans stay off the main actor and run serially.
actor LocalSemanticSearch {
    struct Response: Sendable {
        var matches: [NoteSearchMatch]
        var status: String
    }
    private let cacheURL: URL
    private var index: NoteSearchIndex?
    private var embedding: NLEmbedding?
    private var loadedModel = false
    private var cacheNeedsSave = false

    init(cacheURL: URL) { self.cacheURL = cacheURL }

    func search(_ query: String, documents: [NoteSearchDocument]) throws -> Response {
        try Task.checkCancellation()
        if !loadedModel {
            embedding = NLEmbedding.sentenceEmbedding(for: .english)
            loadedModel = true
        }
        if index == nil {
            index = (try? JSONDecoder().decode(NoteSearchIndex.self, from: Data(contentsOf: cacheURL))) ?? NoteSearchIndex()
        }
        let embedding = embedding
        let model = embedding.map { "apple-sentence-en-r\($0.revision)-chunks-v1" } ?? "text-only-v1"
        var updated = index ?? NoteSearchIndex()
        let changed = try updated.update(documents, model: model, dimensions: embedding?.dimension ?? 0) { text in
            try Task.checkCancellation()
            return embedding?.vector(for: text)
        }
        try Task.checkCancellation()
        index = updated
        cacheNeedsSave = cacheNeedsSave || changed
        var status = embedding == nil ? "Text matching · On-device English model unavailable" : "On-device meaning + text · English"
        if cacheNeedsSave {
            do {
                try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(updated).write(to: cacheURL, options: .atomic)
                cacheNeedsSave = false
            } catch {
                status += " · Search cache couldn’t be saved"
            }
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let vector = trimmed.isEmpty ? nil : embedding?.vector(for: String(trimmed.prefix(400)))
        if !trimmed.isEmpty, embedding != nil,
           !NoteSearchIndex.valid(vector, dimensions: updated.dimensions) {
            status = "Text matching · No embedding for this query"
        }
        return Response(matches: updated.search(trimmed, vector: vector, documents: documents), status: status)
    }
}

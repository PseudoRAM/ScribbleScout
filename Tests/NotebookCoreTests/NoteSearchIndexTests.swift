import Foundation
import Testing
@testable import NotebookCore

@Suite("Local vector search")
struct NoteSearchIndexTests {
    private let proposal = NoteSearchDocument(id: UUID(), title: "Fictional checkout proposal",
                                              text: "Use a custom payment flow for annual plans.")
    private let followUp = NoteSearchDocument(id: UUID(), title: "Fictional requirements follow-up",
                                              text: "Ask the team about trials, tax and discount rules.")
    private let unrelated = NoteSearchDocument(id: UUID(), title: "Fictional infrastructure meeting",
                                               text: "Rotate database backups and monitor disk capacity.")

    @Test
    func ranksMeaningAlongsideExactTermsAndKeepsOneExcerptPerNote() throws {
        let documents = [proposal, followUp, unrelated]
        var index = NoteSearchIndex()
        // Deterministic vectors exercise retrieval without any model, download, or network.
        index.update(documents, model: "fixture-v1", dimensions: 2) { text in
            if text.contains("payment") { return [1, 0] }
            if text.contains("trials") { return [0.45, sqrt(1 - 0.45 * 0.45)] }
            return [0, 1]
        }
        let results = index.search("billing", vector: [1, 0], documents: documents)
        #expect(results.map(\.id) == [proposal.id, followUp.id])
        #expect(results.first?.excerpt == proposal.text)
        #expect(Set(results.map(\.id)).count == results.count)
        #expect(index.search("backups", vector: [1, 0], documents: documents).first?.id == unrelated.id)
        #expect(index.search("unfindable", vector: nil, documents: documents).isEmpty)
        #expect(index.search(" \n ", vector: [1, 0], documents: documents).isEmpty)
        #expect(index.search("billing", vector: [1, 0], documents: [unrelated]).isEmpty)

        let restored = try JSONDecoder().decode(NoteSearchIndex.self, from: JSONEncoder().encode(index))
        #expect(restored.model == "fixture-v1")
        #expect(restored.dimensions == 2)
        #expect(restored.search("billing", vector: [1, 0], documents: documents).map(\.id) == results.map(\.id))
    }

    @Test
    func reusesUnchangedTextButInvalidatesEditsDeletionsAndModelChanges() {
        var index = NoteSearchIndex()
        var calls = 0
        func embed(_ text: String) -> [Double]? { calls += 1; return [1, 0] }
        #expect(index.update([proposal, unrelated], model: "v1", dimensions: 2, embed: embed) == true)
        let firstCalls = calls
        #expect(index.update([proposal, unrelated], model: "v1", dimensions: 2, embed: embed) == false)
        #expect(calls == firstCalls)
        var edited = proposal
        edited.text = "A different decision."
        #expect(index.search("custom", vector: [1, 0], documents: [edited]).isEmpty)
        #expect(index.update([edited], model: "v1", dimensions: 2, embed: embed) == true)
        #expect(index.entries[unrelated.id] == nil)
        #expect(!index.entries.values.flatMap(\.chunks).contains { $0.text.contains("custom") })
        let editCalls = calls
        #expect(index.update([edited], model: "v2", dimensions: 2, embed: embed) == true)
        #expect(calls > editCalls)
        #expect(index.update([edited], model: "v2", dimensions: 3) { _ in [1, 0, 0] } == true)
        #expect(index.entries[edited.id]?.chunks.allSatisfy { $0.vector?.count == 3 } == true)
        edited.title = "Renamed proposal"
        #expect(index.update([edited], model: "v2", dimensions: 3) { _ in [1, 0, 0] } == true)
        #expect(index.search("Renamed", vector: nil, documents: [edited]).count == 1)
        #expect(index.update([], model: "v2", dimensions: 3) { _ in [1, 0, 0] } == true)
        #expect(index.entries.isEmpty)
    }

    @Test
    func invalidVectorsCannotProduceSemanticResultsAndTextFallbackStillWorks() {
        for vector in [[], [0, 0], [1], [Double.nan, 1], [Double.infinity, 1], [Double.greatestFiniteMagnitude, 1]] {
            #expect(NoteSearchIndex.cosine(vector, [1, 0]) == nil)
            var index = NoteSearchIndex()
            index.update([proposal], model: "invalid", dimensions: 2) { _ in vector }
            #expect(index.search("billing", vector: [1, 0], documents: [proposal]).isEmpty)
            #expect(index.search("PAYMENT", vector: nil, documents: [proposal]).count == 1)
        }
        var index = NoteSearchIndex()
        index.update([proposal], model: "unavailable", dimensions: 0) { _ in nil }
        #expect(index.search("annual payment", vector: nil, documents: [proposal]).count == 1)
        #expect(index.update([proposal], model: "unavailable", dimensions: 0) { _ in Issue.record("Text-only index should be reused"); return nil } == false)
        #expect(NoteSearchIndex.cosine([2, 0], [7, 0]) == 1)
        #expect(NoteSearchIndex.cosine([1, 0], [-1, 0]) == -1)
    }

    @Test
    func chunksLongUnicodeParagraphsWithoutDroppingText() {
        let words = Array(repeating: "Hello 📝 世界", count: 150).joined(separator: " ")
        let chunks = NoteSearchIndex.chunks("\n \n" + words + "\n" + String(repeating: "界", count: 901))
        #expect(chunks.allSatisfy { !$0.isEmpty && $0.count <= 400 })
        #expect(chunks.joined().filter { !$0.isWhitespace } == (words + String(repeating: "界", count: 901)).filter { !$0.isWhitespace })
        #expect(NoteSearchIndex.chunks(" \n\t ").isEmpty)
    }
}

import Foundation
import Testing
@testable import NotebookCore

@Suite("Durable assistance records")
struct AssistanceRecordsTests {
    @Test func insertedEvidenceAndCorrectedTranscriptionRoundTrip() throws {
        let region = NoteRegion(canvasID: UUID(), revision: 4, bounds: CanvasBounds(x: -10, y: 40, width: 180, height: 60), recognisedText: "Do not research Cedar", uncertainty: ["Cedar"], sourceHash: "opaque-stroke-fingerprint")
        let evidence = Evidence(kind: .note, title: "Meeting", excerpt: "30 day retention", canvasID: region.canvasID, bounds: region.bounds)
        let block = InsertedBlock(body: "Review retention", caveat: "Confirm before release", evidence: [evidence], region: region, bounds: CanvasBounds(x: 200, y: 40, width: 240, height: 160))
        #expect(try JSONDecoder().decode(InsertedBlock.self, from: JSONEncoder().encode(block)) == block)
        #expect(evidence.isValid)
        #expect(!Evidence(kind: .web, title: "Injected", url: URL(string: "javascript:alert(1)")).isValid)
        #expect(!Evidence(kind: .note, title: "Missing source", excerpt: "unanchored").isValid)
    }

    @Test func sourceModesRejectMixedEvidenceAndUnsourcedResearch() {
        let region = NoteRegion(canvasID: UUID(), revision: 1, bounds: CanvasBounds(), sourceHash: "source")
        var suggestion = Suggestion(request: AssistanceRequest(region: region, intent: .webResearch, sourceMode: .web, question: "Retention?"), answer: "30 days", evidence: [], state: .ready)
        #expect(!suggestion.hasValidEvidence)
        suggestion.evidence = [Evidence(kind: .web, title: "Returned source", url: URL(string: "https://example.com/docs"))]
        #expect(suggestion.hasValidEvidence)
        suggestion.request.sourceMode = .notes
        #expect(!suggestion.hasValidEvidence)
    }

    @Test func fixtureScenariosAreLocalLabelledAndExcludedFromLiveUsage() async throws {
        let ledger = UsageLedger()
        for scenario in FixtureScenario.allCases {
            let provider = FixtureProvider(scenario: scenario, ledger: ledger)
            if scenario == .failed {
                await #expect(throws: AssistanceError.invalidResponse) { try await provider.recognise(image: Data([1])) }
                await #expect(throws: AssistanceError.missingEvidence) { try await provider.answer("Demo", research: true) }
            } else {
                let recognition = try await provider.recognise(image: Data([1]))
                let answer = try await provider.answer("Demo", research: true)
                #expect(answer.text.contains("Fictional demo"))
                #expect(answer.citations.isEmpty)
                #expect(provider.evidence.allSatisfy { $0.kind == .fixture && $0.isValid })
                if scenario == .ambiguous { #expect(!recognition.uncertainty.isEmpty) }
                if scenario == .conflicting { #expect(provider.evidence.count == 2) }
            }
        }
        #expect(await ledger.entries.count == 10)
        #expect(await ledger.summary.requests == 0)
    }
}

import Foundation

enum FixtureScenario: String, CaseIterable, Codable, Sendable {
    case grounded, ambiguous, failed, stale, conflicting
    var title: String { rawValue.capitalized }
}

/// Entirely local, fictional demo content. Never sends network requests or reports billable usage.
struct FixtureProvider: AssistanceProvider {
    var scenario: FixtureScenario = .grounded
    var ledger = UsageLedger()

    func recognise(image: Data) async throws -> RecognitionResult {
        try await record(.recognition)
        if scenario == .failed { throw AssistanceError.invalidResponse }
        if scenario == .ambiguous {
            return RecognitionResult(text: "Check [unclear] retention?", uncertainty: ["The product acronym is illegible; confirm it before research."])
        }
        return RecognitionResult(text: "Fictional demo: What did Project Cedar decide about retention?")
    }

    func route(_ text: String, image: Data? = nil) async throws -> RoutingDecision {
        try await record(.routing)
        if scenario == .failed { throw AssistanceError.invalidResponse }
        return RoutingDecision(route: scenario == .ambiguous ? .clarify : .recall, confidence: 1)
    }

    func answer(_ text: String, research: Bool, image: Data? = nil) async throws -> AssistanceAnswer {
        try await record(research ? .research : .answer)
        switch scenario {
        case .failed: throw AssistanceError.missingEvidence
        case .ambiguous: return AssistanceAnswer(text: "Fictional demo: Please confirm the unclear product acronym before continuing.", citations: [])
        case .conflicting:
            return AssistanceAnswer(text: "Fictional demo: Cedar's planning note proposes 30 days; its review note proposes 90 days. These sources conflict. Confirm the final decision before adopting either.", citations: [])
        case .stale:
            return AssistanceAnswer(text: "Fictional demo: This result belongs to the earlier ink selection. It must be discarded after the source changes.", citations: [])
        case .grounded:
            return AssistanceAnswer(text: "Fictional demo: Project Cedar chose a 30-day retention window, with a review before release. This is synthetic demo evidence, not a real project decision.", citations: [])
        }
    }

    var evidence: [Evidence] {
        guard scenario == .grounded || scenario == .conflicting || scenario == .stale else { return [] }
        var result = [Evidence(kind: .fixture, title: "Fictional Cedar planning note", excerpt: "Synthetic demo: retain records for 30 days; review before release.")]
        if scenario == .conflicting {
            result.append(Evidence(kind: .fixture, title: "Fictional Cedar review note", excerpt: "Synthetic demo: proposed retention is 90 days; final approval pending."))
        }
        return result
    }

    private func record(_ operation: UsageOperation) async throws {
        try Task.checkCancellation()
        await ledger.record(UsageEntry(operation: operation, requestID: UUID().uuidString, latencySeconds: 0, succeeded: scenario != .failed, isFixture: true))
    }
}

extension AssistanceAnswer {
    /// URL metadata comes exclusively from returned tool annotations; the excerpt is the answer, not a claimed source quotation.
    func webEvidence(fetchedAt: Date = Date()) -> [Evidence] {
        citations.map { Evidence(kind: .web, title: $0.title, url: $0.url, fetchedAt: fetchedAt) }.filter(\.isValid)
    }
}

extension Suggestion {
    var hasValidEvidence: Bool {
        evidence.allSatisfy(\.isValid) &&
        (request.intent != .webResearch || !evidence.filter { $0.kind == .web || (isFixture && $0.kind == .fixture) }.isEmpty) &&
        (request.sourceMode != .notes || !evidence.contains { $0.kind == .web }) &&
        (request.sourceMode != .web || !evidence.contains { $0.kind == .note })
    }
}

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
        return RecognitionResult(text: "Fictional demo: What is Cedar Cloud’s published retention policy?")
    }

    func route(_ text: String, image: Data? = nil) async throws -> RoutingDecision {
        try await record(.routing)
        if scenario == .failed { throw AssistanceError.invalidResponse }
        let input = text.lowercased()
        let route: AssistanceRoute
        if scenario == .ambiguous { route = .clarify }
        else if input.contains("do not research") || input.contains("don't research") { route = .none }
        else if input.contains("meeting") || input.contains("our notes") || input.contains("previous notes") { route = .recall }
        else if input.hasPrefix("explain ") || input.hasPrefix("rewrite ") { route = .quickResponse }
        else { route = .webResearch }
        return RoutingDecision(route: route, confidence: 1)
    }

    func answer(_ text: String, research: Bool, image: Data? = nil) async throws -> AssistanceAnswer {
        try await record(research ? .research : .answer)
        if !research && scenario != .failed {
            return AssistanceAnswer(text: "Fictional demo: A retention window sets how long records remain available before scheduled deletion. Review the window against the purpose of the records and document the agreed policy.", citations: [], caveat: "Synthetic explanation for the demo.")
        }
        switch scenario {
        case .failed: throw AssistanceError.missingEvidence
        case .ambiguous: return AssistanceAnswer(text: "Fictional demo: Please confirm the unclear product acronym before continuing.", citations: [])
        case .conflicting:
            return AssistanceAnswer(text: "Fictional demo: Cedar Cloud’s public policy describes a 30-day window, while its fictional release bulletin describes 90 days. The supplied sources disagree about the applicable policy.", citations: [], caveat: "Synthetic sources conflict; confirm the applicable version.", evidence: evidence)
        case .stale:
            return AssistanceAnswer(text: "Fictional demo: This result belongs to the earlier ink selection. It must be discarded after the source changes.", citations: [], caveat: "Source selection changed; discard this result.", evidence: evidence)
        case .grounded:
            return AssistanceAnswer(text: "Fictional demo: Project Cedar Cloud’s fictional published policy describes a 30-day retention window, followed by scheduled deletion. Review the applicable policy version before making a decision about real records; this example demonstrates the research flow using synthetic sources.", citations: [], caveat: "Synthetic demo evidence, not a real company policy.", evidence: evidence)
        }
    }

    var evidence: [Evidence] {
        guard scenario == .grounded || scenario == .conflicting || scenario == .stale else { return [] }
        var result = [Evidence(kind: .fixture, title: "Fictional Cedar Cloud public policy", excerpt: "Synthetic demo: retain records for 30 days; review before release.")]
        if scenario == .conflicting {
            result.append(Evidence(kind: .fixture, title: "Fictional Cedar Cloud release bulletin", excerpt: "Synthetic demo: proposed retention is 90 days; final approval pending."))
        }
        return result
    }

    private func record(_ operation: UsageOperation) async throws {
        try Task.checkCancellation()
        await ledger.record(UsageEntry(operation: operation, requestID: UUID().uuidString, latencySeconds: 0, succeeded: scenario != .failed, isFixture: true))
    }
}

extension AssistanceAnswer {
    /// URL metadata comes exclusively from returned tool annotations. No source quotation or claim verification is invented.
    func webEvidence(fetchedAt: Date = Date()) -> [Evidence] {
        citations.map { Evidence(kind: .web, title: $0.title, url: $0.url, fetchedAt: fetchedAt) }.filter(\.isValid)
    }
}

extension Suggestion {
    var hasValidEvidence: Bool {
        evidence.allSatisfy(\.isValid) &&
        (isFixture || !evidence.contains { $0.kind == .fixture }) &&
        (!isFixture || evidence.allSatisfy { $0.kind == .fixture }) &&
        (request.intent != .recall || !evidence.filter { $0.kind == .note || (isFixture && $0.kind == .fixture) }.isEmpty) &&
        (request.intent != .webResearch || !evidence.filter { $0.kind == .web || (isFixture && $0.kind == .fixture) }.isEmpty) &&
        (request.sourceMode != .notes || !evidence.contains { $0.kind == .web }) &&
        (request.sourceMode != .web || !evidence.contains { $0.kind == .note })
    }
}

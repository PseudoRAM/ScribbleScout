import Foundation

struct CanvasBounds: Codable, Equatable, Sendable {
    var x: Double = 0
    var y: Double = 0
    var width: Double = 0
    var height: Double = 0
}
struct NoteRegion: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var canvasID: UUID
    var revision: Int
    var bounds: CanvasBounds
    var recognisedText = ""
    var uncertainty: [String] = []
    var sourceHash: String
}
enum EvidenceKind: String, Codable, Sendable { case web, note, fixture }
enum SourceMode: String, Codable, CaseIterable, Sendable { case web, notes, both }
enum SuggestionState: String, Codable, Sendable {
    case recognising, researching, ready, needsContext, stale, dismissed, failed
}
struct Evidence: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var kind: EvidenceKind
    var title: String
    var url: URL? = nil
    var excerpt = ""
    var fetchedAt: Date? = nil
    var meetingDate: Date? = nil
    var canvasID: UUID? = nil
    var bounds: CanvasBounds? = nil
    var isValid: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch kind {
        case .web:
            guard let url else { return false }
            return ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host != nil && url.user == nil && url.password == nil
        case .note: return canvasID != nil && bounds != nil && !excerpt.isEmpty
        case .fixture: return !excerpt.isEmpty
        }
    }
}
struct AssistanceRequest: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var region: NoteRegion
    var intent: AssistanceRoute
    var sourceMode: SourceMode
    var question: String
    var createdAt = Date()
}
struct Suggestion: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var request: AssistanceRequest
    var answer: String
    var caveat = ""
    var evidence: [Evidence]
    var state: SuggestionState
    var createdAt = Date()
    var isFixture = false
}
struct InsertedBlock: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var body: String
    var caveat = ""
    var evidence: [Evidence]
    var region: NoteRegion
    var acceptedAt = Date()
    var editedAt: Date? = nil
    var bounds: CanvasBounds
    var isFixture = false
}
struct RecognitionResult: Codable, Equatable, Sendable {
    var text: String
    var uncertainty: [String] = []
}
protocol AssistanceProvider: Sendable {
    func recognise(image: Data) async throws -> RecognitionResult
    func route(_ text: String, image: Data?) async throws -> RoutingDecision
    func answer(_ text: String, research: Bool, image: Data?) async throws -> AssistanceAnswer
}
extension AssistanceProvider {
    func route(_ text: String) async throws -> RoutingDecision { try await route(text, image: nil) }
    func answer(_ text: String, research: Bool) async throws -> AssistanceAnswer { try await answer(text, research: research, image: nil) }
}
enum UsageOperation: String, Codable, Sendable { case recognition, routing, routingFallback, answer, research }
struct UsageEntry: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var operation: UsageOperation
    var requestID: String
    var serverRequestID: String? = nil
    var inputTokens: Int? = nil
    var outputTokens: Int? = nil
    var toolCalls = 0
    var latencySeconds: Double
    var succeeded: Bool
    var isFixture = false
}
struct UsageSummary: Equatable, Sendable {
    var requests = 0
    var inputTokens = 0
    var outputTokens = 0
    var toolCalls = 0
    var latencySeconds: Double = 0
    var unreportedTokenRequests = 0
}
actor UsageLedger {
    private(set) var entries: [UsageEntry] = []
    func record(_ entry: UsageEntry) { entries.append(entry) }
    func reset() { entries.removeAll() }
    var summary: UsageSummary {
        entries.filter { !$0.isFixture }.reduce(into: UsageSummary()) { result, entry in
            result.requests += 1
            result.inputTokens += entry.inputTokens ?? 0
            result.outputTokens += entry.outputTokens ?? 0
            result.toolCalls += entry.toolCalls
            result.latencySeconds += entry.latencySeconds
            if entry.inputTokens == nil || entry.outputTokens == nil { result.unreportedTokenRequests += 1 }
        }
    }
}

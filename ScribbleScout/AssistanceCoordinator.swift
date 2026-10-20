import SwiftUI

/// One editor owns the work. Closing the inspector does not cancel a request.
@MainActor
final class AssistanceCoordinator: ObservableObject {
    enum Stage { case compose, inspect, review, result }
    enum WorkPhase {
        case reading, deciding, answering, researching, recalling
        var isAction: Bool { self != .reading && self != .deciding }
        var label: String {
            switch self {
            case .reading: "Reading handwriting…"
            case .deciding: "Checking how to help…"
            case .answering: "Writing an explanation…"
            case .researching: "Researching the public question…"
            case .recalling: "Searching dated notes on this iPad…"
            }
        }
    }
    @Published private(set) var workPhase: WorkPhase?
    @Published var stage: Stage = .compose
    @Published var transcript = ""
    @Published var publicQuestion = ""
    @Published var followUp = ""
    @Published var selection: CanvasSelection?
    @Published private(set) var region: NoteRegion?
    @Published private(set) var decision: RoutingDecision?
    @Published private(set) var suggestion: Suggestion?
    @Published private(set) var streamingText = ""
    @Published private(set) var activity: String?
    @Published private(set) var message: String?
    @Published private(set) var usage = UsageSummary()
    @Published private(set) var mutedUntil: Date?
    var resolveSource: ((NoteRegion) -> NoteRegion?)?
    var recallSearch: ((String) async throws -> [Evidence])?
    var providerFactory: ((ScoutSession) -> any AssistanceProvider)?
    var pauseDelay: Duration = .milliseconds(1800)
    var automaticCooldown: TimeInterval = 20
    var automaticallyAnswer = true
    private var task: Task<Void, Never>?
    private var pause: Task<Void, Never>?
    private var generation = UUID()
    private var seen = Set<String>()
    private var automatic = false
    private var lastAutomatic = Date.distantPast
    private var queued: CanvasSelection?
    private var retainedEvidence: [Evidence] = []
    private var dismissedTopics = Set<String>()
    private var mutedTopics: [String: Date] = [:]
    private func topicKey(_ text: String) -> String {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    var busy: Bool { activity != nil }
    var canInsert: Bool { suggestion?.state == .ready && suggestion?.hasValidEvidence == true && !busy }
    var pinTitle: String {
        if let activity { return activity }
        switch suggestion?.state {
        case .ready: return "Scout · ready"
        case .stale: return "Source changed"
        case .failed: return "Scout · retry"
        default: return stage == .inspect ? "Review handwriting" : "Scout · review"
        }
    }

    func prepare(_ selection: CanvasSelection?, region: NoteRegion) {
        cancel()
        automatic = false
        self.selection = selection
        self.region = region
        transcript = selection == nil ? region.recognisedText : ""
        publicQuestion = ""; decision = nil; suggestion = nil; message = nil; retainedEvidence = []
        streamingText = ""
        stage = selection == nil ? .inspect : .compose
    }

    func ask(_ selection: CanvasSelection, using settings: ScoutSession) {
        prepare(selection, region: selection.region)
        recognise(using: settings, automatically: settings.mode == .automatic)
    }

    func recognise(using settings: ScoutSession, automatically: Bool = false) {
        guard let selection, let region, validate(region) else { return }
        automatic = automatically
        run(.reading, settings: settings) { provider in
            let result = try await provider.recognise(image: selection.png, context: selection.contextPNG)
            try Task.checkCancellation()
            guard self.validate(region) else { return }
            self.transcript = result.text
            self.region?.recognisedText = result.text
            self.region?.uncertainty = result.uncertainty
            self.stage = .inspect
            if automatically {
                let topic = self.topicKey(result.text)
                if self.dismissedTopics.contains(topic) || (self.mutedTopics[topic].map { $0 > Date() } ?? false) {
                    self.region = nil; self.selection = nil; self.suggestion = nil
                    return
                }
            }
            if automatically && result.uncertainty.isEmpty && !result.text.contains("[unclear]") {
                self.route(using: settings, afterCurrent: true)
            } else if automatically {
                self.message = "Some handwriting is unclear. Review the transcript before Scout continues."
            }
        }
    }

    func route(using settings: ScoutSession, afterCurrent: Bool = false) {
        guard let region, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if !afterCurrent { claimExplicit() }
        if afterCurrent { activity = nil; task = nil }
        self.region?.recognisedText = transcript
        let input = transcript
        run(.deciding, settings: settings) { provider in
            let result = try await provider.route(input, image: self.selection?.contextPNG)
            try Task.checkCancellation()
            guard self.validate(region) else { return }
            self.decision = result
            self.stage = .review
            self.publicQuestion = "" // Explicit research still uses a separately reviewed question.
            switch result.route {
            case .webResearch: self.message = "Review a public question before research. No web search has started."
            case .recall:
                self.message = "Search dated local notes. Public research uses a separate public question."
            case .clarify: self.message = "Check the transcription and add the subject or missing context."
            case .none:
                self.message = "No assistance needed. Keep writing."
                self.region = nil
            case .quickResponse: self.message = "The corrected text is ready for a quick answer."
            }
            self.suggestion = self.makeSuggestion(answer: "", state: .needsContext, evidence: [], fixture: settings.offline)
            if self.automatic && self.automaticallyAnswer {
                switch result.route {
                case .quickResponse, .webResearch:
                    self.activity = nil; self.task = nil
                    if result.route == .webResearch { self.publicQuestion = input }
                    self.answer(using: settings, research: result.route == .webResearch, automatically: true)
                case .recall:
                    self.activity = nil; self.task = nil
                    self.recall(automatically: true, settings: settings)
                case .clarify, .none: break
                }
            }
        }
    }

    func recall(automatically: Bool = false, settings: ScoutSession? = nil) {
        guard let region, validate(region), let recallSearch, !busy else { return }
        if !automatically { claimExplicit() }
        let query = transcript
        let id = UUID(); generation = id
        workPhase = .recalling
        activity = WorkPhase.recalling.label
        suggestion = nil; message = nil; retainedEvidence = []
        task = Task { @MainActor in
            defer {
                if self.generation == id {
                    self.activity = nil; self.workPhase = nil; self.task = nil
                    if let settings, let queued = self.queued, settings.mode == .automatic {
                        self.queued = nil
                        self.startAutomatic(queued, settings: settings)
                    }
                }
            }
            do {
                let evidence = try await recallSearch(query)
                try Task.checkCancellation()
                guard self.generation == id, self.validate(region) else { return }
                self.retainedEvidence = evidence
                let answer = evidence.map { "\($0.claim ?? "Note") · \($0.meetingDate?.formatted(date: .abbreviated, time: .omitted) ?? "Undated"): \($0.excerpt)" }.joined(separator: "\n\n")
                self.suggestion = Suggestion(request: AssistanceRequest(region: region, intent: .recall, sourceMode: .notes, question: query),
                    answer: answer, caveat: "Local excerpts. Proposals and assumptions are not settled decisions. Fictional meetings are labelled.",
                    evidence: evidence, state: evidence.isEmpty ? .needsContext : .ready)
                self.stage = .result
                if evidence.isEmpty { self.message = "No dated evidence found. Try specific terms from the meeting." }
            } catch is CancellationError { return }
            catch { if self.generation == id { self.message = "Local recall failed. Try again." } }
        }
    }

    func answer(using settings: ScoutSession, research: Bool, followUp: Bool = false, automatically: Bool = false) {
        guard let region, validate(region) else { return }
        if !automatically { claimExplicit() }
        let query = research ? publicQuestion : (followUp ? self.followUp : transcript)
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let previous = suggestion
        let localEvidence = research ? retainedEvidence.filter { $0.kind == .note } : []
        let references = retainedEvidence.map { "\($0.title): \($0.excerpt)" }.joined(separator: "\n")
        let input = followUp && !research ? "Question: \(query)\nPrevious answer: \(previous?.answer ?? "")\nExisting evidence (do not invent new citations):\n\(references)" : query
        streamingText = ""
        run(research ? .researching : .answering, settings: settings) { provider in
            let requestGeneration = self.generation
            let result = try await provider.answer(input, research: research, image: research ? nil : self.selection?.contextPNG) { text in
                await self.receiveStream(text, generation: requestGeneration, source: region)
            }
            try Task.checkCancellation()
            guard self.validate(region) else { return }
            var evidence = !result.evidence.isEmpty ? result.evidence : (settings.offline ? FixtureProvider(scenario: settings.scenario).evidence : result.webEvidence())
            if followUp { evidence = self.retainedEvidence + evidence.filter { item in !self.retainedEvidence.contains(where: { $0.url == item.url && $0.title == item.title }) } }
            evidence = localEvidence + evidence
            self.retainedEvidence = evidence
            let localText = localEvidence.map { "\($0.claim ?? "Note"): \($0.excerpt)" }.joined(separator: "\n\n")
            let combinedText = localEvidence.isEmpty ? result.text : "Private meeting evidence\n" + localText + "\n\nPublic research\n" + result.text
            self.suggestion = self.makeSuggestion(answer: combinedText, state: result.isStale ? .stale : .ready,
                                                 evidence: evidence, fixture: settings.offline)
            self.suggestion?.request.question = query
            if !localEvidence.isEmpty {
                self.suggestion?.request.sourceMode = .both
                self.suggestion?.request.intent = .recall
                self.suggestion?.request.originalQuestion = previous?.request.question
            }
            if followUp, let previous {
                self.suggestion?.request.originalQuestion = previous.request.originalQuestion ?? previous.request.question
                self.suggestion?.request.parentRequestID = previous.request.id
                self.suggestion?.request.sourceMode = previous.request.sourceMode
            }
            if !result.caveat.isEmpty { self.suggestion?.caveat = result.caveat }
            self.streamingText = ""
            self.stage = .result
            self.message = result.isStale ? "Fictional stale-source example: select the current content before requesting a new answer." : nil
        }
    }

    private func receiveStream(_ text: String, generation: UUID, source: NoteRegion) {
        guard self.generation == generation, !Task.isCancelled, validate(source) else { return }
        streamingText = text
    }

    private func makeSuggestion(answer: String, state: SuggestionState, evidence: [Evidence], fixture: Bool) -> Suggestion? {
        guard let region else { return nil }
        let research = decision?.route == .webResearch
        return Suggestion(request: AssistanceRequest(region: region, intent: decision?.route ?? .clarify,
                          sourceMode: .web, question: research ? publicQuestion : transcript), answer: answer,
                          caveat: fixture ? "Fictional offline demo. This is not verified research." :
                          (evidence.isEmpty ? "AI explanation using general knowledge; no external evidence was retrieved." : "AI synthesis. Read the linked sources before relying on it."),
                          evidence: evidence, state: state, isFixture: fixture)
    }

    @discardableResult
    func validate(_ source: NoteRegion? = nil) -> Bool {
        guard let original = source ?? region else { return false }
        guard let current = resolveSource?(original) else {
            if suggestion == nil { suggestion = makeSuggestion(answer: "", state: .stale, evidence: [], fixture: false) }
            suggestion?.state = .stale
            streamingText = ""
            message = "The source changed while Scout was working. Select the current content and recognise it again."
            return false
        }
        region?.bounds = current.bounds
        suggestion?.request.region.bounds = current.bounds
        return true
    }

    func dismissSuggestion() {
        if let region { seen.insert(region.sourceHash) }
        if !transcript.isEmpty { dismissedTopics.insert(topicKey(transcript)) }
        cancel(); suggestion = nil; region = nil; selection = nil; message = nil; stage = .compose
    }
    func mute() {
        if transcript.isEmpty { mutedUntil = Date().addingTimeInterval(300) }
        else { mutedTopics[topicKey(transcript)] = Date().addingTimeInterval(300) }
        cancel(); suggestion = nil; region = nil; selection = nil; stage = .compose
    }
    func transcriptEdited() {
        guard !busy else { return }
        claimExplicit()
        decision = nil; suggestion = nil; message = nil; retainedEvidence = []; stage = .inspect
    }
    func publicQuestionEdited() {
        guard !busy else { return }
        claimExplicit()
        guard suggestion?.state == .ready else { return }
        suggestion?.state = .needsContext
        message = "The public question changed. Research it again before inserting this answer."
    }
    func cancel() {
        if busy { suggestion?.state = .needsContext; message = "Request cancelled. You can retry explicitly; remote processing may continue." }
        generation = UUID(); task?.cancel(); pause?.cancel(); task = nil; activity = nil; workPhase = nil; queued = nil; streamingText = ""
    }
    func stopAutomatic() { pause?.cancel(); queued = nil; if automatic { cancel() } }

    private func claimExplicit() {
        automatic = false
        pause?.cancel()
        pause = nil
        queued = nil
    }

    func schedulePause(using settings: ScoutSession, capture: @escaping @MainActor () -> CanvasSelection?) {
        pause?.cancel()
        guard settings.mode == .automatic, settings.canProcess,
              mutedUntil.map({ $0 <= Date() }) ?? true else { return }
        pause = Task { @MainActor in
            try? await Task.sleep(for: self.pauseDelay)
            let cooldown = self.automaticCooldown - Date().timeIntervalSince(self.lastAutomatic)
            if cooldown > 0 { try? await Task.sleep(for: .seconds(cooldown)) }
            guard !Task.isCancelled, settings.mode == .automatic, settings.canProcess, let selection = capture(),
                  !self.seen.contains(selection.region.sourceHash) else { return }
            if self.busy {
                if self.automatic { self.queued = selection }
                return
            }
            // An explicit draft or result remains owned by the user until dismissed.
            guard self.region == nil || self.automatic || (self.region?.sourceHash.hasPrefix("typed:") == true && self.transcript.isEmpty) else { return } // Bounded queue: only the latest changed region.
            self.startAutomatic(selection, settings: settings)
        }
    }
    private func startAutomatic(_ selection: CanvasSelection, settings: ScoutSession) {
        // A queued snapshot may have changed while the previous job was finishing.
        guard resolveSource?(selection.region) != nil else { return }
        seen.insert(selection.region.sourceHash); lastAutomatic = Date()
        prepare(selection, region: selection.region)
        recognise(using: settings, automatically: true)
    }
    func refreshUsage(_ settings: ScoutSession) async { usage = await settings.ledger.summary }

    private func run(_ phase: WorkPhase, settings: ScoutSession,
                     operation: @escaping @MainActor (any AssistanceProvider) async throws -> Void) {
        guard !busy, settings.canProcess else {
            if !settings.canProcess { message = "Choose offline demo, or provide an API key and allow OpenAI processing in Settings." }
            return
        }
        guard settings.jobs < ScoutSession.jobLimit || settings.offline else { message = "Session request limit reached."; return }
        if !settings.offline { settings.jobs += 1 }
        let provider: any AssistanceProvider
        if let providerFactory { provider = providerFactory(settings) }
        else if settings.offline { provider = FixtureProvider(scenario: settings.scenario, ledger: settings.ledger) }
        else { provider = OpenAIAssistance(apiKey: settings.apiKey, ledger: settings.ledger) }
        let id = UUID(); generation = id; workPhase = phase; activity = phase.label; message = nil
        suggestion = makeSuggestion(answer: suggestion?.answer ?? "", state: phase == .researching ? .researching : .recognising,
                                    evidence: retainedEvidence, fixture: settings.offline)
        task = Task { @MainActor in
            do { try await operation(provider) }
            catch {
                guard self.generation == id, !Task.isCancelled else { return }
                self.streamingText = ""
                self.message = (error as? LocalizedError)?.errorDescription ?? "The request failed. Check your connection and retry."
                self.suggestion = self.makeSuggestion(answer: "", state: .failed, evidence: [], fixture: settings.offline)
            }
            guard self.generation == id else { return }
            self.activity = nil; self.workPhase = nil; self.task = nil
            await self.refreshUsage(settings)
            if let queued = self.queued, settings.mode == .automatic {
                self.queued = nil
                self.startAutomatic(queued, settings: settings)
            }
        }
    }
}

import Testing
import Combine
import UIKit
@testable import ScribbleScout

@Suite("Assistance coordination", .serialized)
@MainActor
struct AssistanceCoordinatorTests {
    private func fixtureSettings() -> ScoutSession {
        let settings = ScoutSession(apiKey: "")
        settings.offline = true
        settings.mode = .explicit
        return settings
    }
    // These existing tests isolate recognition/routing queue behavior from answer generation.
    private func recognitionOnlyCoordinator() -> AssistanceCoordinator {
        let coordinator = AssistanceCoordinator()
        coordinator.automaticallyAnswer = false
        return coordinator
    }

    @Test
    func runtimeKeyEnablesLiveAutomaticProcessingAndForgetStopsIt() {
        let settings = ScoutSession(apiKey: "synthetic-key")
        #expect(settings.canProcess && settings.consent && !settings.offline)
        #expect(settings.mode == .automatic)
        settings.forgetKey()
        #expect(!settings.canProcess)
        settings.apiKey = "replacement-synthetic-key"
        #expect(settings.canProcess && !settings.offline && settings.mode == .automatic)
        settings.consent = false
        #expect(!settings.canProcess)
        let absent = ScoutSession(apiKey: "")
        #expect(!absent.offline && !absent.canProcess)
    }

    @Test
    func automaticClearQuestionStreamsAnswerAndCancellationRejectsLateChunks() async {
        let settings = fixtureSettings()
        settings.mode = .automatic
        let provider = ControlledProvider(held: [.answer], recognitionText: "Explain a database index")
        let coordinator = AssistanceCoordinator()
        coordinator.pauseDelay = .zero
        coordinator.providerFactory = { _ in provider }
        coordinator.resolveSource = { $0 }
        coordinator.schedulePause(using: settings) { selection(region()) }
        await provider.waitForCalls(3)
        #expect(coordinator.busy)
        #expect(coordinator.streamingText == "An index")
        #expect(!coordinator.canInsert)
        coordinator.cancel()
        await provider.release(.answer)
        await nextMainTurn()
        #expect(coordinator.streamingText.isEmpty)
        #expect(coordinator.suggestion?.state != .ready)
    }

    @Test
    func automaticResearchUsesRecognizedQuestionAndTracksWorkPhases() async {
        let settings = fixtureSettings()
        settings.mode = .automatic
        let provider = ControlledProvider(held: [.route, .answer], route: .webResearch,
                                          recognitionText: "What are the current database options?")
        let coordinator = AssistanceCoordinator()
        coordinator.pauseDelay = .zero
        coordinator.providerFactory = { _ in provider }
        coordinator.resolveSource = { $0 }
        coordinator.schedulePause(using: settings) { selection(region()) }
        await provider.waitForCalls(2)
        #expect(coordinator.workPhase == .deciding)
        #expect(coordinator.workPhase?.isAction == false)
        await provider.release(.route)
        await provider.waitForCalls(3)
        #expect(coordinator.workPhase == .researching)
        #expect(coordinator.workPhase?.isAction == true)
        #expect(await provider.answeredText == coordinator.transcript)
        #expect(await provider.answeredWithResearch)
        #expect(await provider.answeredWithImage == false)
        await idle(coordinator) { Task { await provider.release(.answer) } }
        #expect(coordinator.workPhase == nil)
        #expect(coordinator.suggestion?.state == .ready)
    }

    @Test
    func automaticRecallSearchesLocalNotesWithoutAnAnswerRequest() async {
        let settings = fixtureSettings()
        settings.mode = .automatic
        let provider = ControlledProvider(route: .recall, recognitionText: "What did we decide last meeting?")
        let coordinator = AssistanceCoordinator()
        coordinator.pauseDelay = .zero
        coordinator.providerFactory = { _ in provider }
        coordinator.resolveSource = { $0 }
        var searched = ""
        var phase: AssistanceCoordinator.WorkPhase?
        coordinator.recallSearch = { query in
            searched = query
            phase = coordinator.workPhase
            return [Evidence(kind: .note, title: "Last meeting", excerpt: "Validate trials first.")]
        }
        coordinator.schedulePause(using: settings) { selection(region()) }
        await provider.waitForCalls(2)
        await nextMainTurn()
        #expect(searched == coordinator.transcript)
        #expect(phase == .recalling)
        #expect(coordinator.workPhase == nil)
        #expect(coordinator.suggestion?.request.sourceMode == .notes)
        #expect(coordinator.suggestion?.state == .ready)
        #expect(await provider.callCount == 2)
    }

    @Test
    func automaticAnswerCompletesWithoutInspectorAndSourceChangesClearPartialText() async {
        let settings = fixtureSettings()
        settings.mode = .automatic
        let provider = ControlledProvider(held: [.answer], recognitionText: "Explain a database index")
        let coordinator = AssistanceCoordinator()
        coordinator.pauseDelay = .zero
        var valid = true
        coordinator.providerFactory = { _ in provider }
        coordinator.resolveSource = { valid ? $0 : nil }
        coordinator.schedulePause(using: settings) { selection(region()) }
        await provider.waitForCalls(3)
        #expect(coordinator.streamingText == "An index")
        valid = false
        #expect(!coordinator.validate())
        #expect(coordinator.streamingText.isEmpty)
        await idle(coordinator) { Task { await provider.release(.answer) } }
        #expect(coordinator.suggestion?.state == .stale)
        #expect(!coordinator.canInsert)
    }

    private func region(_ text: String = "Explain this decision") -> NoteRegion {
        NoteRegion(canvasID: UUID(), revision: 1, bounds: CanvasBounds(x: 20, y: 30, width: 200, height: 100),
                   recognisedText: text, sourceHash: UUID().uuidString)
    }
    private func selection(_ region: NoteRegion) -> CanvasSelection {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { output in
            UIColor.white.setFill(); output.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        return CanvasSelection(image: image, png: image.pngData()!, contextImage: image, contextPNG: image.pngData()!,
                               contextBounds: region.bounds.cgRect, bounds: region.bounds.cgRect, outline: [], region: region)
    }
    private func idle(_ coordinator: AssistanceCoordinator, action: () -> Void) async {
        await withCheckedContinuation { continuation in
            var observer: AnyCancellable?
            observer = coordinator.$activity.drop(while: { $0 == nil }).filter { $0 == nil }.first().sink { _ in
                observer?.cancel(); continuation.resume()
            }
            action()
        }
    }
    private func nextMainTurn() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }

    @Test
    func askSelectionStartsRecognitionWithCanvasContextWithoutAnotherTap() async {
        let settings = fixtureSettings()
        let coordinator = recognitionOnlyCoordinator()
        let provider = ControlledProvider(held: [.recognition])
        coordinator.resolveSource = { $0 }
        coordinator.providerFactory = { _ in provider }
        let source = region()
        let selected = selection(source)
        coordinator.ask(selected, using: settings)
        await provider.waitForCalls(1)
        await idle(coordinator) { Task { await provider.release(.recognition) } }
        #expect(await provider.callCount == 1)
        #expect(await provider.recognitionContext == selected.contextPNG)
        #expect(coordinator.stage == .inspect)
        #expect(!coordinator.transcript.isEmpty)
    }

    @Test
    func localRecallNeedsNoProviderAndCombinedResearchSendsOnlyPublicQuestion() async throws {
        let settings = fixtureSettings()
        settings.mode = .off
        let provider = ControlledProvider()
        let coordinator = recognitionOnlyCoordinator()
        coordinator.resolveSource = { $0 }
        coordinator.providerFactory = { _ in provider }
        let source = region("Private project codename: secret. What did our previous meetings decide?")
        let selected = selection(source)
        let notes = NoteRecord.fictionalMeetings.prefix(2).flatMap { $0.meetingEvidence ?? [] }
        coordinator.recallSearch = { query in
            #expect(query.contains("secret"))
            return notes
        }
        coordinator.prepare(selected, region: source)
        coordinator.transcript = source.recognisedText
        await idle(coordinator) { coordinator.recall() }
        #expect(await provider.callCount == 0)
        #expect(coordinator.suggestion?.request.sourceMode == .notes)
        #expect(coordinator.canInsert)
        #expect(coordinator.suggestion?.answer.contains("Assumption") == true)
        #expect(coordinator.suggestion?.answer.contains("Settled decision") == true)
        #expect(coordinator.selection?.region == selected.region)
        #expect(coordinator.region == source)

        settings.mode = .explicit
        coordinator.publicQuestion = "What payment flows support annual subscriptions?"
        await idle(coordinator) { coordinator.answer(using: settings, research: true) }
        #expect(await provider.answeredText == coordinator.publicQuestion)
        #expect(await provider.answeredWithImage == false)
        #expect(await provider.answeredWithResearch == true)
        #expect(coordinator.suggestion?.request.sourceMode == .both)
        #expect(coordinator.suggestion?.evidence.filter { $0.kind == .note } == notes)
        #expect(coordinator.canInsert)
    }

    @Test
    func sourceEditedDuringAnswerCannotBeAccepted() async throws {
        let settings = fixtureSettings()
        let provider = ControlledProvider(held: [.answer])
        let coordinator = recognitionOnlyCoordinator()
        coordinator.providerFactory = { _ in provider }
        var sourceExists = true
        coordinator.resolveSource = { sourceExists ? $0 : nil }
        let source = region()
        coordinator.prepare(nil, region: source)
        coordinator.answer(using: settings, research: false)
        await provider.waitForCalls(1)
        sourceExists = false
        await idle(coordinator) { Task { await provider.release(.answer) } }
        #expect(coordinator.suggestion?.state == .stale)
        #expect(!coordinator.canInsert)
        #expect(coordinator.message?.contains("source changed") == true)
    }

    @Test
    func offlineStaleScenarioCannotBeInsertedEvenWithUnchangedInk() async {
        let settings = fixtureSettings()
        settings.scenario = .stale
        let coordinator = recognitionOnlyCoordinator()
        coordinator.resolveSource = { $0 }
        coordinator.prepare(nil, region: region())
        coordinator.publicQuestion = "A fictional public question"
        await idle(coordinator) { coordinator.answer(using: settings, research: true) }
        #expect(coordinator.suggestion?.state == .stale)
        #expect(coordinator.suggestion?.isFixture == true)
        #expect(!coordinator.canInsert)
    }

    @Test
    func followUpRetainsOriginalQuestionAndParentRequest() async throws {
        let settings = fixtureSettings()
        let coordinator = recognitionOnlyCoordinator()
        coordinator.resolveSource = { $0 }
        coordinator.prepare(nil, region: region("Explain a retention window"))
        await idle(coordinator) { coordinator.answer(using: settings, research: false) }
        let original = try #require(coordinator.suggestion?.request)
        coordinator.followUp = "Explain the release review"
        await idle(coordinator) { coordinator.answer(using: settings, research: false, followUp: true) }
        #expect(coordinator.suggestion?.request.originalQuestion == original.question)
        #expect(coordinator.suggestion?.request.parentRequestID == original.id)
        #expect(coordinator.suggestion?.request.sourceMode == original.sourceMode)
    }

    @Test
    func cancelledProviderThatIgnoresCancellationCannotPublishItsAnswer() async {
        let settings = fixtureSettings()
        let provider = ControlledProvider(held: [.answer])
        let coordinator = recognitionOnlyCoordinator()
        coordinator.providerFactory = { _ in provider }
        coordinator.resolveSource = { $0 }
        coordinator.prepare(nil, region: region())
        coordinator.answer(using: settings, research: false)
        await provider.waitForCalls(1)
        coordinator.cancel()
        await provider.release(.answer)
        await nextMainTurn()
        #expect(!coordinator.busy)
        #expect(!coordinator.canInsert)
        #expect(coordinator.suggestion?.state != .ready)
        #expect(coordinator.suggestion?.answer != "Delayed answer")
    }

    @Test
    func explicitDraftPreemptsAutomaticRecognitionEvenWhenOldProviderFinishes() async {
        let settings = fixtureSettings()
        settings.mode = .automatic
        let provider = ControlledProvider(held: [.recognition])
        let coordinator = recognitionOnlyCoordinator()
        coordinator.providerFactory = { _ in provider }
        coordinator.resolveSource = { $0 }
        let automaticSelection = selection(region("Automatic handwriting"))
        coordinator.pauseDelay = .zero
        coordinator.automaticCooldown = 0
        coordinator.schedulePause(using: settings) { automaticSelection }
        await provider.waitForCalls(1)
        let explicit = region("My explicit question")
        coordinator.prepare(nil, region: explicit)
        await idle(coordinator) { coordinator.route(using: settings) }
        await provider.release(.recognition)
        await nextMainTurn()
        #expect(coordinator.region?.id == explicit.id)
        #expect(coordinator.transcript == "My explicit question")
        #expect(coordinator.decision?.route == .quickResponse)
        #expect(!coordinator.busy)
    }

    @Test
    func automaticWorkKeepsOnlyLatestQueuedRegion() async {
        let settings = fixtureSettings()
        settings.mode = .automatic
        let provider = ControlledProvider(held: [.recognition])
        let coordinator = recognitionOnlyCoordinator()
        coordinator.pauseDelay = .zero
        coordinator.automaticCooldown = 0
        coordinator.providerFactory = { _ in provider }
        coordinator.resolveSource = { $0 }
        let first = selection(region("First"))
        let middle = selection(region("Middle"))
        let latest = selection(region("Latest"))
        coordinator.schedulePause(using: settings) { first }
        await provider.waitForCalls(1)
        await withCheckedContinuation { continuation in
            coordinator.schedulePause(using: settings) { continuation.resume(); return middle }
        }
        await withCheckedContinuation { continuation in
            coordinator.schedulePause(using: settings) { continuation.resume(); return latest }
        }
        await provider.release(.recognition)
        await provider.waitForCalls(4) // Recognition and routing for first and latest only.
        await nextMainTurn()
        #expect(coordinator.region?.id == latest.region.id)
        #expect(await provider.callCount == 4)
        #expect(coordinator.region?.id != middle.region.id)
    }

    @Test
    func dismissedEquivalentTopicIsSuppressedAcrossChangedSourceHashes() async {
        let settings = fixtureSettings()
        settings.mode = .automatic
        let provider = ControlledProvider(recognitionText: "Explain TLS security")
        let coordinator = recognitionOnlyCoordinator()
        coordinator.pauseDelay = .zero
        coordinator.automaticCooldown = 0
        coordinator.providerFactory = { _ in provider }
        coordinator.resolveSource = { $0 }
        let first = selection(region("First source"))
        coordinator.schedulePause(using: settings) { first }
        await provider.waitForCalls(2)
        await nextMainTurn()
        coordinator.dismissSuggestion()
        let changedHash = selection(region("Changed source"))
        coordinator.schedulePause(using: settings) { changedHash }
        await provider.waitForCalls(3)
        await nextMainTurn()
        #expect(coordinator.region == nil)
        #expect(coordinator.suggestion == nil)
        #expect(await provider.callCount == 3, "Equivalent dismissed topics should recognise locally but not route again")
    }

    @Test
    func explicitAnswerOwnsAutomaticResultAndPreventsLaterPauseFromReplacingIt() async {
        let settings = fixtureSettings()
        settings.mode = .automatic
        let provider = ControlledProvider(held: [.answer])
        let coordinator = recognitionOnlyCoordinator()
        coordinator.pauseDelay = .zero
        coordinator.automaticCooldown = 0
        coordinator.providerFactory = { _ in provider }
        coordinator.resolveSource = { $0 }
        let original = selection(region("Original automatic source"))
        coordinator.schedulePause(using: settings) { original }
        await provider.waitForCalls(2)
        await nextMainTurn()
        coordinator.answer(using: settings, research: false)
        await provider.waitForCalls(3)
        let later = selection(region("Later handwriting"))
        await withCheckedContinuation { continuation in
            coordinator.schedulePause(using: settings) { continuation.resume(); return later }
        }
        await idle(coordinator) { Task { await provider.release(.answer) } }
        await nextMainTurn()
        #expect(coordinator.suggestion?.state == .ready)
        #expect(coordinator.suggestion?.request.region.id == original.region.id)
        #expect(coordinator.region?.id == original.region.id)
        #expect(await provider.callCount == 3, "A later writing pause must not replace an explicitly requested answer")
    }

    @Test
    func queuedSourceInvalidatedBeforeDrainIsNeverUploadedForRecognition() async {
        let settings = fixtureSettings()
        settings.mode = .automatic
        let provider = ControlledProvider(held: [.recognition])
        let coordinator = recognitionOnlyCoordinator()
        coordinator.pauseDelay = .zero
        coordinator.automaticCooldown = 0
        coordinator.providerFactory = { _ in provider }
        var invalidated = Set<UUID>()
        coordinator.resolveSource = { invalidated.contains($0.id) ? nil : $0 }
        let original = selection(region("Still current"))
        let queued = selection(region("Edited before processing"))
        coordinator.schedulePause(using: settings) { original }
        await provider.waitForCalls(1)
        await withCheckedContinuation { continuation in
            coordinator.schedulePause(using: settings) { continuation.resume(); return queued }
        }
        invalidated.insert(queued.region.id)
        await provider.release(.recognition)
        await provider.waitForCalls(2)
        await nextMainTurn()
        #expect(await provider.callCount == 2, "Only original recognition and routing should reach the provider")
        #expect(coordinator.region?.id != queued.region.id)
        #expect(!coordinator.busy)
    }

    @Test(arguments: [ScoutSession.Mode.off, .explicit])
    func nonAutomaticModesDoNotCaptureOrUpload(mode: ScoutSession.Mode) async {
        let settings = fixtureSettings()
        settings.mode = mode
        let provider = ControlledProvider()
        let coordinator = recognitionOnlyCoordinator()
        coordinator.pauseDelay = .zero
        coordinator.providerFactory = { _ in provider }
        var captures = 0
        coordinator.schedulePause(using: settings) { captures += 1; return nil }
        await nextMainTurn()
        #expect(captures == 0)
        #expect(await provider.callCount == 0)
    }

    @Test
    func defaultCooldownDropsNewPauseAndExplicitRequestStillRuns() async {
        let settings = fixtureSettings()
        settings.mode = .automatic
        let provider = ControlledProvider()
        let coordinator = recognitionOnlyCoordinator()
        coordinator.pauseDelay = .zero
        coordinator.providerFactory = { _ in provider }
        coordinator.resolveSource = { $0 }
        #expect(coordinator.automaticCooldown == 20)
        let first = selection(region())
        coordinator.schedulePause(using: settings) { first }
        await provider.waitForCalls(2)
        await nextMainTurn()
        var captures = 0
        coordinator.schedulePause(using: settings) { captures += 1; return first }
        await nextMainTurn()
        #expect(captures == 0)
        #expect(await provider.callCount == 2)
        coordinator.prepare(nil, region: region("Explicit request during cooldown"))
        await idle(coordinator) { coordinator.route(using: settings) }
        #expect(await provider.callCount == 3)
        #expect(coordinator.transcript == "Explicit request during cooldown")
    }

    @Test
    func mutedTopicRecognisesButDoesNotRouteAgain() async {
        let settings = fixtureSettings()
        settings.mode = .automatic
        let provider = ControlledProvider(recognitionText: "Explain TLS security")
        let coordinator = recognitionOnlyCoordinator()
        coordinator.pauseDelay = .zero
        coordinator.automaticCooldown = 0
        coordinator.providerFactory = { _ in provider }
        coordinator.resolveSource = { $0 }
        let first = selection(region())
        coordinator.schedulePause(using: settings) { first }
        await provider.waitForCalls(2)
        await nextMainTurn()
        coordinator.mute()
        let second = selection(region())
        coordinator.schedulePause(using: settings) { second }
        await provider.waitForCalls(3)
        await nextMainTurn()
        #expect(coordinator.region == nil)
        #expect(coordinator.suggestion == nil)
        #expect(await provider.callCount == 3)
    }

    @Test
    func automaticResearchRouteWaitsForSeparatelyReviewedPublicQuestion() async {
        let settings = fixtureSettings()
        settings.mode = .automatic
        let provider = ControlledProvider(route: .webResearch)
        let coordinator = recognitionOnlyCoordinator()
        #expect(coordinator.pauseDelay == .milliseconds(1800))
        coordinator.pauseDelay = .zero
        coordinator.providerFactory = { _ in provider }
        coordinator.resolveSource = { $0 }
        let source = selection(region())
        coordinator.schedulePause(using: settings) { source }
        await provider.waitForCalls(2)
        await nextMainTurn()
        #expect(coordinator.stage == .review)
        #expect(coordinator.publicQuestion.isEmpty)
        #expect(coordinator.message?.contains("No web search has started") == true)
        #expect(await provider.callCount == 2)
        coordinator.answer(using: settings, research: true)
        await nextMainTurn()
        #expect(await provider.callCount == 2, "Blank public question must never start research")
        #expect(!coordinator.canInsert)
    }

    @Test
    func ordinaryWritingShowsBusyPinBeforeSilentRouteCompletes() async {
        let settings = fixtureSettings()
        settings.mode = .automatic
        let provider = ControlledProvider(held: [.recognition], route: .none)
        let coordinator = recognitionOnlyCoordinator()
        coordinator.pauseDelay = .zero
        coordinator.providerFactory = { _ in provider }
        coordinator.resolveSource = { $0 }
        let source = selection(region("Ordinary note"))
        coordinator.schedulePause(using: settings) { source }
        await provider.waitForCalls(1)
        #expect(coordinator.region != nil)
        #expect(coordinator.busy)
        #expect(coordinator.pinTitle == "Reading handwriting…")
        await provider.release(.recognition)
        await provider.waitForCalls(2)
        await nextMainTurn()
        #expect(coordinator.region == nil)
        #expect(coordinator.suggestion == nil)
    }

    @Test
    func recallRoutingPreservesSourceAndWaitsForLocalSearch() async {
        let settings = fixtureSettings()
        let provider = ControlledProvider(route: .recall)
        let coordinator = recognitionOnlyCoordinator()
        coordinator.providerFactory = { _ in provider }
        coordinator.resolveSource = { $0 }
        let source = region()
        coordinator.prepare(nil, region: source)
        await idle(coordinator) { coordinator.route(using: settings) }
        #expect(coordinator.region != nil)
        #expect(coordinator.decision?.route == .recall)
        #expect(!coordinator.canInsert)
        #expect(await provider.callCount == 1)
    }

    @Test(arguments: [AssistanceRoute.none])
    func nonAssistanceLeavesNoCanvasSuggestion(route: AssistanceRoute) async {
        let settings = fixtureSettings()
        let provider = ControlledProvider(route: route)
        let coordinator = recognitionOnlyCoordinator()
        coordinator.providerFactory = { _ in provider }
        coordinator.resolveSource = { $0 }
        coordinator.prepare(nil, region: region())
        await idle(coordinator) { coordinator.route(using: settings) }
        #expect(coordinator.region == nil)
        #expect(coordinator.suggestion == nil)
        #expect(!coordinator.canInsert)
        #expect(await provider.callCount == 1, "Silent routes must not start answer or public research calls")
    }
}

/// Uses continuations deliberately: cancelling the caller does not finish a provider response.
private actor ControlledProvider: AssistanceProvider {
    enum Operation: Hashable { case recognition, route, answer }
    private var held: Set<Operation>
    private let resultRoute: AssistanceRoute
    private let recognitionText: String?
    private var pending: [Operation: CheckedContinuation<Void, Never>] = [:]
    private var started: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var callCount = 0
    private(set) var answeredText = ""
    private(set) var answeredWithImage = false
    private(set) var answeredWithResearch = false
    init(held: Set<Operation> = [], route: AssistanceRoute = .quickResponse, recognitionText: String? = nil) {
        self.held = held; resultRoute = route; self.recognitionText = recognitionText
    }
    func waitForCalls(_ count: Int) async {
        guard callCount < count else { return }
        await withCheckedContinuation { started.append((count, $0)) }
    }
    private func begin(_ operation: Operation) async {
        callCount += 1
        let ready = started.filter { $0.0 <= callCount }
        started.removeAll { $0.0 <= callCount }
        for (_, waiter) in ready { waiter.resume() }
        if held.contains(operation) { await withCheckedContinuation { pending[operation] = $0 } }
    }
    func release(_ operation: Operation) {
        held.remove(operation)
        pending.removeValue(forKey: operation)?.resume()
    }
    private(set) var recognitionContext: Data?
    func recognise(image: Data, context: Data?) async throws -> RecognitionResult {
        recognitionContext = context
        return try await recognise(image: image)
    }
    func recognise(image: Data) async throws -> RecognitionResult {
        await begin(.recognition)
        return RecognitionResult(text: recognitionText ?? "Automatic transcription \(callCount)")
    }
    func route(_ text: String, image: Data?) async throws -> RoutingDecision {
        await begin(.route)
        return RoutingDecision(route: resultRoute, confidence: 1)
    }
    func answer(_ text: String, research: Bool, image: Data?, onText: @escaping @Sendable (String) async -> Void) async throws -> AssistanceAnswer {
        await onText("An index")
        let result = try await answer(text, research: research, image: image)
        await onText(result.text)
        return result
    }
    func answer(_ text: String, research: Bool, image: Data?) async throws -> AssistanceAnswer {
        answeredText = text
        answeredWithImage = image != nil
        answeredWithResearch = research
        await begin(.answer)
        return AssistanceAnswer(text: "Delayed answer", citations: [], evidence: [
            Evidence(kind: .fixture, title: "Test source", excerpt: "Deterministic supporting evidence")
        ])
    }
}

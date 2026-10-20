import Testing
import Combine
import UIKit
@testable import ScribbleScout

@Suite("Assistance coordination", .serialized)
@MainActor
struct AssistanceCoordinatorTests {
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
            observer = coordinator.$activity.dropFirst().filter { $0 == nil }.first().sink { _ in
                observer?.cancel(); continuation.resume()
            }
            action()
        }
    }
    private func nextMainTurn() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }

    @Test
    func sourceEditedDuringAnswerCannotBeAccepted() async throws {
        let settings = ScoutSession()
        let provider = ControlledProvider(held: [.answer])
        let coordinator = AssistanceCoordinator()
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
    func cancelledProviderThatIgnoresCancellationCannotPublishItsAnswer() async {
        let settings = ScoutSession()
        let provider = ControlledProvider(held: [.answer])
        let coordinator = AssistanceCoordinator()
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
        let settings = ScoutSession()
        settings.mode = .automatic
        let provider = ControlledProvider(held: [.recognition])
        let coordinator = AssistanceCoordinator()
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
        let settings = ScoutSession()
        settings.mode = .automatic
        let provider = ControlledProvider(held: [.recognition])
        let coordinator = AssistanceCoordinator()
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
        let settings = ScoutSession()
        settings.mode = .automatic
        let provider = ControlledProvider(recognitionText: "Explain TLS security")
        let coordinator = AssistanceCoordinator()
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
        let settings = ScoutSession()
        settings.mode = .automatic
        let provider = ControlledProvider(held: [.answer])
        let coordinator = AssistanceCoordinator()
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
        let settings = ScoutSession()
        settings.mode = .automatic
        let provider = ControlledProvider(held: [.recognition])
        let coordinator = AssistanceCoordinator()
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

    @Test(arguments: [AssistanceRoute.none, .recall])
    func nonAssistanceAndPrivateRecallLeaveNoCanvasSuggestion(route: AssistanceRoute) async {
        let settings = ScoutSession()
        let provider = ControlledProvider(route: route)
        let coordinator = AssistanceCoordinator()
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
    func recognise(image: Data) async throws -> RecognitionResult {
        await begin(.recognition)
        return RecognitionResult(text: recognitionText ?? "Automatic transcription \(callCount)")
    }
    func route(_ text: String, image: Data?) async throws -> RoutingDecision {
        await begin(.route)
        return RoutingDecision(route: resultRoute, confidence: 1)
    }
    func answer(_ text: String, research: Bool, image: Data?) async throws -> AssistanceAnswer {
        await begin(.answer)
        return AssistanceAnswer(text: "Delayed answer", citations: [], evidence: [
            Evidence(kind: .fixture, title: "Test source", excerpt: "Deterministic supporting evidence")
        ])
    }
}

import SwiftUI
import PencilKit

/// Credentials and consent last only for this app session; neither is added to a note.
@MainActor
final class ScoutSession: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case off = "Off", explicit = "Explicit only", automatic = "Automatic"
        var id: Self { self }
    }
    @Published var apiKey: String {
        didSet {
            if oldValue != apiKey && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                consent = true; offline = false; mode = .automatic
            }
        }
    }
    @Published private(set) var hasDevelopmentKey: Bool
    @Published var consent = false
    @Published var offline = false
    @Published var mode: Mode = .automatic
    @Published var scenario: FixtureScenario = .grounded
    @Published var jobs = 0
    let ledger = UsageLedger()
    static let jobLimit = 60
    var canProcess: Bool { mode != .off && (offline || (consent && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)) }
    // A runtime key enables live assistance; explicit Off and consent controls still stop it.
    init(apiKey key: String = DevelopmentCredential.apiKey()) {
        apiKey = key; hasDevelopmentKey = !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        consent = hasDevelopmentKey
        if CommandLine.arguments.contains("--offline-demo") { offline = true; mode = .explicit }
    }
    func forgetKey() { apiKey = ""; hasDevelopmentKey = false; consent = false }
}

enum BlockPlacement: String, CaseIterable, Identifiable {
    case belowWriting = "Below writing", besideSource = "Beside selection", visibleCanvas = "Visible canvas"
    var id: Self { self }
}

struct ScoutSheet: View {
    @ObservedObject var credentials: ScoutSession
    @ObservedObject var coordinator: AssistanceCoordinator
    var sourceSession: ((Evidence) -> NoteSession?)? = nil
    var insert: (Suggestion, BlockPlacement) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var source: Evidence?
    @State private var claimFilter = "All"
    @State private var latestOnly = false
    @State private var settings = false
    @State private var placement: BlockPlacement = .belowWriting

    var body: some View {
        NavigationStack {
            Form {
                if credentials.offline {
                    Section { Label("Fictional offline demo", systemImage: "airplane").font(.headline)
                        Text("Responses and sources are scripted examples. No network request or API key is used.").font(.callout)
                    }
                }
                if let selection = coordinator.selection {
                    Section("Source selection") {
                        Image(uiImage: selection.image).resizable().scaledToFit().frame(maxHeight: 220)
                            .accessibilityLabel("Selected handwriting to recognise")
                        Image(uiImage: selection.contextImage).resizable().scaledToFit().frame(maxHeight: 180)
                            .accessibilityLabel("Whole canvas context sent to Scout")
                        Text("Scout reads the selected handwriting and uses this whole-canvas snapshot as context, including offscreen content. Large canvases are scaled down.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if coordinator.stage == .compose {
                    Section {
                        Button("Recognise handwriting", systemImage: "text.viewfinder") { coordinator.recognise(using: credentials) }
                            .disabled(coordinator.busy || !credentials.canProcess).frame(minHeight: 44)
                            .accessibilityIdentifier("recogniseSelection")
                    } footer: { Text("You can inspect and correct the transcription before asking Scout to use it.") }
                } else {
                    Section {
                        TextField("Recognised text or question", text: Binding(get: { coordinator.transcript }, set: {
                            guard coordinator.transcript != $0 else { return }
                            coordinator.transcript = $0
                            coordinator.transcriptEdited()
                        }), axis: .vertical)
                            .lineLimit(3...10).disabled(coordinator.busy)
                            .accessibilityIdentifier("scoutQuestion")
                        if let uncertainties = coordinator.region?.uncertainty, !uncertainties.isEmpty {
                            Label(uncertainties.joined(separator: "\n"), systemImage: "exclamationmark.triangle")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Button("Use corrected text", systemImage: "arrow.right") { coordinator.route(using: credentials) }
                            .disabled(coordinator.busy || !credentials.canProcess || coordinator.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .frame(minHeight: 44).accessibilityIdentifier("askScout")
                    } header: { Text("Inspect and correct") } footer: {
                        Text("Check names, acronyms, numbers and negation. A recognition error can change the answer.")
                    }
                }
                if !coordinator.streamingText.isEmpty {
                    Section("Scout · responding") {
                        Text(coordinator.streamingText).textSelection(.enabled).accessibilityIdentifier("streamingResponse")
                    }
                }
                if let activity = coordinator.activity {
                    Section {
                        ProgressView(activity)
                        Text("You can close this inspector and keep writing. The source pin will show when Scout is ready.").font(.callout)
                        Button("Cancel request", role: .destructive) { coordinator.cancel() }.frame(minHeight: 44)
                    }
                }
                if let decision = coordinator.decision {
                    Section("Next step · \(decision.route.title)") {
                        if decision.route == .webResearch {
                            Text("Write a public research question. Remove names, private decisions and confidential details. Only the question below is sent for web research.")
                            TextField("Public research question", text: Binding(get: { coordinator.publicQuestion }, set: {
                                guard coordinator.publicQuestion != $0 else { return }
                                coordinator.publicQuestion = $0
                                coordinator.publicQuestionEdited()
                            }), axis: .vertical)
                                .lineLimit(2...6).disabled(coordinator.busy)
                                .accessibilityIdentifier("publicResearchQuestion")
                            Button("Research this public question", systemImage: "globe") { coordinator.answer(using: credentials, research: true) }
                                .disabled(coordinator.busy || !credentials.canProcess || coordinator.publicQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .frame(minHeight: 44).accessibilityIdentifier("researchPublicQuestion")
                            if let url = browserURL { Link("Open public question in browser", destination: url).frame(minHeight: 44) }
                        } else if decision.route == .quickResponse {
                            Button("Write a quick answer", systemImage: "sparkles") { coordinator.answer(using: credentials, research: false) }
                                .disabled(coordinator.busy || !credentials.canProcess).frame(minHeight: 44)
                        } else if decision.route == .clarify {
                            Text("What subject or missing detail should Scout use for this selection?")
                            Button("Defer for now") { coordinator.dismissSuggestion(); dismiss() }.frame(minHeight: 44)
                        }
                        if decision.usedFallback { Text("Routing used Responses because Decisions was unavailable.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Section("Dated local Recall") {
                    Button("Search private notes", systemImage: "clock") { coordinator.recall() }
                        .disabled(coordinator.busy || coordinator.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .frame(minHeight: 44).accessibilityIdentifier("recallNotes")
                    Text("Runs on this iPad. Results retain meeting dates and distinguish proposals, assumptions and settled decisions.").font(.caption)
                    if coordinator.suggestion?.evidence.contains(where: { $0.kind == .note }) == true {
                        Picker("Evidence status", selection: $claimFilter) {
                            ForEach(["All", "Proposal", "Assumption", "Settled decision"], id: \.self) { Text($0) }
                        }
                        Toggle("Latest matching meeting only", isOn: $latestOnly)
                        TextField("Separate public research question", text: Binding(get: { coordinator.publicQuestion }, set: {
                            coordinator.publicQuestion = $0
                            coordinator.publicQuestionEdited()
                        }), axis: .vertical)
                            .accessibilityIdentifier("recallPublicQuestion")
                        Text("Write only public terms. Private excerpts, meeting titles, dates and your selection are never appended to the web query.").font(.caption)
                        Button("Add public web evidence", systemImage: "globe") { coordinator.answer(using: credentials, research: true) }
                            .disabled(coordinator.busy || !credentials.canProcess || coordinator.publicQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .frame(minHeight: 44).accessibilityIdentifier("combineRecallWeb")
                    }
                }
                if let suggestion = coordinator.suggestion, !suggestion.answer.isEmpty {
                    Section(suggestion.request.sourceMode == .notes ? "Dated local excerpts" : (suggestion.isFixture ? "Fictional demo answer" : "AI suggestion")) {
                        if suggestion.request.sourceMode == .notes {
                            Text("\(Set(suggestion.evidence.compactMap(\.canvasID)).count) matching meetings · Ranked by relevance")
                                .font(.subheadline)
                        } else {
                            Text(.init(suggestion.answer)).textSelection(.enabled)
                        }
                        Text(suggestion.caveat).font(.caption).foregroundStyle(.secondary)
                        ForEach(suggestion.evidence.filter { evidence in
                            guard evidence.kind == .note else { return true }
                            let latest = suggestion.evidence.compactMap(\.meetingDate).max()
                            return (claimFilter == "All" || evidence.claim == claimFilter) && (!latestOnly || evidence.meetingDate == latest)
                        }) { evidence in
                            VStack(alignment: .leading, spacing: 8) {
                                Label(evidence.kind == .fixture ? "Fictional source" : (evidence.kind == .web ? "Web source" : "Your notes"),
                                      systemImage: evidence.kind == .web ? "globe" : "doc.text")
                                    .font(.caption.weight(.semibold))
                                if let url = evidence.url {
                                    Link(evidence.title, destination: url).frame(minHeight: 44, alignment: .leading)
                                    Text(url.host ?? "Web source").font(.caption).foregroundStyle(.secondary)
                                }
                                else { Label(evidence.title, systemImage: evidence.kind == .fixture ? "airplane" : "doc.text") }
                                if let date = evidence.meetingDate {
                                    Text(date, format: .dateTime.day().month(.abbreviated).year()).font(.subheadline.weight(.semibold))
                                }
                                if let claim = evidence.claim { Text(claim + (evidence.isFictional == true ? " · Fictional meeting" : "")).font(.caption.weight(.semibold)) }
                                if evidence.canvasID != nil {
                                    Button("Open source region", systemImage: "viewfinder") { source = evidence }
                                        .frame(minHeight: 44).accessibilityIdentifier("openRecallSource")
                                }
                                Text(evidence.excerpt).font(.callout).foregroundStyle(.secondary)
                                if let date = evidence.fetchedAt { Text("Retrieved \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        Picker("Place AI block", selection: $placement) {
                            ForEach(BlockPlacement.allCases) { Text($0.rawValue).tag($0) }
                        }.accessibilityIdentifier("blockPlacement")
                        Button("Insert editable AI block", systemImage: "plus.rectangle.on.rectangle") {
                            guard coordinator.validate(), coordinator.canInsert, let current = coordinator.suggestion else { return }
                            insert(current, placement); coordinator.dismissSuggestion(); dismiss()
                        }
                        .disabled(!coordinator.canInsert).frame(minHeight: 44).accessibilityIdentifier("insertAIBlock")
                    }
                    Section("Follow up with this evidence") {
                        TextField("Follow-up question", text: $coordinator.followUp, axis: .vertical).lineLimit(2...5)
                        Button("Ask using existing evidence") { coordinator.answer(using: credentials, research: false, followUp: true) }
                            .disabled(coordinator.busy || coordinator.followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !credentials.canProcess)
                            .frame(minHeight: 44)
                        Text("Existing sources stay attached. For fresh research, edit and review the public question above.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let message = coordinator.message {
                    Section {
                        Text(message).accessibilityIdentifier("scoutError")
                        if coordinator.suggestion?.state == .failed {
                            Button("Retry") {
                                if coordinator.transcript.isEmpty { coordinator.recognise(using: credentials) }
                                else if coordinator.decision != nil { coordinator.answer(using: credentials, research: coordinator.decision?.route == .webResearch) }
                                else { coordinator.route(using: credentials) }
                            }.frame(minHeight: 44).disabled(coordinator.busy)
                        }
                    }
                }
                Section {
                    Button("Dismiss suggestion", role: .destructive) { coordinator.dismissSuggestion(); dismiss() }.frame(minHeight: 44).accessibilityIdentifier("dismissSuggestion")
                    Button("Mute this topic for 5 minutes") { coordinator.mute(); dismiss() }.frame(minHeight: 44)
                }
            }
            .tint(NotebookTheme.burgundy)
            .navigationTitle("Ask Scout").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Settings", systemImage: "gearshape") { settings = true } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $source) { evidence in
                NavigationStack {
                    if let session = sourceSession?(evidence) {
                        RecallSourceCanvas(session: session, evidence: evidence)
                    } else {
                        ContentUnavailableView("Source changed or unavailable", systemImage: "exclamationmark.triangle", description: Text("Search again to retrieve the current revision."))
                    }
                }
            }
            .sheet(isPresented: $settings) { ScoutSettingsSheet(credentials: credentials, coordinator: coordinator) }
            .task { await coordinator.refreshUsage(credentials) }
            .onChange(of: credentials.canProcess) { _, allowed in
                if allowed && coordinator.selection != nil && coordinator.stage == .compose && !coordinator.busy {
                    coordinator.recognise(using: credentials)
                }
            }
        }
    }
    private var browserURL: URL? {
        let query = coordinator.publicQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }
}

struct ScoutSettingsSheet: View {
    @ObservedObject var credentials: ScoutSession
    @ObservedObject var coordinator: AssistanceCoordinator
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("What Scout does") {
                    Text("Scout watches your notes, not your microphone. It does not record audio.")
                        .accessibilityIdentifier("scoutStatusExplanation")
                    Text("In Automatic mode, Scout reads changed handwriting after a pause. Decisions checks the text and canvas context to choose whether help is needed. Ordinary notes stay quiet; unclear text waits for your review. A useful response appears on the canvas, where you can read, review or insert it.")
                    Text("Live recognition sends the selected handwriting and a whole-canvas snapshot to OpenAI. Automatic research sends the recognised question to web search. Explicit only waits for Ask Scout; Off stops processing. Fictional offline demo uses scripted examples without network requests.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section("Assistance") {
                    Picker("Mode", selection: $credentials.mode) {
                        ForEach(ScoutSession.Mode.allCases) { Text($0.rawValue).tag($0) }
                    }.accessibilityIdentifier("modePicker")
                    Text("A runtime API key enables live Automatic assistance. After a writing pause, Scout reads the changed region with whole-canvas context and streams clear explanations into a canvas card. Clear text can automatically trigger web research, local note recall or a quick answer. Uncertain handwriting waits for review. Off stops assistance; Explicit only waits for Ask Scout.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Fictional offline demo", isOn: $credentials.offline).disabled(coordinator.busy).accessibilityIdentifier("providerMode")
                    if credentials.offline {
                        Picker("Demo scenario", selection: $credentials.scenario) {
                            Text("Grounded example").tag(FixtureScenario.grounded)
                            Text("Ambiguous handwriting").tag(FixtureScenario.ambiguous)
                            Text("Network failure").tag(FixtureScenario.failed)
                            Text("Stale source example").tag(FixtureScenario.stale)
                            Text("Conflicting sources").tag(FixtureScenario.conflicting)
                        }.disabled(coordinator.busy).accessibilityIdentifier("scenarioPicker")
                    }
                }
                if !credentials.offline {
                    Section {
                        if credentials.hasDevelopmentKey { Label("API key available for this session", systemImage: "key") }
                        else { SecureField("Your OpenAI API key", text: $credentials.apiKey).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(coordinator.busy) }
                        if !credentials.apiKey.isEmpty {
                            Button("Forget key", role: .destructive) { coordinator.cancel(); credentials.forgetKey() }.frame(minHeight: 44)
                        }
                        Toggle("Allow OpenAI processing", isOn: $credentials.consent)
                    } header: { Text("Personal prototype · OpenAI") } footer: {
                        Text("Recognition sends the selected handwriting and a whole-canvas snapshot to OpenAI. Routing and quick answers use that snapshot with the corrected text. In Automatic mode, a research decision sends the recognized text as the web research question. Explicit research sends your separately reviewed public question. With a runtime key, live processing and Automatic mode start enabled. Automatic may recognise changed handwriting, research its text, search local notes and stream explanations after a pause. Your key stays in memory until forgotten or the app closes. Responses use store=false; this does not mean zero retention. API use is billed to your OpenAI project.")
                    }
                }
                Section("Session usage · live requests") {
                    LabeledContent("Requests", value: "\(coordinator.usage.requests)")
                    LabeledContent("Input / output tokens", value: "\(coordinator.usage.inputTokens) / \(coordinator.usage.outputTokens)")
                    LabeledContent("Tool calls", value: "\(coordinator.usage.toolCalls)")
                    LabeledContent("Total request time", value: String(format: "%.1f s", coordinator.usage.latencySeconds))
                    if coordinator.usage.unreportedTokenRequests > 0 { Text("\(coordinator.usage.unreportedTokenRequests) requests did not report tokens; totals are partial.").font(.caption) }
                    Text("Token and tool totals are measured when returned by the provider. No dollar estimate is shown. Offline fixtures are excluded. Cancel stops waiting; remote work and billing may continue.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Scout settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: credentials.mode) { _, mode in if mode != .automatic { coordinator.stopAutomatic() }; if mode == .off { coordinator.cancel() } }
            .onChange(of: credentials.consent) { _, allowed in if !allowed && !credentials.offline { coordinator.cancel() } }
            .task { await coordinator.refreshUsage(credentials) }
        }
    }
}


private struct RecallSourceCanvas: View {
    @ObservedObject var session: NoteSession
    let evidence: Evidence
    @StateObject private var controls = CanvasControls()
    @State private var focused = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        InkCanvas(session: session, controls: controls, tool: PKInkingTool(.pen), fingerDrawing: false, readOnly: true)
            .overlay { RecallRegionHighlight(viewport: controls.viewport, bounds: evidence.bounds ?? CanvasBounds()) }
            .navigationTitle(session.note.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Return to Recall") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Show source region") { focus() } }
            }
            .safeAreaInset(edge: .bottom) {
                Text("\(evidence.claim ?? "Note") · Revision \(evidence.revision ?? 0) · Fictional meeting. Highlight marks the cited region.")
                    .font(.caption).padding().frame(maxWidth: .infinity).background(.regularMaterial)
            }
            .onReceive(controls.viewport.$size) { size in
                guard !focused, size.width > 0 else { return }
                focused = true
                focus()
            }
    }

    private func focus() {
        guard let bounds = evidence.bounds else { return }
        controls.navigate(to: CGPoint(x: bounds.x + bounds.width / 2, y: bounds.y + bounds.height / 2))
    }
}

private struct RecallRegionHighlight: View {
    @ObservedObject var viewport: CanvasViewport
    let bounds: CanvasBounds
    var body: some View {
        Rectangle().fill(Color.accentColor.opacity(0.12))
            .overlay(Rectangle().strokeBorder(Color.accentColor, lineWidth: 3))
            .frame(width: bounds.width * viewport.value.zoom, height: bounds.height * viewport.value.zoom)
            .position(x: (bounds.x + bounds.width / 2) * viewport.value.zoom - viewport.value.x,
                      y: (bounds.y + bounds.height / 2) * viewport.value.zoom - viewport.value.y)
            .allowsHitTesting(false).accessibilityLabel("Cited source region").accessibilityIdentifier("recallRegionHighlight")
    }
}

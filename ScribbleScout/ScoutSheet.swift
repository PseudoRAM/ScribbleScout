import SwiftUI

/// Credentials and consent last only for this app session; neither is added to a note.
@MainActor
final class ScoutSession: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case off = "Off", explicit = "Explicit only", automatic = "Automatic (opt in)"
        var id: Self { self }
    }
    @Published var apiKey: String
    @Published private(set) var hasDevelopmentKey: Bool
    @Published var consent = false
    @Published var offline = true
    @Published var mode: Mode = .explicit
    @Published var scenario: FixtureScenario = .grounded
    @Published var jobs = 0
    let ledger = UsageLedger()
    static let jobLimit = 60
    var canProcess: Bool { mode != .off && (offline || (consent && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)) }
    init() {
        let key = DevelopmentCredential.apiKey()
        apiKey = key; hasDevelopmentKey = !key.isEmpty
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
    var insert: (Suggestion, BlockPlacement) -> Void
    @Environment(\.dismiss) private var dismiss
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
                        Text("Only this selected area is sent for recognition. Nearby notebook content is excluded.").font(.caption).foregroundStyle(.secondary)
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
                if let suggestion = coordinator.suggestion, !suggestion.answer.isEmpty {
                    Section(suggestion.isFixture ? "Fictional demo answer" : "AI suggestion") {
                        Text(.init(suggestion.answer)).textSelection(.enabled)
                        Text(suggestion.caveat).font(.caption).foregroundStyle(.secondary)
                        ForEach(suggestion.evidence) { evidence in
                            VStack(alignment: .leading, spacing: 8) {
                                Label(evidence.kind == .fixture ? "Fictional source" : (evidence.kind == .web ? "Web source" : "Your notes"),
                                      systemImage: evidence.kind == .web ? "globe" : "doc.text")
                                    .font(.caption.weight(.semibold))
                                if let url = evidence.url {
                                    Link(evidence.title, destination: url).frame(minHeight: 44, alignment: .leading)
                                    Text(url.host ?? "Web source").font(.caption).foregroundStyle(.secondary)
                                }
                                else { Label(evidence.title, systemImage: evidence.kind == .fixture ? "airplane" : "doc.text") }
                                Text(evidence.excerpt).font(.callout).foregroundStyle(.secondary)
                                if let date = evidence.fetchedAt { Text("Retrieved \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        Picker("Place AI block", selection: $placement) {
                            ForEach(BlockPlacement.allCases) { Text($0.rawValue).tag($0) }
                        }.accessibilityIdentifier("blockPlacement")
                        Button("Insert editable AI block", systemImage: "plus.rectangle.on.rectangle") {
                            guard coordinator.validate(), let current = coordinator.suggestion else { return }
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
            .sheet(isPresented: $settings) { ScoutSettingsSheet(credentials: credentials, coordinator: coordinator) }
            .task { await coordinator.refreshUsage(credentials) }
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
                Section("Assistance") {
                    Picker("Mode", selection: $credentials.mode) {
                        ForEach(ScoutSession.Mode.allCases) { Text($0.rawValue).tag($0) }
                    }.accessibilityIdentifier("modePicker")
                    Text("Explicit only waits for Ask AI. Automatic reads a bounded changed region after a 1.8 second pause, with a 20 second cooldown. It leaves a quiet pin and never opens this inspector or starts web research. Review transcription and a public question before researching.").font(.caption).foregroundStyle(.secondary)
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
                        Text("Recognition sends the selected canvas image to OpenAI. Routing and quick answers send the corrected text. Web research sends only your separately reviewed public question. Automatic mode may recognise and route changed handwriting after a pause. Your key stays in memory until forgotten or the app closes. Responses use store=false; this does not mean zero retention. API use is billed to your OpenAI project.")
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

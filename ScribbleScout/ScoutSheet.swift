import SwiftUI

/// Credentials live only in memory for this notebook session and are never added to a note.
@MainActor
final class ScoutSession: ObservableObject {
    @Published var apiKey: String
    @Published private(set) var hasDevelopmentKey: Bool

    init() {
        let key = DevelopmentCredential.apiKey()
        apiKey = key
        hasDevelopmentKey = !key.isEmpty
    }

    func forgetKey() {
        apiKey = ""
        hasDevelopmentKey = false
    }
    @Published var jobs = 0
    static let jobLimit = 20
}

struct ScoutSheet: View {
    @ObservedObject var credentials: ScoutSession
    var selection: CanvasSelection? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var publicQuestion = ""
    @State private var consent = false
    @State private var includeContext = true
    @State private var decision: RoutingDecision?
    @State private var answer: AssistanceAnswer?
    @State private var message: String?
    @State private var activity: String?
    @State private var task: Task<Void, Never>?
    @State private var generation = UUID()

    private var busy: Bool { activity != nil }
    private var canRequest: Bool {
        consent && !credentials.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && credentials.jobs < ScoutSession.jobLimit && !busy
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if credentials.hasDevelopmentKey {
                        Label("API key available for this session", systemImage: "key")
                    } else {
                        SecureField("Your OpenAI API key", text: $credentials.apiKey)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .disabled(busy).accessibilityLabel("Your OpenAI API key")
                    }
                    if !credentials.apiKey.isEmpty {
                        Button("Forget key", role: .destructive) { cancel(); credentials.forgetKey(); consent = false }
                    }
                    Toggle("Allow OpenAI processing", isOn: $consent).disabled(busy)
                } header: { Text("Personal prototype") } footer: {
                    Text("Your question and the canvas image previewed here, if any, are sent to OpenAI. When nearby context is on, that surrounding area is included too. The rest of your notebook stays on this iPad. Your key stays in memory until you forget it or close the app. API usage is billed to your OpenAI project. Responses use store=false; this does not mean zero retention.")
                }
                if let selection {
                    Section("Selected canvas area") {
                        Image(uiImage: selection.image).resizable().scaledToFit().frame(maxHeight: 240)
                            .accessibilityLabel("Preview of the lassoed content to send to OpenAI")
                        Toggle("Use nearby canvas context", isOn: $includeContext).disabled(busy)
                            .onChange(of: includeContext) { _, _ in clearResult() }
                        if includeContext {
                            Image(uiImage: selection.contextImage).resizable().scaledToFit().frame(maxHeight: 260)
                                .accessibilityLabel("Nearby canvas context with the selected area outlined in burgundy")
                            Text("The outlined area is the focus. Nearby content outside it helps the AI understand your question. This is the image that will be sent.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Only the lassoed content above will be sent.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    TextField("Question or short passage", text: $question, axis: .vertical)
                        .lineLimit(3...8).disabled(busy)
                        .accessibilityIdentifier("scoutQuestion")
                        .onChange(of: question) { _, _ in clearResult() }
                    Button("Ask Scout", systemImage: "sparkles") { classify() }
                        .disabled(!canRequest || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .frame(minHeight: 44).accessibilityIdentifier("askScout")
                } header: { Text("What are you thinking about?") } footer: {
                    Text("Type a question or use the lasso to select handwriting, text, or a sketch. Scout checks whether to answer, research, search your notes, or ask for more context.")
                }
                if let activity {
                    Section {
                        ProgressView(activity).accessibilityLabel(activity)
                        Button("Cancel request", action: cancel).frame(minHeight: 44)
                    }
                }
                if let decision {
                    Section {
                        Label(decision.route.title, systemImage: symbol(decision.route)).font(.headline)
                        if decision.route == .webResearch {
                            Text("Enter a public search question. Remove names, private decisions, and confidential details. Only this question will be sent for web research.")
                            TextField("Public research question", text: $publicQuestion, axis: .vertical)
                                .lineLimit(2...6).disabled(busy)
                                .onChange(of: publicQuestion) { _, _ in answer = nil; message = nil }
                            Button("Research the web", systemImage: "globe") { respond(research: true) }
                                .disabled(!canRequest || publicQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .frame(minHeight: 44)
                            if let url = browserURL {
                                Link("Open in browser", destination: url).frame(minHeight: 44)
                            }
                        } else if decision.route == .recall {
                            Text("This needs your private notebook history. Close Scout and use Find a note in the notebook menu. No public search was started.")
                        } else if decision.route == .clarify {
                            Text("Add the subject and the specific question, then ask again. Scout will wait for more context.")
                        } else if decision.route == .none {
                            Text("This looks like a note to keep writing. No answer or research was started.")
                        }
                        if decision.usedFallback {
                            Text("Routed with Responses because Decisions was unavailable.").font(.caption).foregroundStyle(.secondary)
                        }
                    } header: { Text("Next step") }
                }
                if let answer {
                    Section {
                        Text(.init(answer.text)).textSelection(.enabled)
                        ForEach(answer.citations, id: \.url) { citation in
                            Link(citation.title, destination: citation.url).frame(minHeight: 44, alignment: .leading)
                        }
                    } header: { Text(answer.citations.isEmpty ? "AI answer · no web search" : "AI research · web sources") }
                }
                if let message {
                    Section { Text(message).foregroundStyle(.red).accessibilityIdentifier("scoutError") }
                }
                Section {
                    Text("\(credentials.jobs) of \(ScoutSession.jobLimit) jobs used this session").font(.caption).foregroundStyle(.secondary)
                    Text("Cancel stops waiting for the result; remote processing and billing may continue. You can retry explicitly. No requests run automatically while you write.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .tint(NotebookTheme.burgundy)
            .navigationTitle("Ask Scout").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { cancel(); dismiss() } } }
            .onAppear {
                if selection != nil && question.isEmpty {
                    question = "Answer any question written in this selection; otherwise briefly explain the selected content."
                }
            }
            .onDisappear(perform: cancel)
        }
    }

    private var browserURL: URL? {
        let query = publicQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }

    private func classify() {
        clearResult()
        let context = selection != nil && includeContext
            ? "The burgundy outline marks the selected content. Focus on that content; consider the surrounding canvas as context. " : ""
        let input = context + question
        let image = includeContext ? selection?.contextPNG : selection?.png
        run(activity: "Checking how to help…") { provider in
            let result = try await provider.route(input, image: image)
            try Task.checkCancellation()
            decision = result
            if result.route == .quickResponse {
                guard credentials.jobs < ScoutSession.jobLimit else { message = "Session limit reached. Start a new app session to continue."; return }
                credentials.jobs += 1
                activity = "Writing a quick answer…"
                let response = try await provider.answer(input, research: false, image: image)
                try Task.checkCancellation()
                answer = response
            }
        }
    }

    private func respond(research: Bool) {
        let input = research ? publicQuestion : question
        answer = nil
        run(activity: "Researching the web…") { provider in
            let response = try await provider.answer(input, research: research)
            try Task.checkCancellation()
            answer = response
        }
    }

    private func run(activity label: String, operation: @escaping @MainActor (OpenAIAssistance) async throws -> Void) {
        guard canRequest else { return }
        credentials.jobs += 1
        message = nil
        activity = label
        let id = UUID()
        generation = id
        let provider = OpenAIAssistance(apiKey: credentials.apiKey)
        task = Task { @MainActor in
            do { try await operation(provider) }
            catch {
                if !Task.isCancelled && generation == id {
                    message = (error as? AssistanceError)?.localizedDescription ?? "Could not connect to OpenAI. Check your connection and try again."
                }
            }
            guard generation == id else { return }
            activity = nil
            task = nil
        }
    }

    private func clearResult() {
        decision = nil
        answer = nil
        message = nil
        publicQuestion = ""
    }

    private func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        activity = nil
    }

    private func symbol(_ route: AssistanceRoute) -> String {
        switch route {
        case .quickResponse: "sparkles"
        case .webResearch: "globe"
        case .recall: "clock"
        case .clarify: "questionmark.bubble"
        case .none: "pencil"
        }
    }
}

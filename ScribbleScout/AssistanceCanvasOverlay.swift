import SwiftUI

/// Pins and editable blocks use the same world coordinates as ink.
struct AssistanceCanvasOverlay: View {
    @ObservedObject var session: NoteSession
    @ObservedObject var credentials: ScoutSession
    @ObservedObject var coordinator: AssistanceCoordinator
    @ObservedObject var viewport: CanvasViewport
    let controls: CanvasControls
    var selectionMode = false
    var openInspector: () -> Void
    var insert: (Suggestion, BlockPlacement) -> Void
    @State private var showingStatus = false
    @State private var editing: InsertedBlock?
    @GestureState private var blockDrag: [UUID: CGSize] = [:]

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(session.note.blocks ?? []) { block in
                    blockView(block)
                }

            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .coordinateSpace(name: "blockCanvas")
            .overlay(alignment: .topLeading) {
                if let region = coordinator.region, coordinator.showsCanvasResponse {
                    let source = screenRect(region.bounds)
                    let width = min(460, max(0, geometry.size.width - 32))
                    let height = min(520, max(0, geometry.size.height - 32))
                    responseCard
                        .frame(width: width, height: height)
                        .offset(x: max(16, min(source.minX, geometry.size.width - width - 16)),
                                y: max(16, min(source.maxY + 16, geometry.size.height - height - 16)))
                }
            }
            .overlay(alignment: .topTrailing) {
                if let phase = coordinator.workPhase {
                    HStack(spacing: 8) {
                        activitySpinner(phase)
                        Text(phase.label).font(.caption.weight(.medium))
                        Button { coordinator.cancel() } label: {
                            Image(systemName: "stop.circle").frame(width: 44, height: 44)
                        }.accessibilityLabel("Stop Scout")
                    }
                    .padding(.leading, 16)
                    .foregroundStyle(phase.isAction ? NotebookTheme.burgundy : NotebookTheme.muted)
                    .background(.regularMaterial, in: Capsule()).padding(16)
                    .accessibilityIdentifier("scoutActivity")
                } else if !coordinator.showsCanvasResponse {
                    HStack(spacing: 8) {
                        Button { showingStatus = true } label: {
                            Label(statusTitle, systemImage: "info.circle")
                                .font(.callout.weight(.medium)).frame(minHeight: 44)
                        }
                        .accessibilityHint("Explains Scout’s mode and what is sent for processing")
                        .accessibilityIdentifier("scoutStatus")
                        if credentials.mode == .automatic {
                            Button { credentials.mode = .explicit } label: {
                                Image(systemName: "pause.fill").frame(width: 44, height: 44)
                            }.accessibilityLabel("Pause automatic Scout")
                        }
                        if coordinator.region != nil {
                            Button("Review", action: openInspector).frame(minHeight: 44)
                        }
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 16).foregroundStyle(NotebookTheme.burgundy)
                    .background(.regularMaterial, in: Capsule()).padding(16)
                }
            }
        }
        .popover(isPresented: $showingStatus) {
            ScoutSettingsSheet(credentials: credentials, coordinator: coordinator)
                .frame(idealWidth: 380, idealHeight: 520)
                .presentationCompactAdaptation(.sheet)
        }
        .sheet(item: $editing) { block in
            AIBlockEditor(block: block, session: session, controls: controls)
        }
    }
    private func activitySpinner(_ phase: AssistanceCoordinator.WorkPhase) -> some View {
        ProgressView().controlSize(.small)
            .tint(phase.isAction ? NotebookTheme.burgundy : NotebookTheme.muted)
            .accessibilityLabel(phase.label)
    }

    private var statusTitle: String {
        if credentials.mode == .off { return "Scout · off" }
        if !credentials.canProcess { return credentials.apiKey.isEmpty ? "Scout · add API key" : "Scout · processing off" }
        if coordinator.region != nil { return "Scout · review" }
        if credentials.offline { return "Scout · fictional demo" }
        return credentials.mode == .automatic ? "Scout · watching notes" : "Scout · ready"
    }

    private var responseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(NotebookTheme.burgundy)
                Text(coordinator.suggestion?.isFixture == true ? "Scout · fictional example" : "Scout")
                    .font(.headline)
                Spacer(minLength: 8)
                Button { coordinator.dismissSuggestion() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }.accessibilityLabel("Dismiss Scout response")
            }
            .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !coordinator.transcript.isEmpty {
                        Text(coordinator.transcript).font(.caption).foregroundStyle(.secondary)
                    }
                    if !coordinator.streamingText.isEmpty {
                        Text(coordinator.streamingText).font(.body).frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("streamingResponse")
                    } else if let suggestion = coordinator.suggestion, !suggestion.answer.isEmpty {
                        Text(.init(suggestion.answer)).font(.body).textSelection(.enabled)
                        Text(suggestion.caveat).font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("scoutResponseEnd")
                    } else if let activity = coordinator.activity {
                        Text(activity).font(.body).foregroundStyle(.secondary)
                        Text("Keep writing. Your response will appear here.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let phase = coordinator.workPhase, phase.isAction {
                        HStack(spacing: 8) {
                            activitySpinner(phase)
                            Text(phase.label).font(.caption).foregroundStyle(.secondary)
                        }.accessibilityIdentifier("scoutSectionActivity")
                    }
                    if let message = coordinator.message {
                        Label(message, systemImage: coordinator.suggestion?.state == .failed ? "exclamationmark.triangle" : "info.circle")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("scoutResponseScroll")
            ViewThatFits(in: .horizontal) {
                responseActions
                VStack(alignment: .leading, spacing: 8) { insertButton; reviewButton }
            }
            .font(.callout.weight(.semibold)).foregroundStyle(NotebookTheme.burgundy)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.primary)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(NotebookTheme.burgundy.opacity(0.25)))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scoutResponseCard")
    }

    private var insertButton: some View {
        Button("Insert", systemImage: "plus.rectangle.on.rectangle") {
            guard coordinator.validate(), coordinator.canInsert, let suggestion = coordinator.suggestion else { return }
            insert(suggestion, .belowWriting)
            coordinator.dismissSuggestion()
        }
        .disabled(!coordinator.canInsert)
        .frame(minHeight: 44)
        .accessibilityLabel("Insert editable AI block")
        .accessibilityIdentifier("insertCanvasAIBlock")
    }

    private var reviewButton: some View {
        Button("Review", systemImage: "text.viewfinder", action: openInspector)
            .frame(minHeight: 44).accessibilityIdentifier("assistancePin")
    }

    private var responseActions: some View {
        HStack(spacing: 12) {
            insertButton
            reviewButton
            Spacer()
            if coordinator.busy {
                Button("Stop", systemImage: "stop.circle") { coordinator.cancel() }.frame(minHeight: 44)
            }
        }
    }

    private func blockView(_ block: InsertedBlock) -> some View {
        let rect = screenRect(block.bounds)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(block.isFixture ? "Fictional demo · AI block" : "AI block", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("insertedAIBlock")
                Spacer(minLength: 4)
                Button { editing = block } label: {
                    Image(systemName: "pencil").frame(width: 44, height: 44)
                }.accessibilityLabel("Edit AI block").accessibilityIdentifier("editAIBlock")
            }
            Text(block.body).font(.callout).lineLimit(6).foregroundStyle(NotebookTheme.ink)
            Text(block.caveat).font(.caption).lineLimit(2).foregroundStyle(.secondary)
            if !block.evidence.isEmpty {
                Text("\(block.evidence.count) attached source\(block.evidence.count == 1 ? "" : "s") · Edit to inspect")
                    .font(.caption).foregroundStyle(NotebookTheme.burgundy)
            }
        }
        .padding(12).frame(width: max(240, min(460, rect.width)), alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(NotebookTheme.burgundy.opacity(0.3), lineWidth: 1))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("blockCanvas"))
            .updating($blockDrag) { value, state, _ in state[block.id] = value.translation }
            .onEnded { value in
                move(block, by: value.translation)
            }, including: selectionMode ? .all : .subviews)
        .offset(x: rect.minX + (blockDrag[block.id]?.width ?? 0),
                y: rect.minY + (blockDrag[block.id]?.height ?? 0))
        .accessibilityHint(selectionMode ? "Drag to move this AI block." : "")
        .accessibilityAction(named: "Move left") { move(block, by: CGSize(width: -44, height: 0)) }
        .accessibilityAction(named: "Move right") { move(block, by: CGSize(width: 44, height: 0)) }
        .accessibilityAction(named: "Move up") { move(block, by: CGSize(width: 0, height: -44)) }
        .accessibilityAction(named: "Move down") { move(block, by: CGSize(width: 0, height: 44)) }
    }

    private func move(_ block: InsertedBlock, by translation: CGSize) {
        let zoom = max(0.15, viewport.value.zoom)
        session.moveBlock(block.id, to: CanvasBounds(block.bounds.cgRect.offsetBy(
            dx: translation.width / zoom, dy: translation.height / zoom)), undoManager: controls.undoManager)
        controls.refresh()
    }

    private func screenRect(_ bounds: CanvasBounds) -> CGRect {
        CGRect(x: bounds.x * viewport.value.zoom - viewport.value.x,
               y: bounds.y * viewport.value.zoom - viewport.value.y,
               width: bounds.width * viewport.value.zoom, height: bounds.height * viewport.value.zoom)
    }
}

private struct AIBlockEditor: View {
    let block: InsertedBlock
    @ObservedObject var session: NoteSession
    let controls: CanvasControls
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section(block.isFixture ? "Fictional demo · editable AI block" : "Editable AI block") {
                    TextEditor(text: $text).frame(minHeight: 200).accessibilityLabel("AI block text")
                        .accessibilityIdentifier("aiBlockText")
                    Text(block.caveat).font(.caption).foregroundStyle(.secondary)
                }
                Section("Original evidence") {
                    ForEach(block.evidence) { evidence in
                        VStack(alignment: .leading, spacing: 6) {
                            if let url = evidence.url {
                                Link(evidence.title, destination: url).frame(minHeight: 44)
                                Text(url.host ?? "Web source").font(.caption).foregroundStyle(.secondary)
                            }
                            else { Text(evidence.title).font(.headline) }
                            if !evidence.excerpt.isEmpty { Text(evidence.excerpt).font(.callout) }
                            if let date = evidence.fetchedAt { Text("Retrieved \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    Text("Editing this block preserves its source selection, evidence and acceptance time. It records a new edit time.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button("Move block to visible canvas") {
                        let viewport = controls.viewport
                        let zoom = max(0.15, viewport.value.zoom)
                        session.moveBlock(block.id, to: CanvasBounds(x: (viewport.value.x + 48) / zoom,
                                          y: (viewport.value.y + 72) / zoom, width: block.bounds.width,
                                          height: block.bounds.height), undoManager: controls.undoManager)
                        controls.refresh(); dismiss()
                    }.frame(minHeight: 44)
                    Button("Delete block", role: .destructive) {
                        session.deleteBlock(block.id, undoManager: controls.undoManager); controls.refresh(); dismiss()
                    }.frame(minHeight: 44)
                }
            }
            .navigationTitle("AI block").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { session.updateBlock(block.id, body: text, undoManager: controls.undoManager); controls.refresh(); dismiss() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { text = block.body }
        }
    }

}

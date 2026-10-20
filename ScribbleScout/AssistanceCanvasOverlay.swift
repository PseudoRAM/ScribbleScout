import SwiftUI

/// Pins and editable blocks use the same world coordinates as ink.
struct AssistanceCanvasOverlay: View {
    @ObservedObject var session: NoteSession
    @ObservedObject var credentials: ScoutSession
    @ObservedObject var coordinator: AssistanceCoordinator
    @ObservedObject var viewport: CanvasViewport
    let controls: CanvasControls
    var openInspector: () -> Void
    @State private var editing: InsertedBlock?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(session.note.blocks ?? []) { block in
                    blockView(block)
                }

            }
            .overlay(alignment: .topLeading) {
                if let region = coordinator.region,
                   coordinator.workPhase?.isAction == true || !coordinator.busy {
                    let source = screenRect(region.bounds)
                    let width = min(420, max(0, geometry.size.width - 32))
                    let height = min(280, geometry.size.height * 0.42)
                    responseCard(height: height)
                        .frame(width: width)
                        .frame(maxHeight: max(0, geometry.size.height - 80))
                        .offset(x: max(16, min(source.minX, geometry.size.width - width - 16)),
                                y: max(64, min(source.maxY + 16, geometry.size.height - height - 190)))
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
                } else if coordinator.region == nil && credentials.mode == .automatic {
                    HStack(spacing: 8) {
                        Label(credentials.offline ? "Scout · fictional demo" : (credentials.canProcess ? "Scout · listening" : "Scout · add API key"), systemImage: "waveform")
                            .font(.callout.weight(.medium))
                        Button { credentials.mode = .explicit } label: {
                            Image(systemName: "pause.fill").frame(width: 44, height: 44)
                        }.accessibilityLabel("Pause automatic Scout")
                    }
                    .padding(.leading, 16).foregroundStyle(NotebookTheme.burgundy)
                    .background(.regularMaterial, in: Capsule()).padding(16)
                }
            }
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

    private func responseCard(height: CGFloat) -> some View {
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
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !coordinator.transcript.isEmpty {
                        Text(coordinator.transcript).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if !coordinator.streamingText.isEmpty {
                        Text(coordinator.streamingText).font(.body).frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("streamingResponse")
                    } else if let suggestion = coordinator.suggestion, !suggestion.answer.isEmpty {
                        Text(.init(suggestion.answer)).font(.body).textSelection(.enabled)
                        Text(suggestion.caveat).font(.caption).foregroundStyle(.secondary)
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
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: height)
            HStack(spacing: 12) {
                Button("Review", systemImage: "text.viewfinder", action: openInspector)
                    .frame(minHeight: 44).accessibilityIdentifier("assistancePin")
                Spacer()
                if coordinator.busy {
                    Button("Stop", systemImage: "stop.circle") { coordinator.cancel() }.frame(minHeight: 44)
                } else if coordinator.suggestion?.state == .failed {
                    Button("Retry") { coordinator.recognise(using: credentials) }.frame(minHeight: 44)
                }
            }
            .font(.callout.weight(.semibold)).foregroundStyle(NotebookTheme.burgundy)
        }
        .padding(16)
        .foregroundStyle(.primary)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(NotebookTheme.burgundy.opacity(0.25)))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scoutResponseCard")
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
        .offset(x: rect.minX, y: rect.minY)
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

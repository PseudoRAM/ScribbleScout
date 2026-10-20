import SwiftUI

/// Pins and editable blocks use the same world coordinates as ink.
struct AssistanceCanvasOverlay: View {
    @ObservedObject var session: NoteSession
    @ObservedObject var coordinator: AssistanceCoordinator
    @ObservedObject var viewport: CanvasViewport
    let controls: CanvasControls
    var openInspector: () -> Void
    @State private var editing: InsertedBlock?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(session.note.blocks ?? []) { block in
                    let rect = screenRect(block.bounds)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(block.isFixture ? "Fictional demo · AI block" : "AI block", systemImage: "sparkles")
                                .font(.caption.weight(.semibold))
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
                    .accessibilityIdentifier("insertedAIBlock")
                }
                if let region = coordinator.region, coordinator.suggestion?.state != .dismissed,
                   coordinator.decision?.route != AssistanceRoute.none {
                    let rect = screenRect(region.bounds)
                    if rect.intersects(CGRect(origin: .zero, size: geometry.size)) {
                        Button(action: openInspector) {
                            HStack(spacing: 8) {
                                if coordinator.busy { ProgressView().controlSize(.small) }
                                else { Image(systemName: coordinator.suggestion?.state == .stale ? "exclamationmark.triangle" : "sparkles") }
                                Text(coordinator.pinTitle).font(.callout.weight(.semibold))
                            }
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(.regularMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(NotebookTheme.burgundy.opacity(0.45), lineWidth: 1))
                        }
                        .buttonStyle(.plain).foregroundStyle(NotebookTheme.burgundy)
                        .offset(x: max(8, min(rect.maxX - 170, geometry.size.width - 220)),
                                y: max(8, min(rect.maxY + 8, geometry.size.height - 64)))
                        .accessibilityLabel(coordinator.pinTitle).accessibilityIdentifier("assistancePin")
                    }
                }
            }
        }
        .sheet(item: $editing) { block in
            AIBlockEditor(block: block, session: session, controls: controls)
        }
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

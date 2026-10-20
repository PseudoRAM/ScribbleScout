import PencilKit
import PhotosUI
import SwiftUI

struct NotebookView: View {
    @ObservedObject var store: NotebookStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var searchFocused: Bool
    @State private var search = ""
    @State private var showingNotebook = false
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var pendingDeletion: Set<UUID> = []
    @State private var sort = LibrarySort.recent
    @StateObject private var scout = ScoutSession()

    private enum LibrarySort: String, CaseIterable {
        case recent = "Recently edited", oldest = "Oldest first", title = "Title"
    }

    private var filteredNotes: [NoteRecord] {
        let notes = store.searchableNotes
        let matches = Set(store.searchMatches.map(\.id))
        let visible = isFiltering ? notes.filter { matches.contains($0.id) } : notes
        return visible.sorted {
            switch sort {
            case .recent: return $0.updatedAt > $1.updatedAt
            case .oldest: return $0.updatedAt < $1.updatedAt
            case .title: return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
    }

    private var isFiltering: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var deletionTitle: String {
        if pendingDeletion.count == 1,
           let note = store.searchableNotes.first(where: { pendingDeletion.contains($0.id) }) {
            return "Delete “\(note.title.isEmpty ? "Untitled note" : note.title)”?"
        }
        return "Delete \(pendingDeletion.count) notes?"
    }

    var body: some View {
        ZStack {
            if let session = store.current {
                NoteEditor(session: session, scout: scout, store: store) {
                    guard session.flush() else { store.issue = session.saveError; return }
                    searchFocused = false
                    showingNotebook = true
                }
                .id(session.id)
                .accessibilityHidden(showingNotebook)
                .allowsHitTesting(!showingNotebook)
            }
            if showingNotebook || store.current == nil {
                library
            }
        }
        .preferredColorScheme(.light)
        .tint(NotebookTheme.burgundy)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onChange(of: search) { _, query in store.search(query) }
        .alert(deletionTitle, isPresented: Binding(
            get: { !pendingDeletion.isEmpty },
            set: { if !$0 { pendingDeletion = [] } }
        )) {
            Button("Cancel", role: .cancel) { pendingDeletion = [] }
            Button("Delete", role: .destructive) {
                store.delete(pendingDeletion)
                selection.formIntersection(Set(store.notes.map(\.id)))
                if selection.isEmpty { selecting = false }
                pendingDeletion = []
            }
        } message: {
            Text("This permanently removes the selected notes, including their handwriting, photos and saved Scout blocks, from this iPad. This cannot be undone.")
        }
        .alert("Notebook notice", isPresented: Binding(get: { store.issue != nil }, set: { if !$0 { store.issue = nil } })) {
            Button("OK") { store.issue = nil }
        } message: { Text(store.issue ?? "") }
    }

    private var library: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 600 || dynamicTypeSize.isAccessibilitySize
            let inset: CGFloat = compact ? 20 : 40
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    libraryHeader(compact: compact)
                        .padding(.bottom, 24)
                    Group {
                        if compact {
                            VStack(alignment: .leading, spacing: 12) { searchField; libraryActions }
                        } else {
                            HStack(spacing: 16) { searchField; libraryActions.fixedSize(horizontal: true, vertical: false) }
                        }
                    }
                    .padding(.bottom, 20)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(selecting ? "\(selection.count) selected" : "\(filteredNotes.count) \(filteredNotes.count == 1 ? "note" : "notes")")
                            .font(.subheadline.weight(.medium))
                        if selecting {
                            HStack(spacing: 16) {
                                Button("Select all shown") { selection.formUnion(filteredNotes.map(\.id)) }
                                    .disabled(filteredNotes.isEmpty)
                                    .frame(minHeight: 44)
                                Button("Clear") { selection = [] }
                                    .disabled(selection.isEmpty).frame(minHeight: 44)
                            }
                        }
                    }
                    .foregroundStyle(NotebookTheme.muted)
                    if isFiltering {
                        HStack(spacing: 8) {
                            if store.isSearching { ProgressView().controlSize(.small) }
                            Text(store.searchStatus).accessibilityIdentifier("searchStatus")
                        }
                        .font(.caption).foregroundStyle(NotebookTheme.muted)
                        .padding(.bottom, 12)
                    }
                    if filteredNotes.isEmpty && !store.isSearching {
                        ContentUnavailableView {
                            Label(isFiltering ? "No notes found" : "A little room to think.",
                                  systemImage: isFiltering ? "magnifyingglass" : "pencil.and.scribble")
                        } description: {
                            Text(isFiltering ? "Try another word from a title or typed note." : "Start a fresh page for your next idea.")
                        } actions: {
                            if isFiltering {
                                Button("Show all notes") { search = "" }
                            } else {
                                Button("Create your first note", action: createNote)
                                    .buttonStyle(.borderedProminent).foregroundStyle(.white)
                            }
                        }
                        .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: compact ? 260 : 300), spacing: 16)], spacing: 16) {
                            ForEach(filteredNotes) { note in noteCard(note) }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, inset).padding(.top, compact ? 20 : 32)
                .frame(maxWidth: 1400).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 8) {
                    Label("Saved on this iPad", systemImage: "internaldrive")
                    Spacer(minLength: 0)
                    if !compact { Text("Your ideas, all in one place.") }
                }
                .font(.caption).foregroundStyle(NotebookTheme.muted)
                .padding(.vertical, 16).padding(.horizontal, inset)
                .background(Color(uiColor: NotebookTheme.paper))
                .overlay(alignment: .top) { Divider() }
            }
            .background(Color(uiColor: NotebookTheme.paper).ignoresSafeArea())
            .foregroundStyle(NotebookTheme.ink)
        }
        .accessibilityIdentifier("notebookNavigation")
    }

    private func libraryHeader(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    libraryBrand.fixedSize()
                    Spacer(minLength: 16)
                    backToNoteButton.fixedSize()
                }
                VStack(alignment: .leading, spacing: 12) {
                    libraryBrand
                    backToNoteButton
                }
            }
            if compact {
                VStack(alignment: .leading, spacing: 16) { libraryTitle; newNoteButton }
            } else {
                HStack(alignment: .bottom) { libraryTitle; Spacer(minLength: 24); newNoteButton }
            }
        }
    }

    private var libraryBrand: some View {
        HStack(spacing: 12) {
            Image("NotebookAppIcon").resizable().scaledToFit().frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
            Text("Scribble Scout").font(.headline)
        }
    }

    @ViewBuilder private var backToNoteButton: some View {
        if store.current != nil {
            Button {
                selecting = false
                selection = []
                showingNotebook = false
            } label: {
                Label("Back to note", systemImage: "arrow.right")
                    .font(.subheadline.weight(.medium)).frame(minHeight: 44)
            }
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityIdentifier("backToNote")
        }
    }

    private var libraryTitle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your notebook").font(.largeTitle.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text("Space for every thought.").font(.body).foregroundStyle(NotebookTheme.muted)
        }
    }

    private var newNoteButton: some View {
        Button(action: createNote) {
            Label("New note", systemImage: "square.and.pencil")
                .font(.body.weight(.semibold)).foregroundStyle(.white).padding(.horizontal, 8).frame(minHeight: 44)
        }
        .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 12))
        .keyboardShortcut("n", modifiers: .command).accessibilityIdentifier("newNote")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(NotebookTheme.muted)
            TextField("Find a note", text: $search)
                .focused($searchFocused).accessibilityLabel("Find a note")
                .autocorrectionDisabled().submitLabel(.search)
            if !search.isEmpty {
                Button { search = ""; searchFocused = true } label: {
                    Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                }
                .foregroundStyle(NotebookTheme.muted).accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 16).padding(.trailing, search.isEmpty ? 16 : 0).frame(minWidth: 200, minHeight: 48)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(searchFocused ? NotebookTheme.burgundy : NotebookTheme.ink.opacity(0.16), lineWidth: 1))
    }

    private var libraryActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { sortControl; selectionControl; deleteControl }
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 8) { sortControl; selectionControl; deleteControl }
        }
        .font(.subheadline.weight(.medium))
    }

    private var sortControl: some View {
        Menu {
            Picker("Sort notes", selection: $sort) {
                ForEach(LibrarySort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down").frame(minHeight: 44)
        }
        .accessibilityLabel("Sort notes: \(sort.rawValue)")
    }

    private var selectionControl: some View {
        Button(selecting ? "Done" : "Select") {
            selecting.toggle()
            selection = []
        }
        .frame(minHeight: 44).disabled(store.notes.isEmpty)
        .accessibilityIdentifier("selectNotes")
    }

    @ViewBuilder private var deleteControl: some View {
        if selecting {
            Button(role: .destructive) { pendingDeletion = selection } label: {
                Label("Delete", systemImage: "trash").frame(minHeight: 44)
                    .foregroundStyle(.red)
            }
            .disabled(selection.isEmpty).accessibilityIdentifier("deleteSelectedNotes")
        }
    }

    private func noteCard(_ note: NoteRecord) -> some View {
        let selected = selection.contains(note.id)
        let current = note.id == store.current?.id
        let excerpt = isFiltering ? store.searchMatches.first(where: { $0.id == note.id })?.excerpt : nil
        let preview = excerpt ?? (note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (note.template == .checkout ? "A sketch of the checkout flow" : "A fresh page for your ideas.") : note.text)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if selecting {
                    if selected { selection.remove(note.id) } else { selection.insert(note.id) }
                } else {
                    store.open(note.id)
                    if store.current?.id == note.id { showingNotebook = false }
                }
            } label: {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: note.template == .checkout ? "rectangle.3.group" : "doc.text")
                            .font(.title2).foregroundStyle(NotebookTheme.burgundy)
                        Spacer()
                        if selecting {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.title2).foregroundStyle(NotebookTheme.burgundy)
                        } else if current {
                            Label("Open", systemImage: "circle.fill").font(.caption.weight(.medium))
                                .foregroundStyle(NotebookTheme.burgundy)
                        }
                    }
                    Text(note.title.isEmpty ? "Untitled note" : note.title)
                        .font(.title3.weight(.semibold)).lineLimit(2, reservesSpace: true)
                    Text(preview.replacingOccurrences(of: "\n", with: " "))
                        .font(.body).foregroundStyle(NotebookTheme.muted).lineLimit(3, reservesSpace: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits((selecting ? selected : current) ? .isSelected : [])
            .accessibilityHint(selecting ? "Select or deselect this note" : "Open note")
            .accessibilityIdentifier("note-\(note.id)")
            Divider().padding(.horizontal, 20)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.updatedAt, format: .dateTime.month(.abbreviated).day().year())
                    Text(note.template == .checkout ? "Reference page" : "\(note.paper.title) paper")
                }
                .font(.caption).foregroundStyle(NotebookTheme.muted)
                Spacer(minLength: 8)
                if !selecting {
                    Button(role: .destructive) { pendingDeletion = [note.id] } label: {
                        Image(systemName: "trash").foregroundStyle(.red).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Delete \(note.title.isEmpty ? "Untitled note" : note.title)")
                    .accessibilityIdentifier("delete-\(note.id)")
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .background(selected ? NotebookTheme.burgundy.opacity(0.06) : .white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .strokeBorder(selected ? NotebookTheme.burgundy : NotebookTheme.ink.opacity(0.12), lineWidth: selected ? 2 : 1))
    }

    private func createNote() {
        let previous = store.current?.id
        store.create()
        if store.current?.id != previous {
            selecting = false
            selection = []
            showingNotebook = false
        }
    }
}

/// Only the moving annotations observe the viewport; navigation leaves the editor and toolbar alone.
private struct CanvasAnnotations: View {
    let session: NoteSession
    @ObservedObject var viewport: CanvasViewport
    var onAction: (ContextAction) -> Void

    var body: some View {
        CheckoutAnnotations(session: session, onAction: onAction)
            .scaleEffect(viewport.value.zoom, anchor: .topLeading)
            .offset(x: -viewport.value.x, y: -viewport.value.y)
    }
}

private struct CanvasMinimap: View {
    let controls: CanvasControls
    @ObservedObject var viewport: CanvasViewport
    @ObservedObject var overview: CanvasOverview
    @State private var collapsed = true
    @State private var dragBounds: CGRect?

    private var visibleRect: CGRect {
        let zoom = max(0.15, viewport.value.zoom)
        return CGRect(x: viewport.value.x / zoom, y: viewport.value.y / zoom,
                      width: viewport.size.width / zoom, height: viewport.size.height / zoom)
    }

    var body: some View {
        VStack(spacing: 0) {
            if collapsed {
                Button { collapsed = false } label: {
                    Image(systemName: "map").frame(width: 44, height: 44)
                }.accessibilityLabel("Show canvas minimap")
            } else {
                HStack(spacing: 0) {
                    Button(action: controls.resetZoom) {
                        Image(systemName: "house").frame(width: 44, height: 44)
                    }.accessibilityLabel("Return to canvas start")
                    Text("Canvas").font(.caption.weight(.semibold))
                    Spacer(minLength: 0)
                    Button { collapsed = true } label: {
                        Image(systemName: "chevron.down").frame(width: 44, height: 44)
                    }.accessibilityLabel("Hide canvas minimap")
                }
                GeometryReader { geometry in
                    let map = CanvasMapGeometry(bounds: dragBounds ?? overview.snapshot.bounds, size: geometry.size)
                    Canvas { context, _ in
                        context.fill(Path(map.map(map.bounds)), with: .color(Color(uiColor: NotebookTheme.paper)))
                        if let image = overview.snapshot.image {
                            context.draw(Image(uiImage: image), in: map.map(overview.snapshot.imageBounds))
                        }
                        let visible = map.map(visibleRect)
                        context.fill(Path(visible), with: .color(NotebookTheme.burgundy.opacity(0.12)))
                        context.stroke(Path(visible), with: .color(NotebookTheme.burgundy), lineWidth: 1.5)
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragBounds == nil { dragBounds = overview.snapshot.bounds }
                            let fixedMap = CanvasMapGeometry(bounds: dragBounds ?? map.bounds, size: geometry.size)
                            controls.navigate(to: fixedMap.worldPoint(value.location))
                        }
                        .onEnded { _ in dragBounds = nil })
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Canvas minimap")
                    .accessibilityHint("Tap or drag to navigate. Actions move the visible area in each direction.")
                    .accessibilityAction(named: "Move left") { move(x: -1, y: 0) }
                    .accessibilityAction(named: "Move right") { move(x: 1, y: 0) }
                    .accessibilityAction(named: "Move up") { move(x: 0, y: -1) }
                    .accessibilityAction(named: "Move down") { move(x: 0, y: 1) }
                    .accessibilityIdentifier("canvasMinimap")
                }
                .frame(height: 108)
                .clipped()
                .padding(.horizontal, 8).padding(.bottom, 8)
            }
        }
        .frame(width: collapsed ? 44 : 180)
        .buttonStyle(.plain)
        .foregroundStyle(NotebookTheme.burgundy)
        .background(.white.opacity(0.97), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(NotebookTheme.burgundy.opacity(0.22), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }

    private func move(x: CGFloat, y: CGFloat) {
        controls.navigate(to: CGPoint(x: visibleRect.midX + visibleRect.width * x,
                                      y: visibleRect.midY + visibleRect.height * y))
    }
}

private struct LassoAssistanceOverlay: View {
    @ObservedObject var controls: CanvasControls
    @ObservedObject var viewport: CanvasViewport
    var ask: (CanvasSelection) -> Void

    var body: some View {
        GeometryReader { geometry in
            if let selection = controls.selection {
                let zoom = viewport.value.zoom
                let x = selection.bounds.minX * zoom - viewport.value.x
                let bottom = selection.bounds.maxY * zoom - viewport.value.y
                Path { path in
                    let points = selection.outline.map { CGPoint(x: $0.x * zoom - viewport.value.x, y: $0.y * zoom - viewport.value.y) }
                    if let first = points.first {
                        path.move(to: first)
                        for point in points.dropFirst() { path.addLine(to: point) }
                        path.closeSubpath()
                    }
                }
                .stroke(NotebookTheme.burgundy, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .allowsHitTesting(false)
                Button("Ask Scout", systemImage: "sparkles") { ask(selection) }
                    .font(.body.weight(.semibold)).buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                    .offset(x: max(12, min(x, geometry.size.width - 150)),
                            y: max(12, min(bottom + 8, geometry.size.height - 64)))
                    .accessibilityIdentifier("askAISelection")
            }
        }
    }
}

private enum DrawingTool: String, CaseIterable {
    case select = "Select", pen = "Pen", marker = "Highlighter", eraser = "Eraser", lasso = "Lasso"
    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .pen: "pencil"
        case .marker: "highlighter"
        case .eraser: "eraser"
        case .lasso: "lasso"
        }
    }
}

private struct SharedPage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct NoteEditor: View {
    @ObservedObject var session: NoteSession
    @ObservedObject var scout: ScoutSession
    @ObservedObject var store: NotebookStore
    var openNotebook: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var controls = CanvasControls()
    @StateObject private var assistance = AssistanceCoordinator()
    @State private var selectedTool: DrawingTool = .pen
    @State private var inkColor = NotebookTheme.ink
    @State private var width = 3.0
    @State private var editingText = false
    @State private var showingScout = false
    @State private var contextAction: ContextAction?
    @State private var sharedPage: SharedPage?
    @State private var selectedPhoto: PhotosPickerItem?
    @AppStorage("fingerDrawing") private var fingerDrawing = false
    @State private var showingConceptCards = false

    private var tool: PKTool {
        switch selectedTool {
        case .pen: PKInkingTool(.pen, color: UIColor(inkColor), width: width)
        case .marker: PKInkingTool(.marker, color: UIColor(inkColor).withAlphaComponent(0.35), width: width * 5)
        case .eraser: PKEraserTool(.vector)
        case .select, .lasso: PKLassoTool()
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 850 || dynamicTypeSize.isAccessibilitySize
            VStack(spacing: 0) {
                header(compact: compact)
                if let error = session.saveError {
                    HStack {
                        Text(error).font(.callout)
                        Button("Retry") { session.flush() }.buttonStyle(.bordered)
                    }.foregroundStyle(.red).padding().background(.red.opacity(0.08))
                }
                InkCanvas(session: session, controls: controls, tool: tool,
                          fingerDrawing: fingerDrawing || selectedTool == .select,
                          capturesLassoRegion: selectedTool == .lasso)
                .overlay(alignment: .topLeading) {
                    if session.note.template == .checkout && showingConceptCards {
                        CanvasAnnotations(session: session, viewport: controls.viewport) { contextAction = $0 }
                    }
                }
                .overlay {
                    if assistance.region?.id != controls.selection?.region.id || assistance.region == nil {
                        LassoAssistanceOverlay(controls: controls, viewport: controls.viewport) { selection in
                            assistance.ask(selection, using: scout)
                            showingScout = true
                        }
                    }
                }
                .overlay {
                    AssistanceCanvasOverlay(session: session, credentials: scout, coordinator: assistance, viewport: controls.viewport,
                                            controls: controls, selectionMode: selectedTool == .select,
                                            openInspector: { showingScout = true }, insert: insertSuggestion)
                }
                .overlay(alignment: .top) {
                    if selectedTool == .select {
                        Text("Circle ink, then drag it to move. Drag AI blocks directly.")
                            .font(.caption).padding(10)
                            .background(.regularMaterial, in: Capsule())
                            .padding(8).allowsHitTesting(false)
                    }
                }
                .clipped()
                .overlay(alignment: .bottomTrailing) {
                    CanvasMinimap(controls: controls, viewport: controls.viewport, overview: controls.overview)
                        .padding(12)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    drawingBar
                        .frame(maxWidth: 726)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                }
            }
            .background(Color(uiColor: NotebookTheme.paper))
        }
        .sheet(isPresented: $showingScout) {
            ScoutSheet(credentials: scout, coordinator: assistance, sourceSession: store.sourceSession, insert: insertSuggestion)
        }
        .onAppear { assistance.recallSearch = { query in try await store.recall(query) }; assistance.resolveSource = { region in CanvasSource.resolve(region, note: session.note, drawing: session.drawing) } }
        .onChange(of: session.note.drawingRevision) { _, _ in
            if assistance.region != nil { assistance.validate() }
            assistance.schedulePause(using: scout) { controls.captureChangedRegion() }
        }
        .onChange(of: session.note.text) { _, _ in if assistance.region != nil { assistance.validate() } }
        .onChange(of: session.note.attachment) { _, _ in if assistance.region != nil { assistance.validate() } }
        .onChange(of: scout.mode) { _, mode in
            if mode != .automatic { assistance.stopAutomatic() }
            else { assistance.schedulePause(using: scout) { controls.captureChangedRegion() } }
        }
        .onChange(of: scout.canProcess) { _, allowed in
            if allowed { assistance.schedulePause(using: scout) { controls.captureChangedRegion() } }
            else { assistance.cancel() }
        }

        .sheet(isPresented: $editingText) { textSheet }
        .sheet(item: $contextAction) { action in contextSheet(action) }
        .sheet(item: $sharedPage) { page in ShareSheet(items: [page.image]) }
        .onChange(of: selectedTool) { _, _ in controls.selection = nil }
        .onChange(of: selectedPhoto) { _, photo in
            Task {
                guard let photo else { return }
                do {
                    guard let data = try await photo.loadTransferable(type: Data.self), let image = UIImage(data: data),
                          let resized = image.preparingThumbnail(of: CGSize(width: 1200, height: 1200)),
                          let jpeg = resized.jpegData(compressionQuality: 0.85) else { return }
                    session.edit { $0.attachment = jpeg }
                } catch { controls.message = "The photo couldn’t be loaded. Try choosing it again." }
            }
        }
        .alert("Photo", isPresented: Binding(get: { controls.message != nil }, set: { if !$0 { controls.message = nil } })) {
            Button("OK") { controls.message = nil }
        } message: { Text(controls.message ?? "") }
        .onDisappear { assistance.cancel(); session.flush() }
    }

    private func insertSuggestion(_ suggestion: Suggestion, placement: BlockPlacement) {
        let viewport = controls.viewport
        let zoom = max(0.15, viewport.value.zoom)
        let source = suggestion.request.region.bounds.cgRect
        let ink = session.drawing.bounds
        var x = (viewport.value.x + 48) / zoom
        var y = (viewport.value.y + 100) / zoom
        switch placement {
        case .belowWriting:
            x = source.minX
            y = max(source.maxY, ink.isNull ? source.maxY : ink.maxY) + 32
        case .besideSource: x = source.maxX + 32; y = source.minY
        case .visibleCanvas: break
        }
        var target = CGRect(x: x, y: y, width: 380, height: 300)
        let obstacles = [source, ink].filter { !$0.isNull } + (session.note.blocks ?? []).map { $0.bounds.cgRect }
        for _ in 0...obstacles.count {
            guard let obstacle = obstacles.first(where: { $0.insetBy(dx: -16, dy: -16).intersects(target) }) else { break }
            target.origin.y = obstacle.maxY + 32
        }
        _ = session.insertBlock(suggestion, at: CanvasBounds(target), undoManager: controls.undoManager)
        controls.navigate(to: CGPoint(x: target.midX, y: target.midY))
        controls.refresh()
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Button(action: openNotebook) { dockIcon("square.grid.2x2") }
                .accessibilityLabel("Open notebook")
            TextField("Note title", text: Binding(get: { session.note.title }, set: { value in session.edit { $0.title = value } }))
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: compact ? .infinity : 280, minHeight: 44)
                .accessibilityLabel("Note title").accessibilityIdentifier("noteTitle").submitLabel(.done)
            if !compact {
                Divider().frame(height: 24)
                Text(session.note.createdAt, format: .dateTime.day().month(.abbreviated).year())
                    .font(.subheadline).foregroundStyle(NotebookTheme.muted)
                    .padding(.horizontal, 12)
                Spacer(minLength: 0)
            }
            Button(action: controls.undo) { dockIcon("arrow.uturn.backward") }
                .disabled(!controls.canUndo).accessibilityLabel("Undo ink").keyboardShortcut("z", modifiers: .command)
            if !compact {
                Button(action: controls.redo) { dockIcon("arrow.uturn.forward") }
                    .disabled(!controls.canRedo).accessibilityLabel("Redo ink").keyboardShortcut("z", modifiers: [.command, .shift])
            }
            optionsMenu
            Button(action: share) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 20))
                    if !compact { Text("Share") }
                }
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .padding(.horizontal, compact ? 0 : 10)
                    .foregroundStyle(.white)
                    .background(NotebookTheme.burgundy, in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("Share note")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(NotebookTheme.ink)
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var optionsMenu: some View {
        Menu {
            Button("Undo ink", systemImage: "arrow.uturn.backward", action: controls.undo).disabled(!controls.canUndo)
            Button("Redo ink", systemImage: "arrow.uturn.forward", action: controls.redo).disabled(!controls.canRedo)
            Divider()
            Picker("Paper", selection: Binding(get: { session.note.paper }, set: { value in session.edit { $0.paper = value } })) {
                ForEach(PaperStyle.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Draw with finger", isOn: $fingerDrawing)
            Picker("Stroke width", selection: $width) {
                Text("Fine").tag(1.5)
                Text("Medium").tag(3.0)
                Text("Bold").tag(6.0)
            }
            Button("Return to canvas start", systemImage: "house", action: controls.resetZoom)
            Button("Typed notes", systemImage: "textformat") { editingText = true }
            Button("Ask Scout", systemImage: "sparkles", action: openScout)
            Button("Recall dated meetings", systemImage: "clock") {
                openScout()
                assistance.transcript = NoteRecord.recallQuestion
                assistance.recall()
            }
            Toggle("Show fictional concept cards", isOn: $showingConceptCards)
            if session.note.attachment != nil {
                Button("Remove photo", systemImage: "photo.badge.minus") { session.edit { $0.attachment = nil } }
            }
            Text(session.saveMessage)
        } label: { Image(systemName: "ellipsis").font(.system(size: 20)).frame(width: 44, height: 44) }
        .accessibilityLabel("Page options")
    }

    private var inkChoices: [(name: String, color: Color)] {
        [("Black", NotebookTheme.ink), ("Burgundy", NotebookTheme.burgundy),
         ("Sage", NotebookTheme.sage), ("Gray", Color(red: 0.82, green: 0.82, blue: 0.82))]
    }

    private var inkName: String {
        inkChoices.first { $0.color == inkColor }?.name ?? "Custom color"
    }

    private var widthName: String {
        width == 1.5 ? "Fine" : width == 6 ? "Bold" : "Medium"
    }

    private var drawingBar: some View {
        ViewThatFits(in: .horizontal) {
            drawingControls
            ScrollView(.horizontal, showsIndicators: false) {
                drawingControls
            }
            .frame(height: 44)
            .accessibilityHint("Swipe horizontally for more drawing controls")
        }
        .buttonStyle(.borderless).tint(NotebookTheme.ink)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(uiColor: .systemBackground), in: Capsule())
        .overlay(Capsule().stroke(NotebookTheme.ink.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 4)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var drawingControls: some View {
        HStack(spacing: 8) {
            toolChoices
            dockDivider
            insertActions
            dockDivider
            colorChoices
            strokeWidthMenu
        }
    }

    private var toolChoices: some View {
        HStack(spacing: 8) {
            ForEach(DrawingTool.allCases, id: \.self) { item in toolButton(item) }
        }
    }

    private var insertActions: some View {
        HStack(spacing: 8) {
            Button(action: openScout) { dockIcon("sparkles") }.accessibilityLabel("Ask Scout")
            Button { editingText = true } label: { dockIcon("textformat") }.accessibilityLabel("Typed notes")
            Button { controls.addRectangle(color: UIColor(inkColor), width: width) } label: { dockIcon("square") }
                .accessibilityLabel("Insert rectangle")
            PhotosPicker(selection: $selectedPhoto, matching: .images) { dockIcon("photo") }.accessibilityLabel("Insert photo")
        }
    }

    private var colorChoices: some View {
        HStack(spacing: 8) {
            ForEach(inkChoices, id: \.name) { choice in
                let selected = inkColor == choice.color
                Button { inkColor = choice.color } label: {
                    Circle().fill(choice.color)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().strokeBorder(NotebookTheme.ink.opacity(0.2), lineWidth: 1))
                        .overlay {
                            if selected {
                                Image(systemName: "checkmark").font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(choice.name == "Gray" ? NotebookTheme.ink : .white)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .overlay(Circle().strokeBorder(selected ? NotebookTheme.ink : .clear, lineWidth: 1.5))
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("\(choice.name) ink")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            ColorPicker("Custom ink color", selection: $inkColor, supportsOpacity: false)
                .labelsHidden().frame(width: 44, height: 44)
                .overlay(Circle().strokeBorder(inkName == "Custom color" ? NotebookTheme.ink : .clear, lineWidth: 2).allowsHitTesting(false))
                .accessibilityLabel("Custom ink color")
                .accessibilityAddTraits(inkName == "Custom color" ? .isSelected : [])
        }
    }

    private var strokeWidthMenu: some View {
        Menu {
            Picker("Stroke width", selection: $width) {
                Text("Fine").tag(1.5)
                Text("Medium").tag(3.0)
                Text("Bold").tag(6.0)
            }
        } label: {
            VStack(spacing: 4) {
                Capsule().frame(width: 20, height: width + 1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }.frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("Stroke width").accessibilityValue(widthName)
    }

    private var dockDivider: some View { Divider().frame(height: 28) }
    private func dockIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 20)).frame(width: 44, height: 44).contentShape(Rectangle())
    }
    private func toolButton(_ item: DrawingTool) -> some View {
        let selected = selectedTool == item
        return Button { selectedTool = item } label: {
            Image(systemName: item.symbol).font(.system(size: 20))
            .frame(width: 44, height: 44)
            .foregroundStyle(selected ? NotebookTheme.burgundy : NotebookTheme.ink)
            .background(selected ? NotebookTheme.burgundy.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? NotebookTheme.burgundy : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .accessibilityLabel(item.rawValue).accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(item == .select ? "Circle handwriting or shapes, then drag to move. Drag AI blocks directly." : "")
    }

    private var textSheet: some View {
        NavigationStack {
            TextEditor(text: Binding(get: { session.note.text }, set: { value in session.edit { $0.text = value } }))
                .font(.body).padding(20).scrollContentBackground(.hidden)
                .background(Color(uiColor: NotebookTheme.paper))
                .accessibilityLabel("Typed notes").accessibilityIdentifier("typedNotes")
                .navigationTitle("Typed notes").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { editingText = false } } }
        }
    }

    private func contextSheet(_ action: ContextAction) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label(action.rawValue, systemImage: action.symbol).font(.title2.weight(.semibold))
                    Text("Fictional concept card · static design example").font(.caption).foregroundStyle(.secondary)
                    Text(action.detail).font(.title3).lineSpacing(7)
                    if action == .research {
                        Link("Read Stripe Docs ↗", destination: URL(string: "https://docs.stripe.com/payments/checkout")!)
                    }
                    Button("Add to typed notes", systemImage: "text.badge.plus") {
                        session.edit { $0.text += ($0.text.isEmpty ? "" : "\n\n") + action.detail }
                        contextAction = nil
                        editingText = true
                    }.buttonStyle(.bordered)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(28)
            }
            .background(Color(uiColor: NotebookTheme.paper))
            .navigationTitle(action == .original ? "Past meeting" : action.rawValue).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { contextAction = nil } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func openScout() {
        if assistance.region == nil {
            let region = CanvasSource.typedRegion(note: session.note)
            assistance.prepare(nil, region: region)
        }
        showingScout = true
    }

    private func share() {
        let annotations = session.note.template == .checkout && showingConceptCards
            ? ImageRenderer(content: CheckoutAnnotations(session: session) { _ in }).uiImage : nil
        guard let image = controls.pageImage(annotations: annotations) else { return }
        sharedPage = SharedPage(image: image)
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

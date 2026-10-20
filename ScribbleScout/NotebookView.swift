import PencilKit
import PhotosUI
import SwiftUI

struct NotebookView: View {
    @ObservedObject var store: NotebookStore
    @State private var search = ""
    @State private var showingNotebook = false

    private var filteredNotes: [NoteRecord] {
        store.notes.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.text.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if let session = store.current {
                NoteEditor(session: session) { showingNotebook.toggle() }.id(session.id)
            } else {
                ContentUnavailableView {
                    Label("A little room to think.", systemImage: "pencil.and.scribble")
                } description: {
                    Text("Capture an idea, sketch a plan, or start a fresh page.")
                } actions: {
                    Button("Create your first note") { store.create() }.buttonStyle(.borderedProminent)
                }
            }
            if showingNotebook {
                Color.black.opacity(0.15).ignoresSafeArea().onTapGesture { showingNotebook = false }
                sidebar
                    .frame(width: 310).frame(maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground))
                    .shadow(color: .black.opacity(0.12), radius: 20, x: 6)
                    .transition(.move(edge: .leading))
            }
        }
        .preferredColorScheme(.light)
        .tint(NotebookTheme.burgundy)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .alert("Notebook notice", isPresented: Binding(get: { store.issue != nil }, set: { if !$0 { store.issue = nil } })) {
            Button("OK") { store.issue = nil }
        } message: { Text(store.issue ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "pencil.tip.crop.circle").font(.largeTitle).foregroundStyle(NotebookTheme.burgundy)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Scribble Scout").font(.title3.weight(.semibold))
                    Text("Your notebook").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { showingNotebook = false } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("Close notebook")
            }.padding(.horizontal, 20).padding(.top, 30).padding(.bottom, 24)
            Button {
                store.create()
                showingNotebook = false
            } label: {
                Label("New note", systemImage: "square.and.pencil").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent).padding(.horizontal, 20).padding(.bottom, 20)
            .keyboardShortcut("n", modifiers: .command).accessibilityIdentifier("newNote")
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find a note", text: $search).accessibilityLabel("Find a note").autocorrectionDisabled()
            }
            .padding(12).background(.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20).padding(.bottom, 20)
            Text("YOUR NOTEBOOK").font(.caption.weight(.semibold)).tracking(1.4)
                .foregroundStyle(.secondary).padding(.horizontal, 22).padding(.bottom, 8)
            List(filteredNotes) { note in
                Button {
                    store.open(note.id)
                    showingNotebook = false
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "doc.text").foregroundStyle(NotebookTheme.burgundy).padding(.top, 3)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(note.title.isEmpty ? "Untitled note" : note.title).font(.headline).lineLimit(2)
                            Text(note.updatedAt, format: .dateTime.month(.abbreviated).day()).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if note.id == store.current?.id { Image(systemName: "checkmark").foregroundStyle(NotebookTheme.burgundy) }
                    }.foregroundStyle(NotebookTheme.ink).padding(.vertical, 8)
                }.accessibilityIdentifier("note-\(note.id)")
            }
            .listStyle(.plain)
            .overlay { if filteredNotes.isEmpty && !search.isEmpty { ContentUnavailableView.search(text: search) } }
            Divider().padding(.horizontal, 20)
            Label("Your notes stay on this iPad", systemImage: "internaldrive")
                .font(.caption).foregroundStyle(.secondary).padding(20)
        }
    }
}

private enum DrawingTool: String, CaseIterable {
    case pen = "Pen", marker = "Highlighter", eraser = "Eraser", lasso = "Lasso"
    var symbol: String {
        switch self {
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
    var openNotebook: () -> Void
    @StateObject private var controls = CanvasControls()
    @State private var selectedTool: DrawingTool = .pen
    @State private var inkColor = NotebookTheme.ink
    @State private var width = 3.0
    @State private var editingText = false
    @State private var contextAction: ContextAction?
    @State private var sharedPage: SharedPage?
    @State private var selectedPhoto: PhotosPickerItem?
    @AppStorage("fingerDrawing") private var fingerDrawing = false

    private var tool: PKTool {
        switch selectedTool {
        case .pen: PKInkingTool(.pen, color: UIColor(inkColor), width: width)
        case .marker: PKInkingTool(.marker, color: UIColor(inkColor).withAlphaComponent(0.35), width: width * 5)
        case .eraser: PKEraserTool(.vector)
        case .lasso: PKLassoTool()
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 1448
            let compact = geometry.size.width < 700
            VStack(spacing: 0) {
                header(compact: compact, scale: compact ? 0.9 : scale)
                if let error = session.saveError {
                    HStack {
                        Text(error).font(.callout)
                        Button("Retry") { session.flush() }.buttonStyle(.bordered)
                    }.foregroundStyle(.red).padding().background(.red.opacity(0.08))
                }
                InkCanvas(session: session, controls: controls, tool: tool, fingerDrawing: fingerDrawing)
                .overlay(alignment: .topLeading) {
                    if session.note.template == .checkout {
                        CheckoutAnnotations(session: session) { contextAction = $0 }
                            .scaleEffect(controls.zoom, anchor: .topLeading)
                            .offset(x: -controls.offset.x, y: -controls.offset.y)
                    }
                }
                .clipped()
                .overlay(alignment: .bottom) {
                    if compact {
                        ScrollView(.horizontal, showsIndicators: false) { drawingBar.padding(.horizontal, 16) }
                            .frame(height: 78).padding(.bottom, 20)
                    } else {
                        drawingBar
                            .scaleEffect(min(1, scale), anchor: .bottom)
                            .padding(.bottom, 27 * scale)
                    }
                }
            }
            .background(Color(uiColor: NotebookTheme.paper))
        }
        .ignoresSafeArea()
        .sheet(isPresented: $editingText) { textSheet }
        .sheet(item: $contextAction) { action in contextSheet(action) }
        .sheet(item: $sharedPage) { page in ShareSheet(items: [page.image]) }
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
        .onDisappear { session.flush() }
    }

    private func header(compact: Bool, scale: CGFloat) -> some View {
        HStack(spacing: 0) {
            Button(action: openNotebook) { Image(systemName: "line.3.horizontal").font(.system(size: 22 * scale)).frame(width: 60 * scale, height: 56 * scale) }
                .accessibilityLabel("Open notebook")
            headerDivider(scale)
            TextField("Note title", text: Binding(get: { session.note.title }, set: { value in session.edit { $0.title = value } }))
                .font(.system(size: 19 * scale, weight: .semibold))
                .frame(maxWidth: compact ? .infinity : 205 * scale)
                .padding(.horizontal, 22 * scale)
                .accessibilityLabel("Note title").accessibilityIdentifier("noteTitle").submitLabel(.done)
            if !compact {
                headerDivider(scale)
                Text(session.note.createdAt.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "en_AU"))))
                    .font(.system(size: 17 * scale)).padding(.horizontal, 22 * scale)
                Spacer(minLength: 0)
            }
            Button(action: controls.undo) { Image(systemName: "arrow.uturn.backward").frame(width: 50 * scale, height: 44) }
                .disabled(!controls.canUndo).accessibilityLabel("Undo ink").keyboardShortcut("z", modifiers: .command)
            if !compact {
                Button(action: controls.redo) { Image(systemName: "arrow.uturn.forward").frame(width: 50 * scale, height: 44) }
                    .disabled(!controls.canRedo).accessibilityLabel("Redo ink").keyboardShortcut("z", modifiers: [.command, .shift])
                optionsMenu.frame(width: 54 * scale)
            }
            Button(action: share) {
                HStack(spacing: 10) {
                    Image(systemName: "person").font(.system(size: 18 * scale))
                    if !compact { Text("Share").font(.system(size: 16 * scale, weight: .medium)) }
                }
                .foregroundStyle(.white).padding(.horizontal, 14 * scale).frame(height: max(38, 39 * scale))
                .background(NotebookTheme.burgundy.gradient, in: RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel("Share note").padding(.leading, 12 * scale).padding(.trailing, 19 * scale)
        }
        .foregroundStyle(NotebookTheme.ink)
        .frame(height: max(48, 60 * scale))
        .background(Color(red: 0.986, green: 0.980, blue: 0.974))
        .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.055)).frame(height: 1) }
    }

    private func headerDivider(_ scale: CGFloat) -> some View {
        Rectangle().fill(.black.opacity(0.14)).frame(width: 1, height: 22 * scale)
    }

    private var optionsMenu: some View {
        Menu {
            Picker("Paper", selection: Binding(get: { session.note.paper }, set: { value in session.edit { $0.paper = value } })) {
                ForEach(PaperStyle.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Draw with finger", isOn: $fingerDrawing)
            Picker("Stroke width", selection: $width) {
                Text("Fine").tag(1.5)
                Text("Medium").tag(3.0)
                Text("Bold").tag(6.0)
            }
            Button("Fit page width", systemImage: "arrow.down.right.and.arrow.up.left", action: controls.resetZoom)
            Button("Typed notes", systemImage: "textformat") { editingText = true }
            if session.note.attachment != nil {
                Button("Remove photo", systemImage: "photo.badge.minus") { session.edit { $0.attachment = nil } }
            }
            Text(session.saveMessage)
        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
        .accessibilityLabel("Page options")
    }

    private var drawingBar: some View {
        HStack(spacing: 8) {
            ForEach([DrawingTool.pen, .marker, .eraser], id: \.self) { item in toolButton(item) }
            dockDivider
            toolButton(.lasso)
            Button { editingText = true } label: { dockIcon("textformat") }.accessibilityLabel("Typed notes")
            Button { controls.addRectangle(color: UIColor(inkColor), width: width) } label: { dockIcon("square") }
                .accessibilityLabel("Insert rectangle")
            PhotosPicker(selection: $selectedPhoto, matching: .images) { dockIcon("photo") }.accessibilityLabel("Insert photo")
            optionsMenu
            dockDivider
            ForEach(Array([NotebookTheme.ink, .init(red: 0.51, green: 0.12, blue: 0.24), NotebookTheme.sage,
                           Color(red: 0.82, green: 0.82, blue: 0.82)].enumerated()), id: \.offset) { index, color in
                Button { inkColor = color } label: {
                    Circle().fill(color.gradient).frame(width: 25, height: 25)
                        .overlay(Circle().strokeBorder(.black.opacity(0.08), lineWidth: 1))
                        .frame(width: 36, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(["Black ink", "Burgundy ink", "Sage ink", "Gray ink"][index])
                .accessibilityAddTraits(inkColor == color ? .isSelected : [])
            }
            ColorPicker("Custom ink color", selection: $inkColor, supportsOpacity: false)
                .labelsHidden().frame(width: 35, height: 44)
                .opacity(0.02)
                .overlay { Image(systemName: "plus.circle").font(.system(size: 30, weight: .ultraLight)).foregroundStyle(.gray).allowsHitTesting(false) }
                .accessibilityLabel("Custom ink color")
        }
        .buttonStyle(.plain).foregroundStyle(NotebookTheme.ink)
        .padding(.horizontal, 14).frame(width: 726, height: 68)
        .background(.white.opacity(0.97), in: Capsule())
        .overlay(Capsule().stroke(.black.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
    }

    private var dockDivider: some View { Rectangle().fill(.black.opacity(0.09)).frame(width: 1, height: 30).padding(.horizontal, 7) }
    private func dockIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 23, weight: .regular)).frame(width: 44, height: 44).contentShape(Rectangle())
    }
    private func toolButton(_ item: DrawingTool) -> some View {
        Button { selectedTool = item } label: {
            dockIcon(item.symbol)
                .foregroundStyle(item == .marker ? Color(red: 0.55, green: 0.47, blue: 0.26) : NotebookTheme.ink)
                .background(selectedTool == item ? Color(red: 0.965, green: 0.949, blue: 0.950) : .clear, in: RoundedRectangle(cornerRadius: 9))
                .overlay(alignment: .bottom) {
                    if selectedTool == item { Capsule().fill(NotebookTheme.burgundy).frame(width: 39, height: 3).offset(y: 2) }
                }
        }
        .accessibilityLabel(item.rawValue).accessibilityAddTraits(selectedTool == item ? .isSelected : [])
    }

    private var textSheet: some View {
        NavigationStack {
            TextEditor(text: Binding(get: { session.note.text }, set: { value in session.edit { $0.text = value } }))
                .font(.system(size: 22)).padding(20).scrollContentBackground(.hidden)
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

    private func share() {
        guard let base = controls.pageImage() else { return }
        let renderer = UIGraphicsImageRenderer(size: base.size)
        let image = renderer.image { _ in
            base.draw(at: .zero)
            if session.note.template == .checkout {
                let annotations = ImageRenderer(content: CheckoutAnnotations(session: session) { _ in })
                annotations.uiImage?.draw(at: .zero)
            }
        }
        sharedPage = SharedPage(image: image)
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

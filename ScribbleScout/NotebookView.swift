import PencilKit
import SwiftUI

struct NotebookView: View {
    @ObservedObject var store: NotebookStore
    @State private var search = ""
    @State private var visibility: NavigationSplitViewVisibility = .all

    private var filteredNotes: [NoteRecord] {
        store.notes.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.text.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "pencil.tip.crop.circle")
                        .font(.largeTitle)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Scribble Scout").font(.title3.weight(.semibold))
                        Text("AI Note Taking").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 22).padding(.vertical, 24)

                Button(action: store.create) {
                    Label("New note", systemImage: "square.and.pencil")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 20).padding(.bottom, 20)
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityIdentifier("newNote")

                HStack {
                    Text("YOUR NOTEBOOK").font(.caption.weight(.semibold)).tracking(1.4)
                    Spacer()
                    Text("\(store.notes.count)").font(.caption.monospacedDigit())
                }
                .foregroundStyle(.secondary).padding(.horizontal, 22).padding(.bottom, 8)

                List(selection: Binding(get: { store.current?.id }, set: { if let id = $0 { store.open(id) } })) {
                    ForEach(filteredNotes) { note in
                        NavigationLink(value: note.id) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "doc.text").foregroundStyle(Color.accentColor).padding(.top, 3)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(note.title.isEmpty ? "Untitled note" : note.title)
                                        .font(.headline).lineLimit(2)
                                    Text(note.updatedAt, format: .dateTime.month(.abbreviated).day())
                                        .font(.caption).foregroundStyle(.secondary)
                                    if !note.text.isEmpty {
                                        Text(note.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .accessibilityIdentifier("note-\(note.id)")
                    }
                }
                .listStyle(.sidebar)
                .overlay {
                    if filteredNotes.isEmpty && !search.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                }
                Divider().padding(.horizontal, 20)
                Label("Your notes stay on this iPad", systemImage: "internaldrive")
                    .font(.caption).foregroundStyle(.secondary).padding(20)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .navigationTitle("Notebook")
            .toolbar(.hidden, for: .navigationBar)
            .searchable(text: $search, prompt: "Find a note")
            .navigationSplitViewColumnWidth(min: 270, ideal: 310, max: 380)
        } detail: {
            if let session = store.current {
                NoteEditor(session: session).id(session.id)
            } else {
                ContentUnavailableView {
                    Label("A little room to think.", systemImage: "pencil.and.scribble")
                } description: {
                    Text("Capture an idea, sketch a plan, or start a fresh page.\nYour notebook is saved locally, ready whenever you are.")
                } actions: {
                    Button("Create your first note", action: store.create).buttonStyle(.borderedProminent)
                }
                .navigationTitle("Scribble Scout")
            }
        }
        .alert("Notebook notice", isPresented: Binding(get: { store.issue != nil }, set: { if !$0 { store.issue = nil } })) {
            Button("OK") { store.issue = nil }
        } message: { Text(store.issue ?? "") }
    }
}

private enum EditorMode: String, CaseIterable { case ink = "Handwriting", text = "Text" }
private enum DrawingTool: String, CaseIterable {
    case pen = "Pen", marker = "Highlighter", eraser = "Eraser", lasso = "Lasso"
    var symbol: String {
        switch self {
        case .pen: "pencil.tip"
        case .marker: "highlighter"
        case .eraser: "eraser"
        case .lasso: "lasso"
        }
    }
}

private struct NoteEditor: View {
    @ObservedObject var session: NoteSession
    @StateObject private var controls = CanvasControls()
    @State private var mode: EditorMode = .ink
    @State private var selectedTool: DrawingTool = .pen
    @State private var inkColor: Color = Color(uiColor: .label)
    @State private var width = 3.0
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
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    TextField("Note title", text: Binding(get: { session.note.title }, set: { value in session.edit { $0.title = value } }))
                        .font(.system(.largeTitle, design: .serif).weight(.medium))
                        .accessibilityLabel("Note title")
                        .accessibilityIdentifier("noteTitle")
                        .submitLabel(.done)
                    Menu {
                        Picker("Paper", selection: Binding(get: { session.note.paper }, set: { value in session.edit { $0.paper = value } })) {
                            ForEach(PaperStyle.allCases) { Text($0.title).tag($0) }
                        }
                        Toggle("Draw with finger", isOn: $fingerDrawing)
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title2).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Page options")
                }
                HStack(spacing: 12) {
                    Text(session.note.createdAt, format: .dateTime.weekday(.wide).month(.wide).day())
                    Spacer()
                    Label(session.saveMessage, systemImage: session.saveError == nil ? "checkmark.circle" : "exclamationmark.triangle")
                        .foregroundStyle(session.saveError == nil ? Color.secondary : Color.red)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28).padding(.top, 18).padding(.bottom, 20)

            HStack {
                Picker("Note mode", selection: $mode) {
                    ForEach(EditorMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(maxWidth: 260)
                Spacer()
                if mode == .ink {
                    Button(action: controls.undo) { Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44) }
                        .disabled(!controls.canUndo).accessibilityLabel("Undo ink")
                        .keyboardShortcut("z", modifiers: .command)
                    Button(action: controls.redo) { Image(systemName: "arrow.uturn.forward").frame(width: 44, height: 44) }
                        .disabled(!controls.canRedo).accessibilityLabel("Redo ink")
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 12)

            if let error = session.saveError {
                HStack {
                    Text(error).font(.callout)
                    Button("Retry") { session.flush() }.buttonStyle(.bordered)
                }
                .foregroundStyle(.red).padding().background(Color.red.opacity(0.08))
            }

            ZStack(alignment: .bottom) {
                // Keep the same canvas alive while typing to preserve its undo history and viewport.
                InkCanvas(session: session, controls: controls, tool: tool, fingerDrawing: fingerDrawing)
                    .opacity(mode == .ink ? 1 : 0)
                    .allowsHitTesting(mode == .ink)
                    .accessibilityHidden(mode != .ink)
                if mode == .text {
                    TextEditor(text: Binding(get: { session.note.text }, set: { value in session.edit { $0.text = value } }))
                        .font(.system(.body, design: .serif))
                        .padding(24)
                        .accessibilityLabel("Typed notes")
                        .accessibilityIdentifier("typedNotes")
                }
            }
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.07)))
            .padding(.horizontal, 20)

            if mode == .ink { drawingBar }
            HStack {
                Text(mode == .ink ? (fingerDrawing ? "Finger or Pencil to write · two fingers to scroll" : "Apple Pencil to write · finger to scroll") : "A space for the words behind your sketches")
                Spacer()
                if mode == .ink {
                    Button("\(Int(controls.zoom * 100))% · Fit page", action: controls.resetZoom)
                        .accessibilityLabel("Fit page width")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 28).padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Notebook")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { session.flush() }
    }

    private var drawingBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DrawingTool.allCases, id: \.self) { item in
                    Button { selectedTool = item } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                            .font(.callout.weight(.medium)).padding(.horizontal, 12).frame(minHeight: 44)
                            .background(selectedTool == item ? Color.accentColor.opacity(0.12) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 10))
                    }
                    .accessibilityAddTraits(selectedTool == item ? .isSelected : [])
                }
                Divider().frame(height: 24).padding(.horizontal, 4)
                ColorPicker("Ink color", selection: $inkColor, supportsOpacity: false)
                    .labelsHidden().frame(width: 44, height: 44).accessibilityLabel("Ink color")
                Menu {
                    Picker("Stroke width", selection: $width) {
                        Text("Fine").tag(1.5)
                        Text("Medium").tag(3.0)
                        Text("Bold").tag(6.0)
                    }
                } label: {
                    Image(systemName: "lineweight").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Stroke width")
            }
            .padding(8)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 20).padding(.top, 12)
    }
}

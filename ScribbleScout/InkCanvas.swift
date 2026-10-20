import PencilKit
import SwiftUI

@MainActor
final class CanvasControls: ObservableObject {
    weak var canvas: PKCanvasView?
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var zoom = 1.0

    func refresh() {
        canUndo = canvas?.undoManager?.canUndo ?? false
        canRedo = canvas?.undoManager?.canRedo ?? false
        zoom = Double(canvas?.zoomScale ?? 1)
    }
    func undo() {
        canvas?.undoManager?.undo()
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }
    func redo() {
        canvas?.undoManager?.redo()
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }
    func resetZoom() {
        guard let canvas else { return }
        canvas.setZoomScale(canvas.minimumZoomScale, animated: true)
        canvas.setContentOffset(.zero, animated: true)
    }
}

/// A sibling paper layer uses the public scroll offset and zoom scale, without inspecting PencilKit's view hierarchy.
private final class PaperView: UIView {
    var style: PaperStyle = .dotted { didSet { setNeedsDisplay() } }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        UIColor.secondaryLabel.withAlphaComponent(0.2).setStroke()
        UIColor.secondaryLabel.withAlphaComponent(0.25).setFill()
        switch style {
        case .blank: break
        case .dotted:
            for y in stride(from: 32.0, to: bounds.height, by: 28) {
                for x in stride(from: 32.0, to: bounds.width, by: 28) {
                    context.fillEllipse(in: CGRect(x: x, y: y, width: 1.5, height: 1.5))
                }
            }
        case .ruled:
            context.setLineWidth(0.5)
            for y in stride(from: 60.0, to: bounds.height, by: 36) {
                context.move(to: CGPoint(x: 32, y: y))
                context.addLine(to: CGPoint(x: bounds.width - 32, y: y))
            }
            context.strokePath()
        }
    }
}

private final class NotebookCanvasView: PKCanvasView {
    let paper = PaperView(frame: CGRect(origin: .zero, size: NotebookPage.size))
    var readyForViewport = false
    var initialViewport = PageViewport()
    var viewportDidInitialize: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        minimumZoomScale = min(1, max(0.25, bounds.width / NotebookPage.size.width))
        guard !readyForViewport else { alignPaper(); return }
        paper.isUserInteractionEnabled = false
        paper.backgroundColor = .systemBackground
        maximumZoomScale = 3
        zoomScale = max(minimumZoomScale, min(maximumZoomScale, initialViewport.zoom))
        let maxX = max(0, contentSize.width - bounds.width)
        let maxY = max(0, contentSize.height - bounds.height)
        contentOffset = CGPoint(x: min(maxX, max(0, initialViewport.x)), y: min(maxY, max(0, initialViewport.y)))
        readyForViewport = true
        alignPaper()
        viewportDidInitialize?()
    }

    func alignPaper() {
        paper.transform = CGAffineTransform(scaleX: zoomScale, y: zoomScale)
        paper.frame.origin = CGPoint(x: -contentOffset.x, y: -contentOffset.y)
    }
}

private final class CanvasContainer: UIView {
    let canvas = NotebookCanvasView()
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = .systemBackground
        addSubview(canvas.paper)
        addSubview(canvas)
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds
        canvas.alignPaper()
    }
}

struct InkCanvas: UIViewRepresentable {
    @ObservedObject var session: NoteSession
    @ObservedObject var controls: CanvasControls
    var tool: PKTool
    var fingerDrawing: Bool

    func makeUIView(context: Context) -> UIView {
        let container = CanvasContainer()
        let canvas = container.canvas
        canvas.isOpaque = false
        canvas.backgroundColor = .clear
        canvas.contentSize = NotebookPage.size
        canvas.alwaysBounceVertical = true
        canvas.drawing = session.drawing
        canvas.initialViewport = session.note.viewport
        canvas.paper.style = session.note.paper
        canvas.tool = tool
        canvas.drawingPolicy = fingerDrawing ? .anyInput : .pencilOnly
        canvas.accessibilityLabel = "Handwriting canvas"
        canvas.accessibilityHint = "Write with Apple Pencil. Pinch to zoom. Use two fingers to scroll when finger drawing is on."
        canvas.delegate = context.coordinator
        controls.canvas = canvas
        canvas.viewportDidInitialize = { [weak controls] in
            DispatchQueue.main.async { controls?.refresh() }
        }
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let canvas = (uiView as? CanvasContainer)?.canvas else { return }
        // Keep the active tool stable while PencilKit completes drawing and undo operations.
        if let ink = tool as? PKInkingTool, (canvas.tool as? PKInkingTool) != ink { canvas.tool = ink }
        if let eraser = tool as? PKEraserTool, (canvas.tool as? PKEraserTool) != eraser { canvas.tool = eraser }
        if tool is PKLassoTool, !(canvas.tool is PKLassoTool) { canvas.tool = tool }
        let policy: PKCanvasViewDrawingPolicy = fingerDrawing ? .anyInput : .pencilOnly
        if canvas.drawingPolicy != policy { canvas.drawingPolicy = policy }
        if canvas.paper.style != session.note.paper { canvas.paper.style = session.note.paper }
    }

    func makeCoordinator() -> Coordinator { Coordinator(session: session, controls: controls) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let session: NoteSession
        let controls: CanvasControls
        init(session: NoteSession, controls: CanvasControls) { self.session = session; self.controls = controls }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            session.setDrawing(canvasView.drawing)
            // Undo registration finishes after PencilKit's delegate callback.
            DispatchQueue.main.async { [weak controls] in controls?.refresh() }
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? NotebookCanvasView)?.alignPaper()
            saveViewport(scrollView)
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            (scrollView as? NotebookCanvasView)?.alignPaper()
            saveViewport(scrollView)
        }

        private func saveViewport(_ scrollView: UIScrollView) {
            guard (scrollView as? NotebookCanvasView)?.readyForViewport == true else { return }
            let viewport = PageViewport(zoom: scrollView.zoomScale,
                                        x: scrollView.contentOffset.x, y: scrollView.contentOffset.y)
            // UIScrollView can call its delegate during SwiftUI layout.
            DispatchQueue.main.async { [weak self] in
                self?.session.setViewport(viewport)
                self?.controls.refresh()
            }
        }
    }
}

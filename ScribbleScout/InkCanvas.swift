import PencilKit
import SwiftUI

@MainActor
final class CanvasControls: ObservableObject {
    weak var canvas: PKCanvasView?
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var zoom = 1.0
    @Published var offset = CGPoint.zero
    @Published var message: String?

    func refresh() {
        canUndo = canvas?.undoManager?.canUndo ?? false
        canRedo = canvas?.undoManager?.canRedo ?? false
        zoom = Double(canvas?.zoomScale ?? 1)
        offset = canvas?.contentOffset ?? .zero
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

    func addRectangle(color: UIColor, width: CGFloat) {
        guard let canvas else { return }
        let origin = CGPoint(x: (canvas.contentOffset.x + 80) / canvas.zoomScale,
                             y: (canvas.contentOffset.y + 80) / canvas.zoomScale)
        let points = [origin, CGPoint(x: origin.x + 180, y: origin.y),
                      CGPoint(x: origin.x + 180, y: origin.y + 110),
                      CGPoint(x: origin.x, y: origin.y + 110), origin]
        let path = PKStrokePath(controlPoints: points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                          size: CGSize(width: width, height: width), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date())
        replaceDrawing(PKDrawing(strokes: canvas.drawing.strokes + [PKStroke(ink: PKInk(.pen, color: color), path: path)]))
    }

    private func replaceDrawing(_ drawing: PKDrawing) {
        guard let canvas else { return }
        let previous = canvas.drawing
        canvas.undoManager?.registerUndo(withTarget: self) { $0.replaceDrawing(previous) }
        canvas.drawing = drawing
        refresh()
    }

    func pageImage() -> UIImage? {
        guard let canvas = canvas as? NotebookCanvasView else { return nil }
        return UIGraphicsImageRenderer(size: canvas.paper.bounds.size).image { context in
            NotebookTheme.paper.setFill()
            context.fill(canvas.paper.bounds)
            canvas.paper.draw(canvas.paper.bounds)
            canvas.drawing.image(from: canvas.paper.bounds, scale: 2).draw(in: canvas.paper.bounds)
        }
    }
}

/// A sibling paper layer uses the public scroll offset and zoom scale, without inspecting PencilKit's view hierarchy.
private final class PaperView: UIView {
    var note = NoteRecord() { didSet { if note != oldValue { setNeedsDisplay() } } }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        UIColor(NotebookTheme.muted).withAlphaComponent(0.22).setStroke()
        UIColor(NotebookTheme.muted).withAlphaComponent(0.28).setFill()
        switch note.paper {
        case .blank: break
        case .dotted:
            for y in stride(from: 15.0, to: bounds.height, by: 25.5) {
                for x in stride(from: 15.0, to: bounds.width, by: 25.5) {
                    context.fillEllipse(in: CGRect(x: x, y: y, width: 1.35, height: 1.35))
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
        if note.template == .checkout { CheckoutPaper.draw(in: context) }
        if let data = note.attachment, let image = UIImage(data: data) {
            let width: CGFloat = 300
            image.draw(in: CGRect(x: 60, y: 60,
                                  width: width, height: width * image.size.height / image.size.width))
        }
        if !note.text.isEmpty && note.template == nil {
            (note.text as NSString).draw(in: CGRect(x: 60, y: note.attachment == nil ? 60 : 400,
                                                   width: bounds.width - 120, height: bounds.height - 140),
                                       withAttributes: [.font: UIFont(name: "Caveat-Regular", size: 32) ?? .systemFont(ofSize: 28),
                                                        .foregroundColor: UIColor(NotebookTheme.ink)])
        }
    }
}

private final class NotebookCanvasView: PKCanvasView {
    let paper = PaperView(frame: CGRect(origin: .zero, size: NotebookPage.size))
    var readyForViewport = false
    var initialViewport = PageViewport()
    var viewportDidInitialize: (() -> Void)?
    var pageSize = NotebookPage.size

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        let wasFit = abs(zoomScale - minimumZoomScale) < 0.01
        let previousMinimum = minimumZoomScale
        minimumZoomScale = min(1, max(0.25, bounds.width / pageSize.width))
        guard !readyForViewport else {
            if wasFit && abs(previousMinimum - minimumZoomScale) > 0.001 {
                zoomScale = minimumZoomScale
                contentOffset = .zero
            }
            alignPaper()
            return
        }
        paper.isUserInteractionEnabled = false
        paper.backgroundColor = NotebookTheme.paper
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
        backgroundColor = NotebookTheme.paper
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
        canvas.pageSize = NotebookPage.size(for: session.note)
        canvas.contentSize = canvas.pageSize
        canvas.paper.frame = CGRect(origin: .zero, size: canvas.pageSize)
        canvas.alwaysBounceVertical = true
        canvas.drawing = session.drawing
        canvas.initialViewport = session.note.viewport
        canvas.paper.note = session.note
        canvas.tool = tool
        canvas.drawingPolicy = fingerDrawing ? .anyInput : .pencilOnly
        canvas.accessibilityLabel = "Handwriting canvas"
        canvas.accessibilityValue = session.note.template == .checkout ? CheckoutPaper.transcript : session.note.text
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
        canvas.paper.note = session.note
        canvas.accessibilityValue = session.note.template == .checkout ? CheckoutPaper.transcript : session.note.text
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

import CryptoKit
import PencilKit
import SwiftUI

extension CanvasBounds {
    init(_ rect: CGRect) { self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height) }
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// App-owned source identity. Stroke order and translation are deliberately excluded.
/// Ambiguous duplicate strokes fail closed rather than attaching evidence to different ink.
enum CanvasSource {
    private struct Stroke: Codable {
        var hash: String
        var x: Double
        var y: Double
    }
    private struct Snapshot: Codable {
        var strokes: [Stroke]
        var paper: String
    }
    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private static func identity(_ stroke: PKStroke) -> Stroke {
        // Normalize only translation; rotation, resizing, masking and erased points invalidate the source.
        let origin = stroke.renderBounds.origin
        var values: [Double] = [Double(stroke.randomSeed)]
        for point in stroke.path {
            let location = point.location.applying(stroke.transform)
            values += [location.x - origin.x, location.y - origin.y, point.timeOffset,
                       point.size.width, point.size.height, point.opacity, point.force, point.azimuth, point.altitude]
        }
        // Preserve rotation/scaling and erasure information while allowing a pure translation.
        values += [stroke.transform.a, stroke.transform.b, stroke.transform.c, stroke.transform.d]
        if let mask = stroke.mask {
            mask.cgPath.applyWithBlock { pointer in
                let element = pointer.pointee
                values.append(Double(element.type.rawValue))
                let count: Int
                switch element.type {
                case .moveToPoint, .addLineToPoint: count = 1
                case .addQuadCurveToPoint: count = 2
                case .addCurveToPoint: count = 3
                case .closeSubpath: count = 0
                @unknown default: count = 0
                }
                for index in 0..<count {
                    values += [element.points[index].x, element.points[index].y]
                }
            }
        }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        stroke.ink.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        values += [red, green, blue, alpha]
        let rounded = values.map { ($0 * 1_000_000).rounded() / 1_000_000 }
        var data = (try? JSONEncoder().encode(rounded)) ?? Data()
        data.append(Data(stroke.ink.inkType.rawValue.utf8))
        return Stroke(hash: digest(data), x: origin.x, y: origin.y)
    }
    private static func paper(_ note: NoteRecord, in rect: CGRect) -> String {
        var data = Data()
        let page = CGRect(origin: .zero, size: NotebookPage.size(for: note))
        if note.template != nil && page.intersects(rect) { data.append(Data("checkout-v1".utf8)) }
        let attachmentRect = CGRect(x: 60, y: 60, width: 300, height: note.attachment.flatMap(UIImage.init(data:)).map { 300 * $0.size.height / $0.size.width } ?? 0)
        if rect.intersects(attachmentRect), let attachment = note.attachment { data.append(attachment) }
        let textRect = CGRect(x: 60, y: note.attachment == nil ? 60 : 400, width: page.width - 120, height: page.height - 140)
        if note.template == nil && rect.intersects(textRect) { data.append(Data(note.text.utf8)) }
        return digest(data)
    }
    static func region(note: NoteRecord, drawing: PKDrawing, bounds: CGRect) -> NoteRegion {
        let snapshot = Snapshot(strokes: drawing.strokes.filter { $0.renderBounds.intersects(bounds) }.map(identity),
                                paper: paper(note, in: bounds))
        let encoded = (try? JSONEncoder().encode(snapshot)) ?? Data()
        return NoteRegion(canvasID: note.id, revision: note.drawingRevision, bounds: CanvasBounds(bounds),
                          sourceHash: encoded.base64EncodedString())
    }
    static func typedRegion(note: NoteRecord) -> NoteRegion {
        NoteRegion(canvasID: note.id, revision: note.drawingRevision,
                   bounds: CanvasBounds(x: 60, y: note.attachment == nil ? 60 : 400, width: 880, height: 240),
                   recognisedText: note.text, sourceHash: "typed:" + digest(Data(note.text.utf8)))
    }
    static func resolve(_ region: NoteRegion, note: NoteRecord, drawing: PKDrawing) -> NoteRegion? {
        if region.sourceHash.hasPrefix("typed:") {
            return region.canvasID == note.id && region.sourceHash == typedRegion(note: note).sourceHash ? region : nil
        }
        guard note.id == region.canvasID, let data = Data(base64Encoded: region.sourceHash),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
        let current = drawing.strokes.map(identity)
        var translation: CGPoint?
        for source in snapshot.strokes {
            let candidates = current.filter { $0.hash == source.hash }
            // Prefer the original location when identical marks occur elsewhere.
            let exact = candidates.filter { abs($0.x - source.x) < 0.01 && abs($0.y - source.y) < 0.01 }
            guard let match = exact.count == 1 ? exact.first : (candidates.count == 1 ? candidates.first : nil) else { return nil }
            let delta = CGPoint(x: match.x - source.x, y: match.y - source.y)
            if let translation, hypot(delta.x - translation.x, delta.y - translation.y) > 0.1 { return nil }
            translation = delta
        }
        let delta = translation ?? .zero
        let bounds = region.bounds.cgRect.offsetBy(dx: delta.x, dy: delta.y)
        // Paper cannot move with ink; only allow translation when no printed content is selected.
        guard snapshot.paper == paper(note, in: bounds),
              delta == .zero || snapshot.paper == digest(Data()) else { return nil }
        let hashes = drawing.strokes.filter { $0.renderBounds.intersects(bounds) }.map { identity($0).hash }.sorted()
        guard hashes == snapshot.strokes.map(\.hash).sorted() else { return nil }
        var resolved = region
        resolved.bounds = CanvasBounds(bounds)
        resolved.revision = note.drawingRevision
        return resolved
    }
}

struct CanvasMapGeometry {
    let bounds: CGRect
    let size: CGSize
    var scale: CGFloat { min(max(1, size.width - 16) / max(1, bounds.width), max(1, size.height - 16) / max(1, bounds.height)) }
    var origin: CGPoint {
        CGPoint(x: (size.width - bounds.width * scale) / 2 - bounds.minX * scale,
                y: (size.height - bounds.height * scale) / 2 - bounds.minY * scale)
    }
    func map(_ rect: CGRect) -> CGRect {
        CGRect(x: origin.x + rect.minX * scale, y: origin.y + rect.minY * scale,
               width: rect.width * scale, height: rect.height * scale)
    }
    func worldPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
    }
}

@MainActor
final class CanvasViewport: ObservableObject {
    @Published var value = PageViewport(zoom: 1)
    @Published var size = CGSize.zero
}

@MainActor
final class CanvasOverview: ObservableObject {
    struct Snapshot {
        var bounds = CGRect(x: 0, y: 0, width: 1000, height: 1400)
        var imageBounds = CGRect.zero
        var image: UIImage?
    }
    @Published var snapshot = Snapshot()
}

struct CanvasSelection: Identifiable {
    let id = UUID()
    let image: UIImage
    let png: Data
    let contextImage: UIImage
    let contextPNG: Data
    let contextBounds: CGRect
    let bounds: CGRect
    let outline: [CGPoint]
    let region: NoteRegion
}

@MainActor
final class CanvasControls: ObservableObject {
    weak var canvas: PKCanvasView?
    var undoManager: UndoManager? { canvas?.undoManager }
    private var recentChangedBounds: CGRect?
    @Published var canUndo = false
    @Published var canRedo = false
    let viewport = CanvasViewport()
    let overview = CanvasOverview()
    @Published var message: String?
    @Published var selection: CanvasSelection?

    func captureSelection(outline: [CGPoint]) {
        selection = nil
        guard let canvas = canvas as? NotebookCanvasView, outline.count >= 3 else { return }
        let path = UIBezierPath()
        path.move(to: outline[0])
        for point in outline.dropFirst() { path.addLine(to: point) }
        path.close()
        let rect = path.bounds
        var doubledArea: CGFloat = 0
        for index in outline.indices {
            let point = outline[index]
            let next = outline[(index + 1) % outline.count]
            doubledArea += point.x * next.y - next.x * point.y
        }
        guard abs(doubledArea) >= 288 else { return }
        guard rect.width.isFinite, rect.height.isFinite, rect.minX.isFinite, rect.minY.isFinite,
              rect.width >= 12, rect.height >= 12 else { return }
        func render(_ region: CGRect, mask: Bool) -> UIImage {
            let scale = min(2, 1600 / max(region.width, region.height))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let size = CGSize(width: region.width * scale, height: region.height * scale)
            return UIGraphicsImageRenderer(size: size, format: format).image { output in
                UIColor.white.setFill()
                output.fill(CGRect(origin: .zero, size: size))
                output.cgContext.scaleBy(x: scale, y: scale)
                output.cgContext.translateBy(x: -region.minX, y: -region.minY)
                if mask { path.addClip() }
                NotebookTheme.paper.setFill()
                output.fill(region)
                canvas.paper.draw(canvas.paper.bounds)
                canvas.drawing.image(from: region, scale: scale).draw(in: region)
                if !mask {
                    UIColor(NotebookTheme.burgundy).setStroke()
                    path.lineWidth = 3 / scale
                    path.stroke()
                }
            }
        }
        let image = render(rect, mask: true)
        // Nearby context is bounded to 300 page points around the selection, with the focus outlined.
        let contextBounds = rect.insetBy(dx: -300, dy: -300)
        let contextImage = render(contextBounds, mask: false)
        guard let png = image.pngData(), let contextPNG = contextImage.pngData() else { return }
        selection = CanvasSelection(image: image, png: png, contextImage: contextImage, contextPNG: contextPNG,
                                    contextBounds: contextBounds, bounds: rect, outline: outline,
                                    region: CanvasSource.region(note: canvas.paper.note, drawing: canvas.drawing, bounds: rect))
    }

    func resolveSource(_ region: NoteRegion) -> NoteRegion? {
        guard let canvas = canvas as? NotebookCanvasView else { return nil }
        return CanvasSource.resolve(region, note: canvas.paper.note, drawing: canvas.drawing)
    }
    func isCurrent(_ region: NoteRegion) -> Bool { resolveSource(region) != nil }
    func typedRegion() -> NoteRegion? {
        guard let canvas = canvas as? NotebookCanvasView else { return nil }
        return CanvasSource.typedRegion(note: canvas.paper.note)
    }

    /// Snapshot only the bounded recent changed area, after the caller's pause debounce.
    func captureChangedRegion() -> CanvasSelection? {
        guard let rect = recentChangedBounds, !rect.isNull else { return nil }
        recentChangedBounds = nil
        let bounded = CGRect(x: rect.midX - min(rect.width, 1000) / 2,
                             y: rect.midY - min(rect.height, 1000) / 2,
                             width: min(rect.width, 1000), height: min(rect.height, 1000)).insetBy(dx: -16, dy: -16)
        captureSelection(outline: [CGPoint(x: bounded.minX, y: bounded.minY), CGPoint(x: bounded.maxX, y: bounded.minY),
                                   CGPoint(x: bounded.maxX, y: bounded.maxY), CGPoint(x: bounded.minX, y: bounded.maxY)])
        return selection
    }
    func captureRecentChange() -> CanvasSelection? { captureChangedRegion() }

    fileprivate func recordChanges(from previous: PKDrawing, to current: PKDrawing) {
        // No rendering here. Union changed stroke bounds, then crop once after the writing pause.
        let old = previous.strokes
        let new = current.strokes
        let oldData = Set(old.map { PKDrawing(strokes: [$0]).dataRepresentation() })
        let newData = Set(new.map { PKDrawing(strokes: [$0]).dataRepresentation() })
        let changed = new.filter { !oldData.contains(PKDrawing(strokes: [$0]).dataRepresentation()) } +
            old.filter { !newData.contains(PKDrawing(strokes: [$0]).dataRepresentation()) }
        let rect = changed.reduce(CGRect.null) { $0.union($1.renderBounds) }
        if !rect.isNull { recentChangedBounds = (recentChangedBounds ?? .null).union(rect) }
    }

    func refresh() {
        let undo = canvas?.undoManager?.canUndo ?? false
        let redo = canvas?.undoManager?.canRedo ?? false
        if canUndo != undo { canUndo = undo }
        if canRedo != redo { canRedo = redo }
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
        guard let canvas = canvas as? NotebookCanvasView else { return }
        let animated = !UIAccessibility.isReduceMotionEnabled
        canvas.setZoomScale(canvas.fitZoomScale, animated: animated)
        canvas.setContentOffset(.zero, animated: animated)
    }

    func navigate(to point: CGPoint) {
        guard let canvas = canvas as? NotebookCanvasView else { return }
        let origin = CGPoint(x: point.x - canvas.bounds.width / canvas.zoomScale / 2,
                             y: point.y - canvas.bounds.height / canvas.zoomScale / 2)
        canvas.expand(toInclude: CGRect(origin: origin, size: canvas.visibleRect.size))
        canvas.setContentOffset(CGPoint(x: origin.x * canvas.zoomScale, y: origin.y * canvas.zoomScale), animated: false)
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

    func pageImage(annotations: UIImage? = nil) -> UIImage? {
        guard let canvas = canvas as? NotebookCanvasView else { return nil }
        let rect = canvas.occupiedRect
        // Bound export memory even when ink is spread over a very large canvas.
        let scale = min(2, 4096 / max(rect.width, rect.height))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let outputSize = CGSize(width: rect.width * scale, height: rect.height * scale)
        return UIGraphicsImageRenderer(size: outputSize, format: format).image { context in
            NotebookTheme.paper.setFill()
            context.fill(CGRect(origin: .zero, size: outputSize))
            context.cgContext.scaleBy(x: scale, y: scale)
            context.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
            PaperPattern.draw(canvas.paper.note.paper, in: context.cgContext, rect: rect, scale: scale)
            canvas.paper.draw(canvas.paper.bounds)
            canvas.drawing.image(from: rect, scale: scale).draw(in: rect)
            for block in canvas.paper.note.blocks ?? [] {
                let bounds = block.bounds.cgRect
                UIColor.white.setFill()
                UIBezierPath(roundedRect: bounds, cornerRadius: 12).fill()
                let provenance = block.isFixture ? "AI · Demo fixture" : "AI · Sources attached"
                let sources = block.evidence.map { evidence in
                    evidence.title + (evidence.url.map { " — " + $0.absoluteString } ?? "")
                }.joined(separator: "\n")
                let text = [provenance, block.body, block.caveat, sources].filter { !$0.isEmpty }.joined(separator: "\n\n")
                (text as NSString).draw(in: bounds.insetBy(dx: 14, dy: 14), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 16), .foregroundColor: UIColor(NotebookTheme.ink)
                ])
            }
            annotations?.draw(in: canvas.paper.bounds)
        }
    }
}

private enum PaperPattern {
    private static let dots: UIColor = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let tile = UIGraphicsImageRenderer(size: CGSize(width: 25.5, height: 25.5), format: format).image { output in
            UIColor(NotebookTheme.muted).withAlphaComponent(0.28).setFill()
            output.cgContext.fillEllipse(in: CGRect(x: 15, y: 15, width: 1.35, height: 1.35))
        }
        return UIColor(patternImage: tile)
    }()

    static func draw(_ style: PaperStyle, in context: CGContext, rect: CGRect, scale: CGFloat) {
        context.setStrokeColor(UIColor(NotebookTheme.muted).withAlphaComponent(0.22).cgColor)
        context.setFillColor(UIColor(NotebookTheme.muted).withAlphaComponent(0.28).cgColor)
        switch style {
        case .blank: break
        case .dotted:
            guard scale >= 0.15 else { return }
            dots.setFill()
            context.fill(rect)
        case .ruled:
            let step = 36 * max(1, ceil(4 / (36 * scale)))
            context.setLineWidth(0.5)
            for y in stride(from: floor((rect.minY - 60) / step) * step + 60, through: rect.maxY, by: step) {
                context.move(to: CGPoint(x: rect.minX, y: y))
                context.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            context.strokePath()
        }
    }
}

/// The grid has only a viewport-sized backing store, regardless of how far the user travels.
private final class PatternView: UIView {
    var style: PaperStyle = .dotted { didSet { if style != oldValue { setNeedsDisplay() } } }
    var viewport = PageViewport(zoom: 1) { didSet { if viewport != oldValue { setNeedsDisplay() } } }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let zoom = max(0.15, viewport.zoom)
        let visible = CGRect(x: viewport.x / zoom, y: viewport.y / zoom,
                             width: bounds.width / zoom, height: bounds.height / zoom)
        context.translateBy(x: -viewport.x, y: -viewport.y)
        context.scaleBy(x: zoom, y: zoom)
        PaperPattern.draw(style, in: context, rect: visible, scale: zoom)
    }
}

/// A sibling paper layer uses the public scroll offset and zoom scale, without inspecting PencilKit's view hierarchy.
private final class PaperView: UIView {
    var note = NoteRecord() {
        didSet {
            // Ink, save metadata, and the viewport do not change the paper pixels.
            if note.paper != oldValue.paper || note.template != oldValue.template ||
                note.text != oldValue.text || note.attachment != oldValue.attachment {
                setNeedsDisplay()
            }
        }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
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
    let pattern = PatternView()
    var readyForViewport = false
    var initialViewport = PageViewport()
    var viewportDidInitialize: (() -> Void)?
    var lassoDidBegin: (() -> Void)?
    var lassoDidFinish: (([CGPoint]) -> Void)?
    var pageSize = NotebookPage.size
    private(set) var worldBounds = CGRect.zero
    private(set) var updatingExtent = false
    private var previousFitZoom: CGFloat = 0
    var fitZoomScale: CGFloat { min(1, max(0.25, bounds.width / pageSize.width)) }
    var visibleRect: CGRect {
        CGRect(x: contentOffset.x / zoomScale, y: contentOffset.y / zoomScale,
               width: bounds.width / zoomScale, height: bounds.height / zoomScale)
    }
    var occupiedRect: CGRect {
        let content = CGRect(origin: .zero, size: pageSize).union(drawing.bounds.isNull ? .null : drawing.bounds.insetBy(dx: -32, dy: -32))
        return (paper.note.blocks ?? []).reduce(content) { $0.union($1.bounds.cgRect.insetBy(dx: -32, dy: -32)) }
    }

    func expand(toInclude rect: CGRect) {
        guard !updatingExtent, rect.minX.isFinite, rect.minY.isFinite,
              rect.width.isFinite, rect.height.isFinite else { return }
        updatingExtent = true
        defer { updatingExtent = false }
        // Grow scrollable margins in chunks; ink stays in its original coordinate space.
        let padded = rect.insetBy(dx: -768, dy: -768)
        let extent = CGRect(x: floor(padded.minX / 1024) * 1024, y: floor(padded.minY / 1024) * 1024,
                            width: ceil(padded.maxX / 1024) * 1024 - floor(padded.minX / 1024) * 1024,
                            height: ceil(padded.maxY / 1024) * 1024 - floor(padded.minY / 1024) * 1024)
        worldBounds = worldBounds.union(extent)
        let offset = contentOffset
        // PencilKit owns its drawable content size. Resizing it during a stroke cancels live ink.
        // Grow only the scroll margins, leaving the native drawing and zoom geometry stable.
        let inset = UIEdgeInsets(top: -worldBounds.minY * zoomScale, left: -worldBounds.minX * zoomScale,
                                 bottom: max(0, worldBounds.maxY * zoomScale - contentSize.height),
                                 right: max(0, worldBounds.maxX * zoomScale - contentSize.width))
        if contentInset != inset { contentInset = inset }
        if contentOffset != offset { contentOffset = offset }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        let wasFit = abs(zoomScale - previousFitZoom) < 0.01
        let fitChanged = abs(previousFitZoom - fitZoomScale) > 0.001
        previousFitZoom = fitZoomScale
        guard !readyForViewport else {
            if wasFit && fitChanged {
                let center = CGPoint(x: visibleRect.midX, y: visibleRect.midY)
                zoomScale = fitZoomScale
                contentOffset = CGPoint(x: center.x * zoomScale - bounds.width / 2,
                                        y: center.y * zoomScale - bounds.height / 2)
            }
            alignPaper()
            return
        }
        paper.isUserInteractionEnabled = false
        paper.isOpaque = false
        paper.backgroundColor = .clear
        minimumZoomScale = 0.15
        maximumZoomScale = 3
        zoomScale = initialViewport.zoom > 0 ? max(minimumZoomScale, min(maximumZoomScale, initialViewport.zoom)) : fitZoomScale
        let offset = CGPoint(x: initialViewport.x.isFinite ? initialViewport.x : 0,
                             y: initialViewport.y.isFinite ? initialViewport.y : 0)
        expand(toInclude: occupiedRect.union(CGRect(x: offset.x / zoomScale, y: offset.y / zoomScale,
                                                   width: bounds.width / zoomScale, height: bounds.height / zoomScale)))
        contentOffset = offset
        readyForViewport = true
        alignPaper()
        viewportDidInitialize?()
    }

    func alignPaper() {
        guard !updatingExtent else { return }
        if readyForViewport { expand(toInclude: visibleRect) }
        paper.transform = CGAffineTransform(scaleX: zoomScale, y: zoomScale)
        paper.frame.origin = CGPoint(x: -contentOffset.x, y: -contentOffset.y)
        pattern.viewport = PageViewport(zoom: zoomScale, x: contentOffset.x, y: contentOffset.y)
    }
}

/// Observe the user's region without replacing PencilKit's native lasso or reading the clipboard.
private final class LassoRegionGesture: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private var points: [CGPoint] = []
    private weak var trackedTouch: UITouch?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delegate = self
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil, touches.count == 1, let touch = touches.first,
              let canvas = view as? NotebookCanvasView, canvas.tool is PKLassoTool,
              touch.type == .pencil || canvas.drawingPolicy == .anyInput else {
            state = state == .possible ? .failed : .cancelled
            return
        }
        canvas.lassoDidBegin?()
        trackedTouch = touch
        points = [worldPoint(touch)]
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .began || state == .changed,
              let touch = trackedTouch, touches.contains(touch) else { return }
        let point = worldPoint(touch)
        if let last = points.last, hypot(point.x - last.x, point.y - last.y) >= 2 { points.append(point) }
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .began || state == .changed,
              let touch = trackedTouch, touches.contains(touch) else { return }
        points.append(worldPoint(touch))
        (view as? NotebookCanvasView)?.lassoDidFinish?(points)
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .cancelled }
    override func reset() { points = []; trackedTouch = nil; super.reset() }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

    private func worldPoint(_ touch: UITouch) -> CGPoint {
        guard let canvas = view as? NotebookCanvasView else { return .zero }
        // UIScrollView bounds already include the content offset.
        let point = touch.location(in: canvas)
        return CGPoint(x: point.x / canvas.zoomScale, y: point.y / canvas.zoomScale)
    }
}

private final class CanvasContainer: UIView {
    let canvas = NotebookCanvasView()
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = NotebookTheme.paper
        canvas.pattern.backgroundColor = NotebookTheme.paper
        canvas.pattern.isUserInteractionEnabled = false
        canvas.pattern.contentMode = .redraw
        addSubview(canvas.pattern)
        addSubview(canvas.paper)
        addSubview(canvas)
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds
        canvas.pattern.frame = bounds
        canvas.alignPaper()
    }
}

struct InkCanvas: UIViewRepresentable {
    @ObservedObject var session: NoteSession
    var controls: CanvasControls
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
        canvas.alwaysBounceHorizontal = true
        canvas.decelerationRate = .fast
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.showsHorizontalScrollIndicator = false
        canvas.showsVerticalScrollIndicator = false
        canvas.drawing = session.drawing
        canvas.initialViewport = session.note.viewport
        canvas.paper.note = session.note
        canvas.pattern.style = session.note.paper
        canvas.tool = tool
        canvas.drawingPolicy = fingerDrawing ? .anyInput : .pencilOnly
        canvas.accessibilityLabel = "Handwriting canvas"
        canvas.accessibilityValue = session.note.template == .checkout ? CheckoutPaper.transcript : session.note.text
        canvas.accessibilityHint = "Write with Apple Pencil. Pinch to zoom. Use two fingers to scroll when finger drawing is on."
        canvas.delegate = context.coordinator
        controls.canvas = canvas
        canvas.addGestureRecognizer(LassoRegionGesture(target: nil, action: nil))
        canvas.lassoDidBegin = { [weak controls] in controls?.selection = nil }
        canvas.lassoDidFinish = { [weak controls] outline in controls?.captureSelection(outline: outline) }
        canvas.viewportDidInitialize = { [weak controls, weak canvas, weak coordinator = context.coordinator] in
            if let canvas { coordinator?.scrollViewDidScroll(canvas) }
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
        let contentChanged = canvas.paper.note != session.note
        let selectionChanged = canvas.paper.note.text != session.note.text ||
            canvas.paper.note.template != session.note.template || canvas.paper.note.attachment != session.note.attachment
        if selectionChanged { DispatchQueue.main.async { controls.selection = nil } }
        canvas.paper.note = session.note
        canvas.pattern.style = session.note.paper
        if contentChanged { context.coordinator.scheduleOverview(canvas) }
        canvas.accessibilityValue = session.note.template == .checkout ? CheckoutPaper.transcript : session.note.text
    }

    func makeCoordinator() -> Coordinator { Coordinator(session: session, controls: controls) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let session: NoteSession
        let controls: CanvasControls
        private var viewportUpdatePending = false
        private var pendingOverview: DispatchWorkItem?
        init(session: NoteSession, controls: CanvasControls) { self.session = session; self.controls = controls }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            controls.selection = nil
            controls.recordChanges(from: session.drawing, to: canvasView.drawing)
            session.setDrawing(canvasView.drawing)
            scheduleOverview(canvasView)
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
            guard let canvas = scrollView as? NotebookCanvasView, canvas.readyForViewport, !canvas.updatingExtent else { return }
            // Keep lifecycle saves current even if the deferred overlay update has not run.
            session.setViewport(PageViewport(zoom: canvas.zoomScale,
                                             x: canvas.contentOffset.x, y: canvas.contentOffset.y))
            guard !viewportUpdatePending else { return }
            viewportUpdatePending = true
            // Coalesce scroll + zoom callbacks and read the latest position after layout.
            DispatchQueue.main.async { [weak self, weak canvas] in
                guard let self else { return }
                self.viewportUpdatePending = false
                guard let canvas else { return }
                let viewport = PageViewport(zoom: canvas.zoomScale,
                                            x: canvas.contentOffset.x, y: canvas.contentOffset.y)
                if self.controls.viewport.value != viewport { self.controls.viewport.value = viewport }
                if self.controls.viewport.size != canvas.bounds.size { self.controls.viewport.size = canvas.bounds.size }
                if self.controls.overview.snapshot.bounds != canvas.worldBounds {
                    self.controls.overview.snapshot.bounds = canvas.worldBounds
                    self.scheduleOverview(canvas)
                }
            }
        }

        fileprivate func scheduleOverview(_ view: PKCanvasView) {
            guard let canvas = view as? NotebookCanvasView, canvas.readyForViewport else { return }
            pendingOverview?.cancel()
            let work = DispatchWorkItem { [weak self, weak canvas] in
                guard let self, let canvas else { return }
                let rect = canvas.worldBounds
                let scale = min(256 / rect.width, 256 / rect.height)
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let image = UIGraphicsImageRenderer(size: CGSize(width: rect.width * scale, height: rect.height * scale), format: format).image { output in
                    output.cgContext.scaleBy(x: scale, y: scale)
                    output.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
                    canvas.paper.draw(canvas.paper.bounds)
                    canvas.drawing.image(from: rect, scale: scale).draw(in: rect)
                }
                self.controls.overview.snapshot = CanvasOverview.Snapshot(bounds: rect, imageBounds: rect, image: image)
            }
            pendingOverview = work
            // Cache a small preview after ink settles; scrolling only moves the viewport outline.
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(180), execute: work)
        }
    }
}

import Testing
import PencilKit
import Combine
import SwiftUI
@testable import ScribbleScout

@Suite("Notebook persistence and editing", .serialized)
struct NotebookTests {
    @MainActor
    @Test
    func testPencilCanvasIsActiveOnOpeningAndAfterClearing() throws {
        try withRepository { repository in
            let session = NoteSession(note: NoteRecord(), drawing: PKDrawing(), repository: repository)
            let controls = CanvasControls()
            let host = UIHostingController(rootView: InkCanvas(session: session, controls: controls,
                tool: PKInkingTool(.pen, color: .black, width: 3), fingerDrawing: false))
            let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 768, height: 1024)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            host.view.layoutIfNeeded()
            let canvas = try #require(controls.canvas)
            #expect(canvas.drawingPolicy == .pencilOnly)
            #expect(canvas.isDrawingEnabled)
            #expect(canvas.isFirstResponder, "The startup canvas must own Pencil input")
            canvas.drawing = drawing()
            canvas.delegate?.canvasViewDrawingDidChange?(canvas)
            canvas.resignFirstResponder()
            canvas.drawing = PKDrawing()
            canvas.delegate?.canvasViewDrawingDidChange?(canvas)
            #expect(canvas.isFirstResponder, "Clearing ink must leave Pencil input active")
        }
    }

    @Test
    func testOnDeviceSearchPersistsAndRebuildsItsDisposableCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("search-index.json")
        let document = NoteSearchDocument(id: UUID(), title: "Dog care", text: "Take the puppy outside for a walk.")
        let service = LocalSemanticSearch(cacheURL: cache)
        let first = try await service.search("puppy", documents: [document])
        #expect(first.matches.first?.id == document.id)
        let savedData = try Data(contentsOf: cache)
        let saved = try JSONDecoder().decode(NoteSearchIndex.self, from: savedData)
        #expect(saved.entries[document.id]?.text == document.text)
        let semantic = try await service.search("Walk the dog", documents: [document])
        if saved.dimensions > 0 {
            #expect(semantic.matches.first?.id == document.id)
            #expect(first.status.contains("On-device meaning"))
        } else {
            #expect(first.status.contains("model unavailable"))
        }
        _ = try await service.search("puppy", documents: [document])
        #expect(try Data(contentsOf: cache) == savedData, "Unchanged text must not rewrite the cache")
        let reopened = try await LocalSemanticSearch(cacheURL: cache).search("puppy", documents: [document])
        #expect(reopened.matches.first?.id == document.id)

        try Data("damaged cache".utf8).write(to: cache)
        let rebuilt = try await LocalSemanticSearch(cacheURL: cache).search("puppy", documents: [document])
        #expect(rebuilt.matches.first?.id == document.id)
        let empty = try await service.search("puppy", documents: [])
        #expect(empty.matches.isEmpty)
        let removed = try JSONDecoder().decode(NoteSearchIndex.self, from: Data(contentsOf: cache))
        #expect(removed.entries.isEmpty)
    }

    @MainActor
    @Test
    func testOnlySearchableEditsRequestIndexRefresh() throws {
        try withRepository { repository in
            let session = NoteSession(note: NoteRecord(), drawing: PKDrawing(), repository: repository)
            var refreshes = 0
            session.onSearchableChange = { refreshes += 1 }
            session.edit { $0.text = "New searchable text" }
            session.edit { $0.title = "Renamed" }
            #expect(refreshes == 2)
            session.edit { $0.text = "New searchable text" }
            session.edit { $0.paper = .blank }
            session.setDrawing(drawing())
            session.setViewport(PageViewport(zoom: 2, x: 20, y: 30))
            #expect(session.flush())
            #expect(refreshes == 2)
        }
    }

    private func drawing() -> PKDrawing {
        let points = [CGPoint(x: 80, y: 100), CGPoint(x: 160, y: 140), CGPoint(x: 240, y: 100)]
        let path = PKStrokePath(controlPoints: points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                          size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date(timeIntervalSince1970: 1_000))
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)])
    }

    private func withRepository(_ test: (LocalNotebook) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try test(LocalNotebook(root: root))
    }

    @Test(arguments: PaperStyle.allCases)
    func testRealInkAndMetadataSurviveReopeningAndNotesStaySeparate(paper: PaperStyle) throws {
        try withRepository { repository in
            var first = NoteRecord(title: "Planning", text: "Remember the decision", paper: paper,
                                   viewport: PageViewport(zoom: 1.5, x: 120, y: 240), drawingRevision: 1)
            first = try repository.save(first, drawing: drawing(), inkChanged: true)
            let second = try repository.save(NoteRecord(title: "Another canvas"), drawing: PKDrawing(), inkChanged: true)
            let reopened = try LocalNotebook(root: repository.root).load(first.id)
            #expect(reopened.note == first)
            try #require(reopened.drawing.strokes.count == 1)
            #expect(reopened.drawing.strokes[0].path[1].location == CGPoint(x: 160, y: 140))
            #expect(try repository.load(second.id).drawing.strokes.isEmpty)
            #expect(try repository.list().notes.count == 2)
            #expect(!reopened.recovered)
        }
    }

    @Test
    func testBrokenMetadataAndInterruptedInkWriteRecoverPreviousSnapshot() throws {
        try withRepository { repository in
            var note = try repository.save(NoteRecord(title: "Original"), drawing: drawing(), inkChanged: true)
            let originalFile = note.drawingFile
            note.title = "Updated"
            note = try repository.save(note, drawing: drawing(), inkChanged: false)
            #expect(note.drawingFile == originalFile, "Metadata edits must not duplicate ink")
            let folder = repository.folder(for: note.id)
            try Data("orphaned pending ink".utf8).write(to: folder.appendingPathComponent("interrupted.drawing"))
            try Data("truncated json".utf8).write(to: folder.appendingPathComponent("note.json"))
            let recovered = try repository.load(note.id)
            #expect(recovered.recovered)
            #expect(recovered.note.title == "Original")
            #expect(recovered.drawing.strokes.count == 1)
            let repaired = try repository.save(recovered.note, drawing: recovered.drawing, inkChanged: false)
            #expect(try repository.load(repaired.id).note.title == "Original")
        }
    }

    @Test
    func testCorruptedLatestInkFallsBackWithoutOverwritingRecoveryCopy() throws {
        try withRepository { repository in
            var note = try repository.save(NoteRecord(title: "Safe ink"), drawing: drawing(), inkChanged: true)
            let previousFile = try #require(note.drawingFile)
            note.drawingRevision += 1
            note = try repository.save(note, drawing: PKDrawing(), inkChanged: true)
            try Data("broken ink".utf8).write(to: repository.folder(for: note.id).appendingPathComponent(try #require(note.drawingFile)))
            let recovered = try repository.load(note.id)
            #expect(recovered.recovered)
            #expect(recovered.note.drawingFile == previousFile)
            #expect(recovered.drawing.strokes.count == 1)
        }
    }

    @Test
    func testOnlyCurrentAndPreviousInkAreRetained() throws {
        try withRepository { repository in
            var note = NoteRecord()
            for revision in 1...5 {
                note.drawingRevision = revision
                note = try repository.save(note, drawing: drawing(), inkChanged: true)
            }
            let files = try FileManager.default.contentsOfDirectory(at: repository.folder(for: note.id), includingPropertiesForKeys: nil)
            #expect(files.filter { $0.pathExtension == "drawing" }.count == 2)
            #expect(try repository.load(note.id).note.drawingRevision == 5)
        }
    }

    @Test(arguments: ["id", "drawingFile"])
    func testInvalidSnapshotRecoversPreviousCopy(field: String) throws {
        try withRepository { repository in
            var note = try repository.save(NoteRecord(title: "Safe copy"), drawing: drawing(), inkChanged: true)
            note.title = "Latest copy"
            note = try repository.save(note, drawing: drawing(), inkChanged: false)
            let currentURL = repository.folder(for: note.id).appendingPathComponent("note.json")
            var metadata = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: currentURL)) as? [String: Any])
            // A readable external drawing ensures this checks path validation, not a missing-file error.
            try drawing().dataRepresentation().write(to: repository.root.appendingPathComponent("outside.drawing"))
            metadata[field] = field == "id" ? UUID().uuidString : "../outside.drawing"
            try JSONSerialization.data(withJSONObject: metadata).write(to: currentURL)

            let recovered = try repository.load(note.id)
            #expect(recovered.recovered)
            #expect(recovered.note.title == "Safe copy")
            #expect(recovered.drawing.strokes.count == 1)
        }
    }

    @Test
    func testMissingLatestDrawingRecoversPreviousInk() throws {
        try withRepository { repository in
            var note = try repository.save(NoteRecord(), drawing: drawing(), inkChanged: true)
            let previousFile = note.drawingFile
            note = try repository.save(note, drawing: PKDrawing(), inkChanged: true)
            try FileManager.default.removeItem(at: repository.folder(for: note.id)
                .appendingPathComponent(try #require(note.drawingFile)))

            let recovered = try repository.load(note.id)
            #expect(recovered.recovered)
            #expect(recovered.note.drawingFile == previousFile)
            #expect(recovered.drawing.strokes.count == 1)
        }
    }

    @Test
    func testLibrarySortsNotesAndReportsRecoveryWithoutDeletingUnreadableFiles() throws {
        try withRepository { repository in
            let older = try repository.save(NoteRecord(title: "Older", updatedAt: Date(timeIntervalSince1970: 1)),
                                            drawing: PKDrawing(), inkChanged: true)
            var newer = try repository.save(NoteRecord(title: "Newer", updatedAt: Date(timeIntervalSince1970: 2)),
                                            drawing: drawing(), inkChanged: true)
            newer.title = "Incomplete update"
            _ = try repository.save(newer, drawing: drawing(), inkChanged: false)
            try Data("broken metadata".utf8).write(to: repository.folder(for: newer.id).appendingPathComponent("note.json"))
            let brokenID = UUID()
            let brokenFolder = repository.folder(for: brokenID)
            try FileManager.default.createDirectory(at: brokenFolder, withIntermediateDirectories: true)
            let unreadableURL = brokenFolder.appendingPathComponent("note.json")
            let unreadableData = Data("keep this for recovery".utf8)
            try unreadableData.write(to: unreadableURL)
            try Data().write(to: repository.root.appendingPathComponent("unrelated-file"))

            let listing = try repository.list()
            #expect(listing.notes.map(\.id) == [newer.id, older.id])
            #expect(listing.notes.first?.title == "Newer")
            #expect(listing.warnings.count == 2)
            #expect(listing.warnings.contains { $0.contains("Recovered") && $0.contains("Newer") })
            #expect(listing.warnings.contains { $0.contains(brokenFolder.lastPathComponent) })
            #expect(try Data(contentsOf: unreadableURL) == unreadableData)
            #expect(throws: (any Error).self) { try repository.load(brokenID) }
        }
    }

    @MainActor
    @Test
    func testViewportSavePreservesEditDateAndInkAndCleanFlushDoesNotCommitAgain() throws {
        try withRepository { repository in
            let note = try repository.save(NoteRecord(updatedAt: Date(timeIntervalSince1970: 1)),
                                           drawing: drawing(), inkChanged: true)
            let session = NoteSession(note: note, drawing: drawing(), repository: repository)
            var savedNotes: [NoteRecord] = []
            session.onSave = { savedNotes.append($0) }
            let viewport = PageViewport(zoom: 2, x: 50, y: 100)
            session.setViewport(viewport)
            #expect(session.flush())
            let reopened = try repository.load(note.id)
            #expect(reopened.note.viewport == viewport)
            #expect(reopened.note.updatedAt == note.updatedAt)
            #expect(reopened.note.drawingFile == note.drawingFile)
            #expect(reopened.drawing.strokes.count == 1)

            session.setViewport(viewport)
            #expect(session.flush())
            #expect(savedNotes.count == 1)
        }
    }

    @MainActor
    @Test
    func testNavigationKeepsLatestViewportWithoutPublishingEditorUpdates() throws {
        try withRepository { repository in
            let saved = try repository.save(NoteRecord(), drawing: drawing(), inkChanged: true)
            let session = NoteSession(note: saved, drawing: drawing(), repository: repository)
            let controls = CanvasControls()
            var editorUpdates = 0
            var toolbarUpdates = 0
            let sessionSubscription = session.objectWillChange.sink { editorUpdates += 1 }
            let controlsSubscription = controls.objectWillChange.sink { toolbarUpdates += 1 }
            defer { sessionSubscription.cancel(); controlsSubscription.cancel() }

            for step in 1...120 {
                let viewport = PageViewport(zoom: 1.5, x: Double(step), y: Double(step * 2))
                session.setViewport(viewport)
                controls.viewport.value = viewport
                controls.refresh()
            }
            let latest = PageViewport(zoom: 1.5, x: 120, y: 240)
            #expect(session.note.viewport == latest)
            #expect(editorUpdates == 0)
            #expect(toolbarUpdates == 0)

            session.edit { $0.text = "Still editable after navigation" }
            #expect(editorUpdates > 0)
            #expect(session.flush())
            let reopened = try repository.load(session.id)
            #expect(reopened.note.viewport == latest)
            #expect(reopened.note.text == "Still editable after navigation")
            #expect(reopened.note.drawingFile == saved.drawingFile)
        }
    }

    @MainActor
    @Test
    func testCanvasRestoresAndCoalescesViewportWhileImmediateSaveKeepsLatestPosition() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalNotebook(root: root)
        let initial = PageViewport(zoom: 1.5, x: 50, y: 100)
        let saved = try repository.save(NoteRecord(viewport: initial), drawing: PKDrawing(), inkChanged: true)
        let session = NoteSession(note: saved, drawing: PKDrawing(), repository: repository)
        let controls = CanvasControls()
        let host = UIHostingController(rootView: InkCanvas(session: session, controls: controls,
                                                         tool: PKInkingTool(.pen), fingerDrawing: false))
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 600, height: 500)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        let canvas = try #require(controls.canvas)
        canvas.layoutIfNeeded()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(controls.viewport.value == initial)

        var overlayUpdates = 0
        let subscription = controls.viewport.objectWillChange.sink { overlayUpdates += 1 }
        defer { subscription.cancel() }
        for step in 1...120 {
            canvas.contentOffset = CGPoint(x: step, y: step * 2)
            canvas.delegate?.scrollViewDidScroll?(canvas)
            canvas.delegate?.scrollViewDidZoom?(canvas)
        }
        let latest = PageViewport(zoom: canvas.zoomScale, x: 120, y: 240)
        #expect(session.note.viewport == latest)
        #expect(overlayUpdates == 0)
        // Backgrounding or changing notes may flush before the queued overlay update.
        #expect(session.flush())
        #expect(try repository.load(session.id).note.viewport == latest)

        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(controls.viewport.value == latest)
        #expect(overlayUpdates == 1)
    }

    @MainActor
    @Test
    func testInfiniteCanvasNavigatesEveryDirectionAndRestoresNegativeInk() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalNotebook(root: root)
        let session = NoteSession(note: NoteRecord(), drawing: PKDrawing(), repository: repository)
        let controls = CanvasControls()
        let host = UIHostingController(rootView: InkCanvas(session: session, controls: controls,
                                                         tool: PKInkingTool(.pen), fingerDrawing: false))
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 600, height: 500)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        let canvas = try #require(controls.canvas)
        canvas.layoutIfNeeded()
        let zoom = canvas.zoomScale
        for point in [CGPoint(x: 6000, y: 5000), CGPoint(x: -6000, y: 5000),
                      CGPoint(x: 6000, y: -5000), CGPoint(x: -6000, y: -5000)] {
            controls.navigate(to: point)
            let center = CGPoint(x: (canvas.contentOffset.x + canvas.bounds.width / 2) / zoom,
                                 y: (canvas.contentOffset.y + canvas.bounds.height / 2) / zoom)
            #expect(abs(center.x - point.x) < 1)
            #expect(abs(center.y - point.y) < 1)
            #expect(canvas.zoomScale == zoom)
        }
        controls.addRectangle(color: .red, width: 6)
        canvas.delegate?.canvasViewDrawingDidChange?(canvas)
        #expect(canvas.drawing.bounds.maxX < 0)
        #expect(canvas.drawing.bounds.maxY < 0)
        #expect(session.flush())
        let reopened = try repository.load(session.id)
        #expect(reopened.drawing.strokes.count == 1)
        #expect(reopened.drawing.bounds == canvas.drawing.bounds)
        #expect(reopened.note.viewport.x < 0 && reopened.note.viewport.y < 0)
        let export = try #require(controls.pageImage())
        #expect(max(export.size.width, export.size.height) <= 4096)

        try await Task.sleep(for: .milliseconds(400))
        let snapshot = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let pixels = try #require(snapshot.cgImage?.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(pixels))
        let redPixels = stride(from: 0, to: CFDataGetLength(pixels) - 4, by: 4).filter {
            bytes[$0 + 1] < 100 && ((bytes[$0] > 180 && bytes[$0 + 2] < 100) || (bytes[$0 + 2] > 180 && bytes[$0] < 100))
        }.count
        #expect(redPixels > 100, "PencilKit must visibly render ink at negative coordinates")
        let preview = try #require(controls.overview.snapshot.image)
        #expect(max(preview.size.width, preview.size.height) <= 256)

        let restored = NoteSession(note: reopened.note, drawing: reopened.drawing, repository: repository)
        let restoredControls = CanvasControls()
        let restoredHost = UIHostingController(rootView: InkCanvas(session: restored, controls: restoredControls,
                                                                 tool: PKInkingTool(.pen), fingerDrawing: false))
        window.rootViewController = restoredHost
        restoredHost.view.layoutIfNeeded()
        restoredControls.canvas?.layoutIfNeeded()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(restoredControls.viewport.value == reopened.note.viewport)
        #expect(restoredControls.canvas?.drawing.bounds == reopened.drawing.bounds)
    }

    @Test
    func testMinimapCoordinatesRoundTripWithNegativeBounds() {
        let map = CanvasMapGeometry(bounds: CGRect(x: -6000, y: -5000, width: 16000, height: 12000),
                                    size: CGSize(width: 180, height: 108))
        let viewport = CGRect(x: -2000, y: 3000, width: 900, height: 700)
        let mapped = map.map(viewport)
        let center = map.worldPoint(CGPoint(x: mapped.midX, y: mapped.midY))
        #expect(abs(center.x - viewport.midX) < 0.001)
        #expect(abs(center.y - viewport.midY) < 0.001)
        #expect(map.map(map.bounds).minX >= 0)
        #expect(map.map(map.bounds).maxX <= map.size.width)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func testAutosaveCommitsLatestTextAndInk() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalNotebook(root: root)
        let session = NoteSession(note: NoteRecord(updatedAt: Date(timeIntervalSince1970: 1)),
                                  drawing: PKDrawing(), repository: repository)
        await confirmation("Autosave publishes the latest edits once") { saved in
            var committed: NoteRecord?
            session.onSave = { committed = $0; saved() }
            session.edit { $0.text = "First draft" }
            session.edit { $0.text = "Latest draft" }
            session.setDrawing(drawing())
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(5))
            while committed == nil && clock.now < deadline {
                try? await clock.sleep(for: .milliseconds(20))
            }
            #expect(committed?.text == "Latest draft")
            #expect(session.saveError == nil)
        }
        let reopened = try repository.load(session.id)
        #expect(reopened.note.text == "Latest draft")
        #expect(reopened.note.updatedAt > Date(timeIntervalSince1970: 1))
        #expect(reopened.note.drawingRevision == 1)
        #expect(reopened.drawing.strokes.count == 1)
    }

    @MainActor
    @Test
    func testFailedSaveKeepsEditsAndRetryCommitsThem() throws {
        try withRepository { repository in
            try FileManager.default.createDirectory(at: repository.root, withIntermediateDirectories: true)
            let note = NoteRecord()
            try Data().write(to: repository.folder(for: note.id)) // A file blocks the note directory.
            let session = NoteSession(note: note, drawing: drawing(), repository: repository)
            var savedNotes: [NoteRecord] = []
            session.onSave = { savedNotes.append($0) }
            session.edit { $0.text = "Unsaved work stays here" }
            #expect(!session.flush())
            #expect(session.saveError != nil)
            #expect(session.note.text == "Unsaved work stays here")
            #expect(session.drawing.strokes.count == 1)
            #expect(savedNotes.isEmpty)

            try FileManager.default.removeItem(at: repository.folder(for: note.id))
            #expect(session.flush())
            #expect(session.saveError == nil)
            #expect(session.saveMessage == "Saved on this iPad")
            #expect(savedNotes == [session.note])
            let reopened = try repository.load(note.id)
            #expect(reopened.note.text == "Unsaved work stays here")
            #expect(reopened.drawing.strokes.count == 1)
        }
    }

    @Test
    func testReferencePageAndCardStatePersistWithoutChangingExistingPageCoordinates() throws {
        try withRepository { repository in
            var sample = NoteRecord.checkoutExample
            sample.keptResearch = true
            sample.attachment = Data([1, 2, 3])
            let saved = try repository.save(sample, drawing: drawing(), inkChanged: true)
            let reopened = try repository.load(saved.id)
            #expect(reopened.note.template == .checkout)
            #expect(reopened.note.keptResearch == true)
            #expect(reopened.note.attachment == sample.attachment)
            #expect(NotebookPage.size(for: reopened.note) == CGSize(width: 1448, height: 1026))

            var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(NoteRecord())) as? [String: Any])
            legacy.removeValue(forKey: "template")
            legacy.removeValue(forKey: "keptResearch")
            legacy.removeValue(forKey: "attachment")
            let existing = try JSONDecoder().decode(NoteRecord.self, from: JSONSerialization.data(withJSONObject: legacy))
            #expect(existing.template == nil)
            #expect(NotebookPage.size(for: existing) == CGSize(width: 1000, height: 1400))
        }
    }

    @MainActor
    @Test
    func testLassoCropMasksNeighboursAndDoesNotChangeInkOrClipboard() throws {
        try withRepository { repository in
            let red = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300)).image { output in
                UIColor.red.setFill()
                output.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
            }
            let note = NoteRecord(attachment: red.pngData())
            let originalInk = drawing()
            let session = NoteSession(note: note, drawing: originalInk, repository: repository)
            let controls = CanvasControls()
            let host = UIHostingController(rootView: InkCanvas(session: session, controls: controls,
                                                             tool: PKLassoTool(), fingerDrawing: true))
            let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 600, height: 500)
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true; window.rootViewController = nil }
            host.view.layoutIfNeeded()
            let canvas = try #require(controls.canvas)
            let clipboardVersion = UIPasteboard.general.changeCount
            controls.captureSelection(outline: [CGPoint(x: 60, y: 60), CGPoint(x: 260, y: 60), CGPoint(x: 60, y: 260)])
            let selected = try #require(controls.selection)
            #expect(selected.bounds == CGRect(x: 60, y: 60, width: 200, height: 200))
            #expect(selected.image.size == CGSize(width: 400, height: 400))
            #expect(selected.contextBounds == CGRect(x: -240, y: -240, width: 800, height: 800))
            #expect(selected.contextImage.size == CGSize(width: 1600, height: 1600))
            let contextCG = try #require(selected.contextImage.cgImage)
            let contextPixel = try #require(contextCG.cropping(to: CGRect(x: 960, y: 960, width: 1, height: 1)))
            let data = try #require(contextPixel.dataProvider?.data)
            let bytes = try #require(CFDataGetBytePtr(data))
            #expect(min(bytes[0], bytes[1], bytes[2]) < 120, "The nearby red photo must remain available as context outside the lasso")
            let cg = try #require(selected.image.cgImage)
            var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            try pixels.withUnsafeMutableBytes { bytes in
                let context = try #require(CGContext(data: bytes.baseAddress, width: cg.width, height: cg.height,
                                                     bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                                     space: CGColorSpaceCreateDeviceRGB(),
                                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            }
            // Outside the triangular lasso must be white, even though a photo fills its bounding box.
            let outside = (360 * cg.width + 360) * 4
            #expect(pixels[outside] > 240 && pixels[outside + 1] > 240 && pixels[outside + 2] > 240)
            #expect(canvas.drawing.dataRepresentation() == originalInk.dataRepresentation())
            #expect(UIPasteboard.general.changeCount == clipboardVersion)
            controls.captureSelection(outline: [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])
            #expect(controls.selection == nil, "A drag or tap must not become a selected region")
            controls.captureSelection(outline: [CGPoint(x: -8000, y: -6000), CGPoint(x: -3000, y: -6000),
                                               CGPoint(x: -3000, y: -1000), CGPoint(x: -8000, y: -1000)])
            let large = try #require(controls.selection)
            #expect(max(large.image.size.width, large.image.size.height) <= 1600)
        }
    }

    @MainActor
    @Test
    func testInsertRectangleUsesVisiblePageCoordinatesAndKeepsExistingInk() throws {
        let canvas = PKCanvasView(frame: CGRect(x: 0, y: 0, width: 600, height: 500))
        canvas.contentSize = NotebookPage.size
        canvas.drawing = drawing()
        let controls = CanvasControls()
        controls.canvas = canvas
        controls.addRectangle(color: .red, width: 3)
        #expect(canvas.drawing.strokes.count == 2)
        let stroke = try #require(canvas.drawing.strokes.last)
        let path = stroke.path
        #expect(path.count >= 3)
        #expect(path.first?.location == CGPoint(x: 80, y: 80))
        #expect(path.last?.location == path.first?.location)
        if path.count >= 3 { #expect(path[2].location == CGPoint(x: 260, y: 190)) }
    }
    @MainActor
    @Test
    func testAIBlockAcceptanceEditingUndoReopenAndRecoveryPreserveInkAndEvidence() throws {
        try withRepository { repository in
            let originalInk = drawing()
            let session = NoteSession(note: NoteRecord(), drawing: originalInk, repository: repository)
            let source = CanvasSource.region(note: session.note, drawing: originalInk, bounds: originalInk.bounds)
            let evidence = Evidence(kind: .web, title: "Source", url: URL(string: "https://example.com"), excerpt: "Supporting text")
            let request = AssistanceRequest(region: source, intent: .webResearch, sourceMode: .web, question: "Check this")
            let suggestion = Suggestion(request: request, answer: "Draft answer", caveat: "Check assumptions", evidence: [evidence], state: .ready)
            let manager = UndoManager()
            manager.groupsByEvent = false
            manager.beginUndoGrouping()
            let id = session.insertBlock(suggestion, at: CanvasBounds(x: 300, y: 200, width: 320, height: 200), undoManager: manager)
            manager.endUndoGrouping()
            #expect(session.note.blocks?.count == 1)
            manager.undo()
            #expect(session.note.blocks?.isEmpty == true)
            manager.redo()
            #expect(session.note.blocks?.first?.id == id)
            session.updateBlock(id, body: "Edited by me")
            session.moveBlock(id, to: CanvasBounds(x: -300, y: 600, width: 320, height: 200))
            #expect(session.note.blocks?.first?.editedAt != nil)
            #expect(session.flush())
            let reopened = try repository.load(session.id)
            let block = try #require(reopened.note.blocks?.first)
            #expect(block.body == "Edited by me")
            #expect(block.evidence == [evidence])
            #expect(block.region == source)
            #expect(block.bounds.x == -300)
            #expect(reopened.drawing.strokes.count == originalInk.strokes.count)
            #expect(reopened.drawing.bounds == originalInk.bounds)
            // Commit another metadata change, then corrupt it: recovery retains the block and its provenance.
            session.edit { $0.title = "Latest" }
            #expect(session.flush())
            try Data("interrupted".utf8).write(to: repository.folder(for: session.id).appendingPathComponent("note.json"))
            #expect(try repository.load(session.id).note.blocks?.first == block)
            session.deleteBlock(id)
            #expect(session.note.blocks?.isEmpty == true)
        }
    }

    @Test
    func testRegionIgnoresUnrelatedInkRebasesTranslationAndRejectsChangedOrDeletedSource() throws {
        let note = NoteRecord()
        let original = drawing()
        let source = CanvasSource.region(note: note, drawing: original, bounds: original.bounds.insetBy(dx: -10, dy: -10))
        #expect(CanvasSource.resolve(source, note: note, drawing: original) != nil)
        let outside = original.transformed(using: CGAffineTransform(translationX: 1000, y: 1000))
        let appended = PKDrawing(strokes: original.strokes + outside.strokes)
        #expect(CanvasSource.resolve(source, note: note, drawing: appended) != nil)
        let moved = original.transformed(using: CGAffineTransform(translationX: -300, y: 400))
        let resolved = try #require(CanvasSource.resolve(source, note: note, drawing: moved))
        #expect(abs(resolved.bounds.x - (source.bounds.x - 300)) < 0.1)
        #expect(abs(resolved.bounds.y - (source.bounds.y + 400)) < 0.1)
        var repeated = resolved
        for _ in 0..<4 {
            repeated = try #require(CanvasSource.resolve(repeated, note: note, drawing: moved))
            #expect(repeated.bounds == resolved.bounds, "Repeated validation must not translate the anchor twice")
        }
        #expect(CanvasSource.resolve(source, note: note, drawing: PKDrawing()) == nil)
        let resized = original.transformed(using: CGAffineTransform(scaleX: 2, y: 2))
        #expect(CanvasSource.resolve(source, note: note, drawing: resized) == nil)
        var otherNote = note
        otherNote.id = UUID()
        #expect(CanvasSource.resolve(source, note: otherNote, drawing: original) == nil)
    }

    @Test
    func testLegacyNotesOpenWithoutBlocksAndTypedSourcesExpireOnlyWhenTextChanges() throws {
        let note = NoteRecord(text: "Original question")
        let encoded = try JSONEncoder().encode(note)
        var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "blocks")
        let legacy = try JSONDecoder().decode(NoteRecord.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.blocks == nil)
        let source = CanvasSource.typedRegion(note: legacy)
        var updated = legacy
        updated.title = "Renamed"
        #expect(CanvasSource.resolve(source, note: updated, drawing: drawing()) != nil)
        updated.text = "Corrected question"
        #expect(CanvasSource.resolve(source, note: updated, drawing: drawing()) == nil)
    }

}

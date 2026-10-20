import XCTest
import UIKit

final class CanvasInputTests: XCTestCase {
    @MainActor
    func testWritingOnStartupNoteAndAfterClearingInk() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-fingerDrawing", "YES"]
        app.launch()
        app.buttons["Open notebook"].tap()
        app.buttons["newNote"].tap()
        app.buttons["Burgundy ink"].tap()
        // Save an empty note, then exercise the editor created at app startup.
        app.buttons["Page options"].tap()
        XCTAssertTrue(app.buttons["Saved on this iPad"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        let empty = try ink(in: app.screenshot().image, includeDarkInk: true).count
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.30))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.45))
        for _ in 0..<2 {
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
            XCTAssertGreaterThan(try ink(in: app.screenshot().image, includeDarkInk: true).count, empty + 100,
                                 "The startup note and a completely cleared canvas must accept ink")
            let undo = app.buttons["Undo ink"]
            guard undo.isEnabled else { XCTFail("Drawing must create an undoable stroke"); return }
            undo.tap()
            XCTAssertLessThanOrEqual(try ink(in: app.screenshot().image, includeDarkInk: true).count, empty + 20)
        }
        app.buttons["Burgundy ink"].tap()
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        app.buttons["Page options"].tap()
        XCTAssertTrue(app.buttons["Saved on this iPad"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        let saved = try ink(in: app.screenshot().image).count
        XCTAssertGreaterThan(saved, 100)
        app.buttons["Eraser"].tap()
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertLessThanOrEqual(try ink(in: app.screenshot().image).count, 20)
        app.buttons["Pen"].tap()
        app.buttons["Burgundy ink"].tap()
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertGreaterThan(try ink(in: app.screenshot().image).count, 100,
                             "Erasing every saved stroke must leave the canvas writable")
    }

    @MainActor
    func testContinuousInkUndoAndFingerPan() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-fingerDrawing", "YES"]
        app.launch()
        app.buttons["Open notebook"].tap()
        app.buttons["newNote"].tap()
        XCTAssertTrue(app.buttons["Show canvas minimap"].exists)
        XCTAssertFalse(app.otherElements["canvasMinimap"].exists)
        app.buttons["Burgundy ink"].tap()
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.30))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.45))
        let empty = try ink(in: app.screenshot().image)
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        let drawn = try ink(in: app.screenshot().image)
        XCTAssertGreaterThan(drawn.count, empty.count + 100, "Dragging must render a continuous stroke, not an invisible dot")
        app.buttons["Undo ink"].tap()
        XCTAssertLessThanOrEqual(try ink(in: app.screenshot().image).count, empty.count + 20)

        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertGreaterThan(try ink(in: app.screenshot().image).count, empty.count + 100)
        app.buttons["Page options"].tap()
        XCTAssertTrue(app.buttons["Saved on this iPad"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["-fingerDrawing", "NO"]
        app.launch()
        let beforePan = try ink(in: app.screenshot().image)
        XCTAssertGreaterThan(beforePan.count, empty.count + 100)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.60, dy: 0.60))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.60, dy: 0.50)),
                   withVelocity: .slow, thenHoldForDuration: 0.1)
        let afterPan = try ink(in: app.screenshot().image)
        XCTAssertGreaterThan(afterPan.count, 20)
        XCTAssertGreaterThan(abs(afterPan.centerY - beforePan.centerY), 40, "A finger pan must move the ink with the canvas")
    }

    @MainActor
    func testNotebookNavigation() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Open notebook"].tap()
        XCTAssertTrue(app.staticTexts["Scribble Scout"].exists)
        let firstNote = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "note-")).firstMatch
        XCTAssertTrue(firstNote.waitForExistence(timeout: 5))
        let noteID = firstNote.identifier
        firstNote.tap()
        XCTAssertTrue(app.textFields["noteTitle"].exists)
        app.buttons["Open notebook"].tap()
        XCTAssertTrue(app.buttons[noteID].isSelected)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Notebook navigation portrait"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let search = app.textFields["Find a note"]
        search.tap()
        search.typeText("zzzxqnomatch987654")
        XCTAssertTrue(app.staticTexts["No notes found"].waitForExistence(timeout: 10))
        app.buttons["Clear search"].tap()
        XCTAssertTrue(app.buttons[noteID].waitForExistence(timeout: 5))
        app.buttons["Close notebook"].tap()
        app.buttons["Open notebook"].tap()
        app.buttons["newNote"].tap()
        XCTAssertEqual(app.textFields["noteTitle"].value as? String, "Untitled note")
        app.buttons["Open notebook"].tap()

        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1) // Let the system rotation finish before capturing the layout.
        let landscape = XCTAttachment(screenshot: app.screenshot())
        landscape.name = "Notebook navigation landscape"
        landscape.lifetime = .keepAlways
        add(landscape)
        XCUIDevice.shared.orientation = .portrait

        app.terminate()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.buttons["Open notebook"].tap()
        XCTAssertTrue(app.buttons["Close notebook"].isHittable)
        Thread.sleep(forTimeInterval: 1) // Capture the open drawer after its entrance animation.
        XCTAssertGreaterThanOrEqual(app.textFields["Find a note"].frame.minX, 0)
        XCTAssertLessThanOrEqual(app.textFields["Find a note"].frame.maxX, app.frame.maxX)
        let largeType = XCTAttachment(screenshot: app.screenshot())
        largeType.name = "Notebook navigation accessibility text"
        largeType.lifetime = .keepAlways
        add(largeType)
    }

    private func ink(in image: UIImage, includeDarkInk: Bool = false) throws -> (count: Int, centerY: Double) {
        let full = try XCTUnwrap(image.cgImage)
        let rect = CGRect(x: Double(full.width) * 0.15, y: Double(full.height) * 0.20,
                          width: Double(full.width) * 0.60, height: Double(full.height) * 0.40)
        let crop = try XCTUnwrap(full.cropping(to: rect))
        var pixels = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: crop.width, height: crop.height,
                                                 bitsPerComponent: 8, bytesPerRow: crop.width * 4,
                                                 space: CGColorSpaceCreateDeviceRGB(),
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        }
        var count = 0
        var totalY = 0
        for offset in stride(from: 0, to: pixels.count, by: 4)
        where (pixels[offset] > 80 || includeDarkInk) && pixels[offset + 1] < 80 && pixels[offset + 2] < 130 {
            count += 1
            totalY += offset / 4 / crop.width
        }
        return (count, count == 0 ? 0 : Double(totalY) / Double(count))
    }
}

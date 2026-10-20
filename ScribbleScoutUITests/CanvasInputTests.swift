import XCTest
import UIKit

final class CanvasInputTests: XCTestCase {
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

    private func ink(in image: UIImage) throws -> (count: Int, centerY: Double) {
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
        where pixels[offset] > 80 && pixels[offset + 1] < 80 && pixels[offset + 2] < 130 {
            count += 1
            totalY += offset / 4 / crop.width
        }
        return (count, count == 0 ? 0 : Double(totalY) / Double(count))
    }
}

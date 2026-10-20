import XCTest

/// Exercises the account-free interaction, not handwriting accuracy or live source support.
final class DemoAssistanceTests: XCTestCase {
    @MainActor
    func testFictionalResearchInsertEditAndReopen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--offline-demo"]
        app.launch()
        app.buttons["Open notebook"].tap()
        app.buttons["newNote"].tap()
        app.buttons["Ask Scout"].tap()
        XCTAssertTrue(app.staticTexts["Fictional offline demo"].waitForExistence(timeout: 5))

        let question = app.descendants(matching: .any).matching(identifier: "scoutQuestion").firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        question.tap()
        question.typeText("Find documentation about a retention policy.")
        app.buttons["askScout"].tap()
        let publicQuestion = app.descendants(matching: .any).matching(identifier: "publicResearchQuestion").firstMatch
        reveal(publicQuestion, in: app)
        XCTAssertTrue(publicQuestion.waitForExistence(timeout: 5))
        publicQuestion.tap()
        publicQuestion.typeText("What is a retention policy?")
        let research = app.buttons["researchPublicQuestion"]
        reveal(research, in: app)
        research.tap()
        let insert = app.buttons["insertAIBlock"]
        reveal(insert, in: app)
        XCTAssertTrue(insert.waitForExistence(timeout: 5))
        XCTAssertTrue(insert.isEnabled)
        insert.tap()

        let edit = app.buttons["editAIBlock"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        app.buttons["Undo ink"].tap()
        XCTAssertFalse(edit.exists, "One undo must remove the accepted block")
        app.buttons["Page options"].tap()
        app.buttons["Redo ink"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        app.buttons["Select"].tap()
        let originalFrame = edit.frame
        let grab = edit.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 1))
            .withOffset(CGVector(dx: -100, dy: 40))
        grab.press(forDuration: 0.1,
                   thenDragTo: grab.withOffset(CGVector(dx: 70, dy: 60)),
                   withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertEqual(edit.frame.minX, originalFrame.minX + 70, accuracy: 4)
        XCTAssertEqual(edit.frame.minY, originalFrame.minY + 60, accuracy: 4)
        app.buttons["Undo ink"].tap()
        XCTAssertEqual(edit.frame.minX, originalFrame.minX, accuracy: 4)
        XCTAssertEqual(edit.frame.minY, originalFrame.minY, accuracy: 4)
        app.buttons["Page options"].tap()
        app.buttons["Redo ink"].tap()
        XCTAssertEqual(edit.frame.minX, originalFrame.minX + 70, accuracy: 4)
        XCTAssertEqual(edit.frame.minY, originalFrame.minY + 60, accuracy: 4)
        app.buttons["Pen"].tap()
        let inserted = XCTAttachment(screenshot: app.screenshot())
        inserted.name = "Fictional research inserted as a separate AI block"
        inserted.lifetime = .keepAlways
        add(inserted)
        edit.tap()
        let body = app.textViews["aiBlockText"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        body.typeText(" Reviewed for the fictional demo.")
        app.buttons["Save"].tap()
        // Termination after the save indicator confirms persistence rather than relying on a delay.
        app.buttons["Page options"].tap()
        XCTAssertTrue(app.buttons["Saved on this iPad"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["editAIBlock"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["editAIBlock"].firstMatch.tap()
        XCTAssertTrue(app.textViews["aiBlockText"].waitForExistence(timeout: 5))
        XCTAssertTrue((app.textViews["aiBlockText"].value as? String ?? "").contains("Reviewed for the fictional demo."))
        XCTAssertTrue(app.staticTexts["Original evidence"].exists)
    }

    @MainActor
    func testDatedRecallOpensRegionAndReturnsToOriginalEditor() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Open notebook"].tap()
        app.buttons["newNote"].tap()
        let originalTitle = app.textFields["noteTitle"].value as? String
        app.buttons["Page options"].tap()
        app.buttons["Recall dated meetings"].tap()
        let source = app.buttons["openRecallSource"].firstMatch
        reveal(source, in: app)
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        source.tap()
        XCTAssertTrue(app.buttons["Return to Recall"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Show source region"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Dated fictional meeting with cited region highlighted"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Return to Recall"].tap()
        XCTAssertTrue(app.navigationBars["Ask Scout"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertEqual(app.textFields["noteTitle"].value as? String, originalTitle)
        XCTAssertTrue(app.buttons["Ask Scout"].exists)
    }

    @MainActor
    func testCanvasResponseCardWithLargeTextAndDarkMode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--offline-demo", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"]
        app.launch()
        app.buttons["Open notebook"].tap()
        app.buttons["newNote"].tap()
        app.buttons["Ask Scout"].tap()
        let question = app.descendants(matching: .any).matching(identifier: "scoutQuestion").firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        question.tap()
        question.typeText("Explain a database index.")
        let route = app.buttons["askScout"]
        reveal(route, in: app)
        route.tap()
        let answer = app.buttons["Write a quick answer"]
        reveal(answer, in: app)
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        answer.tap()
        app.buttons["Done"].tap()
        let card = app.descendants(matching: .any).matching(identifier: "scoutResponseCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let portrait = XCTAttachment(screenshot: app.screenshot())
        portrait.name = "Scout canvas response · large text dark portrait"
        portrait.lifetime = .keepAlways
        add(portrait)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["assistancePin"].isHittable)
        let landscape = XCTAttachment(screenshot: app.screenshot())
        landscape.name = "Scout canvas response · large text dark landscape"
        landscape.lifetime = .keepAlways
        add(landscape)
        app.buttons["Dismiss Scout response"].tap()
        XCTAssertFalse(card.exists)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }
}

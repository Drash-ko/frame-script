import XCTest

@MainActor
final class ModeSwitcherHitAreaUITests: XCTestCase {
    // Adaptive metrics restored from pre-Phase-1 commit 4b19b9b5a4983e7307c2d21ede7aa262447d802c.
    private let expectedButtonWidthRange: ClosedRange<CGFloat> = 92...112
    private let expectedSwitcherWidthRange: ClosedRange<CGFloat> = 286...346
    private let expectedButtonHeight: CGFloat = 28
    private let expectedSwitcherHeight: CGFloat = 34
    private let tolerance: CGFloat = 0.5

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testEnglishHitAreasAndMetrics() throws {
        try verifyHitAreasAndMetrics(languageArgument: "--framescript-ui-test-language-english")
    }

    func testRussianHitAreasAndMetrics() throws {
        try verifyHitAreasAndMetrics(languageArgument: "--framescript-ui-test-language-russian")
    }

    private func verifyHitAreasAndMetrics(languageArgument: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--framescript-ui-test-open-demo", languageArgument]
        app.launch()

        let identifiers = ["mode-switcher-script", "mode-switcher-broll", "mode-switcher-editing"]
        let controls = identifiers.map { modeControl($0, in: app) }
        XCTAssertTrue(controls[0].waitForExistence(timeout: 5))
        controls.forEach { control in
            XCTAssertGreaterThanOrEqual(control.frame.width, expectedButtonWidthRange.lowerBound - tolerance)
            XCTAssertLessThanOrEqual(control.frame.width, expectedButtonWidthRange.upperBound + tolerance)
            XCTAssertEqual(control.frame.height, expectedButtonHeight, accuracy: tolerance)
        }

        let switcher = app.descendants(matching: .any)["mode-switcher"]
        XCTAssertTrue(switcher.exists)
        XCTAssertGreaterThanOrEqual(switcher.frame.width, expectedSwitcherWidthRange.lowerBound - tolerance)
        XCTAssertLessThanOrEqual(switcher.frame.width, expectedSwitcherWidthRange.upperBound + tolerance)
        XCTAssertEqual(switcher.frame.height, expectedSwitcherHeight, accuracy: tolerance)

        let insidePoints = [
            CGVector(dx: 0.05, dy: 0.5),  // empty left area
            CGVector(dx: 0.35, dy: 0.5),  // label text
            CGVector(dx: 0.72, dy: 0.5),  // shortcut keycap
            CGVector(dx: 0.95, dy: 0.5),  // empty right area
            CGVector(dx: 0.5, dy: 0.05),  // top edge
            CGVector(dx: 0.5, dy: 0.95),  // bottom edge
        ]

        for (index, identifier) in identifiers.enumerated() {
            let alternate = identifiers[(index + 1) % identifiers.count]
            for point in insidePoints {
                modeControl(alternate, in: app).click()
                controls[index].coordinate(withNormalizedOffset: point).click()
                assertSelected(identifier, in: app)
            }

            modeControl(alternate, in: app).click()
            controls[index]
                .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -0.15))
                .click()
            assertSelected(alternate, in: app)
        }
    }

    private func modeControl(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func assertSelected(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let element = modeControl(identifier, in: app)
        let predicate = NSPredicate(format: "selected == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: 2)
        XCTAssertEqual(result, .completed, element.debugDescription, file: file, line: line)
    }
}

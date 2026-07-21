import XCTest

final class TodoPilotUITests: XCTestCase {
    func testAppLaunchesToTodayList() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add"].exists)
    }

    func testDiagnosticsViewIsReachableFromSidebar() {
        let app = XCUIApplication()
        app.launch()

        app.staticTexts["Diagnostics"].click()

        XCTAssertTrue(app.staticTexts["Privacy-safe internal status"].waitForExistence(timeout: 5))
    }
}

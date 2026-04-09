import XCTest

final class RootViewUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_rootViewIsDisplayedOnLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        let root = app.otherElements["root-view"]
        XCTAssertTrue(root.waitForExistence(timeout: 5))
    }
}

import XCTest

/// UI / E2E test for the SwiftChat client apps.
///
/// This is an XCUITest and must run against a built app bundle. In the
/// `SwiftChat.xcodeproj` this file belongs to a "SwiftChatUITests" UI-testing
/// bundle whose target is the iOS (or macOS) app. It cannot run from plain
/// `swift test` because SwiftPM has no app host to launch.
///
/// Flow covered:
///   1. Launch the app.
///   2. Type a message into the composer and send it.
///   3. Assert the outbound bubble appears in the timeline.
///   4. Edit the message and assert the "(Edited)" label appears.
///   5. Delete the message and assert the "This message was deleted" bubble.
final class ChatFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSendEditDeleteMessageFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting"]
        app.launch()

        // 1 & 2: Type and send.
        let composer = app.textFields["Message"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        composer.typeText("Hello E2E")
        app.buttons["arrow.up.circle.fill"].tap()

        // 3: Bubble appears.
        let bubble = app.staticTexts["Hello E2E"]
        XCTAssertTrue(bubble.waitForExistence(timeout: 5))

        // 4: Edit -> "(Edited)".
        bubble.press(forDuration: 1.0)
        app.buttons["Edit"].tap()
        let editField = app.textFields["Message"].firstMatch
        editField.tap()
        editField.typeText(" edited")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["(Edited)"].waitForExistence(timeout: 5))

        // 5: Delete -> tombstone bubble.
        app.staticTexts["Hello E2E edited"].press(forDuration: 1.0)
        app.buttons["Delete"].tap()
        XCTAssertTrue(
            app.staticTexts["This message was deleted"].waitForExistence(timeout: 5)
        )
    }
}

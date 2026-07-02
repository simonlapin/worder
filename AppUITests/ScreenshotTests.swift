import XCTest

/// Marketing screenshot capture for App Store Connect. Not part of the
/// regular test scheme — run via the WorderScreenshots scheme.
final class ScreenshotTests: XCTestCase {
    @MainActor
    func testCaptureScreenshots() throws {
        let app = XCUIApplication()
        app.launch()

        let study = app.buttons["Заниматься"]
        XCTAssertTrue(study.waitForExistence(timeout: 30), "home did not appear")
        sleep(2)
        snap(name: "01-home")

        study.tap()
        let intro = app.buttons["Понятно"]
        XCTAssertTrue(intro.waitForExistence(timeout: 10), "intro card did not appear")
        sleep(1)
        snap(name: "02-intro")

        // Intros come in batches; tap through until an exercise shows up.
        var taps = 0
        while app.buttons["Понятно"].exists && taps < 6 {
            app.buttons["Понятно"].tap()
            taps += 1
            sleep(1)
        }
        sleep(1)
        snap(name: "03-exercise")

        let finish = app.buttons["Завершить"]
        if finish.waitForExistence(timeout: 5) {
            finish.tap()
        }
        let done = app.buttons["Готово"]
        if done.waitForExistence(timeout: 5) {
            done.tap()
        }

        let stats = app.buttons["Статистика"]
        XCTAssertTrue(stats.waitForExistence(timeout: 10), "home did not come back")
        stats.tap()
        sleep(2)
        snap(name: "04-stats")

        let words = app.buttons["Все слова"].firstMatch
        if words.waitForExistence(timeout: 5) {
            words.tap()
            sleep(2)
            snap(name: "05-words")
        }
    }

    @MainActor
    private func snap(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

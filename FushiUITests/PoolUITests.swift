import AppKit
import XCTest

/// Every UI test uses in-memory demo data and a named pasteboard, never the user's history.
@MainActor
final class PoolUITests: XCTestCase {
  private let app = XCUIApplication()
  private var search: XCUIElement { app.textFields["pool-search"] }
  private var firstItem: XCUIElement { app.descendants(matching: .any).matching(identifier: "pool-recent-0").firstMatch }
  private var preview: XCUIElement { app.descendants(matching: .any).matching(identifier: "pool-preview").firstMatch }

  override func setUpWithError() throws {
    continueAfterFailure = false
    app.launchArguments = ["--pool-demo"]
    app.launch()
    XCTAssertTrue(search.waitForExistence(timeout: 10))
    XCTAssertTrue(firstItem.waitForExistence(timeout: 10))
  }

  override func tearDownWithError() throws { app.terminate() }

  func testPoolRendersAndPaginates() {
    let next = app.buttons["pool-page-next"]
    XCTAssertTrue(next.isEnabled)
    next.click()
    XCTAssertTrue(app.buttons["pool-page-previous"].isEnabled)
    let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    shot.name = "浮拾-原生分页"; shot.lifetime = .keepAlways; add(shot)
    app.buttons["pool-page-previous"].click()
    XCTAssertTrue(firstItem.exists)
  }

  func testSearchAndNoResults() {
    search.click(); search.typeText("npm")
    XCTAssertTrue(app.staticTexts["npm run dev"].waitForExistence(timeout: 5))
    search.typeKey("a", modifierFlags: .command)
    search.typeText("no-such-clip-987654")
    XCTAssertTrue(app.staticTexts["没有找到这一条"].waitForExistence(timeout: 5))
    search.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(firstItem.waitForExistence(timeout: 5))
  }

  func testSpacePreviewAndClose() {
    search.click(); search.typeKey(" ", modifierFlags: [])
    XCTAssertTrue(preview.waitForExistence(timeout: 5))
    app.buttons["pool-preview-close"].click()
    XCTAssertTrue(preview.waitForNonExistence(timeout: 3))
    XCTAssertTrue(firstItem.exists)
  }

  func testCopyUsesOnlyDemoPasteboard() {
    let board = NSPasteboard(name: .init("dev.carey.shiguangpool.demo"))
    firstItem.click()
    let predicate = NSPredicate { _, _ in board.string(forType: .string) == "下次见面，带上相机。" }
    expectation(for: predicate, evaluatedWith: nil)
    waitForExpectations(timeout: 5)
  }

  func testContextPinAndUnpin() {
    firstItem.rightClick()
    app.menuItems["放入常用"].click()
    let pinned = app.descendants(matching: .any).matching(NSPredicate(
      format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "pool-favorite-", "下次见面"
    )).firstMatch
    XCTAssertTrue(pinned.waitForExistence(timeout: 5))
    pinned.rightClick()
    XCTAssertTrue(app.menuItems["移出常用"].waitForExistence(timeout: 3))
    app.menuItems["移出常用"].click()
    XCTAssertTrue(firstItem.waitForExistence(timeout: 5))
  }

  func testCommandDeleteInSearchDoesNotDeleteHistory() {
    search.click(); search.typeText("npm")
    XCTAssertTrue(app.staticTexts["npm run dev"].waitForExistence(timeout: 5))
    search.typeKey(.delete, modifierFlags: .command)
    search.typeKey(.escape, modifierFlags: [])
    search.click(); search.typeText("npm")
    XCTAssertTrue(app.staticTexts["npm run dev"].waitForExistence(timeout: 5))
  }
}

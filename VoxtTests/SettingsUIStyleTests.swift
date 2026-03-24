import XCTest
@testable import Voxt

final class SettingsUIStyleTests: XCTestCase {
    func testResolvedSelectWidthShrinksConfiguredWidth() {
        XCTAssertEqual(SettingsUIStyle.resolvedSelectWidth(220), 204)
        XCTAssertEqual(SettingsUIStyle.resolvedSelectWidth(160), 144)
    }

    func testResolvedSelectWidthHasMinimumFloor() {
        XCTAssertEqual(SettingsUIStyle.resolvedSelectWidth(120), 120)
        XCTAssertEqual(SettingsUIStyle.resolvedSelectWidth(80), 120)
        XCTAssertEqual(SettingsUIStyle.resolvedSelectWidth(0), 120)
    }
}

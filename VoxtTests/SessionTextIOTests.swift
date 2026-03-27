import XCTest
@testable import Voxt

@MainActor
final class SessionTextIOTests: XCTestCase {
    func testRewriteAlwaysPresentsAnswerOverlay() {
        let delegate = AppDelegate()
        delegate.sessionOutputMode = .rewrite

        XCTAssertTrue(delegate.shouldPresentRewriteAnswerOverlay(hasSelectedSourceText: false))
        XCTAssertTrue(delegate.shouldPresentRewriteAnswerOverlay(hasSelectedSourceText: true))
    }

    func testOnlyDirectAnswerRewriteUsesStructuredOutput() {
        let delegate = AppDelegate()
        delegate.sessionOutputMode = .rewrite

        XCTAssertTrue(delegate.shouldUseStructuredRewriteAnswerOutput(hasSelectedSourceText: false))
        XCTAssertFalse(delegate.shouldUseStructuredRewriteAnswerOutput(hasSelectedSourceText: true))
    }

    func testNonRewriteSessionsDoNotPresentRewriteAnswerOverlay() {
        let delegate = AppDelegate()

        delegate.sessionOutputMode = .transcription
        XCTAssertFalse(delegate.shouldPresentRewriteAnswerOverlay(hasSelectedSourceText: false))
        XCTAssertFalse(delegate.shouldUseStructuredRewriteAnswerOutput(hasSelectedSourceText: false))

        delegate.sessionOutputMode = .translation
        XCTAssertFalse(delegate.shouldPresentRewriteAnswerOverlay(hasSelectedSourceText: false))
        XCTAssertFalse(delegate.shouldUseStructuredRewriteAnswerOutput(hasSelectedSourceText: false))
    }
}

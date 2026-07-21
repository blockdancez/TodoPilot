import XCTest
@testable import TodoPilot

final class OCRTaskDraftPrefillTests: XCTestCase {
    func testTitleUsesFirstNonEmptyLineAndKeepsFullTextAsDetail() {
        let reviewedText = "  \n\t重设计结算页。  \n补充异常状态和验收标准"

        let draft = OCRTaskDraftPrefill(reviewedText: reviewedText)

        XCTAssertEqual(draft.title, "重设计结算页。")
        XCTAssertEqual(draft.detail, reviewedText)
    }

    func testTitleCollapsesWhitespaceInsideFirstMeaningfulLine() {
        let draft = OCRTaskDraftPrefill(reviewedText: "  修复   支付\t回调  \n第二行")

        XCTAssertEqual(draft.title, "修复 支付 回调")
    }

    func testTitleIsLimitedToEightyCharactersWithoutSplittingEmoji() {
        let emoji = "👩🏽‍💻"
        let draft = OCRTaskDraftPrefill(reviewedText: String(repeating: emoji, count: 81))

        XCTAssertEqual(draft.title.count, 80)
        XCTAssertEqual(draft.title, String(repeating: emoji, count: 80))
    }

    func testWhitespaceOnlyTextProducesEmptyTitle() {
        let draft = OCRTaskDraftPrefill(reviewedText: " \n\t ")

        XCTAssertEqual(draft.title, "")
        XCTAssertEqual(draft.detail, " \n\t ")
    }
}

import Foundation

struct OCRTaskDraftPrefill: Equatable {
    static let maximumTitleLength = 80

    let title: String
    let detail: String

    init(reviewedText: String) {
        detail = reviewedText
        title = Self.makeTitle(from: reviewedText)
    }

    private static func makeTitle(from text: String) -> String {
        let firstMeaningfulLine = text
            .components(separatedBy: .newlines)
            .lazy
            .map { line in
                line
                    .split(whereSeparator: \Character.isWhitespace)
                    .joined(separator: " ")
            }
            .first { !$0.isEmpty } ?? ""

        return String(firstMeaningfulLine.prefix(maximumTitleLength))
    }
}

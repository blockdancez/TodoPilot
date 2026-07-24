import AppKit

enum TaskSourceTabLayoutPolicy {
    static let minimumWidth: CGFloat = 70
    static let spacing: CGFloat = 14
    private static let horizontalTitlePadding: CGFloat = 16
    private static let titleFont = NSFont.systemFont(ofSize: 14, weight: .bold)

    static func width(for title: String) -> CGFloat {
        let measuredWidth = ceil((title as NSString).size(withAttributes: [.font: titleFont]).width)
        return max(minimumWidth, measuredWidth + horizontalTitlePadding)
    }

    static func requiredWidth(for titles: [String]) -> CGFloat {
        guard !titles.isEmpty else {
            return 0
        }
        return titles.map(width(for:)).reduce(0, +)
            + CGFloat(titles.count - 1) * spacing
    }
}

import Carbon
import SwiftUI

struct ShortcutKeyToken: Hashable {
    let symbol: String?
    let label: String
    let accessibilityLabel: String

    init(symbol: String? = nil, label: String, accessibilityLabel: String? = nil) {
        self.symbol = symbol
        self.label = label
        self.accessibilityLabel = accessibilityLabel ?? label
    }
}

enum ShortcutKeyChordStyle: Equatable {
    case inline
    case prominent
    case settings

    var keyHeight: CGFloat {
        switch self {
        case .inline:
            26
        case .prominent:
            24
        case .settings:
            34
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .inline:
            8
        case .prominent:
            7
        case .settings:
            12
        }
    }

    var spacing: CGFloat {
        switch self {
        case .settings:
            6
        default:
            4
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .inline:
            12
        case .prominent:
            11
        case .settings:
            14
        }
    }

    var foreground: Color {
        switch self {
        case .prominent:
            .white
        default:
            Color(red: 0.13, green: 0.14, blue: 0.16)
        }
    }

    var keyBackground: Color {
        switch self {
        case .prominent:
            .white.opacity(0.18)
        case .inline:
            Color.black.opacity(0.055)
        case .settings:
            Color.black.opacity(0.055)
        }
    }

    var keyStroke: Color {
        switch self {
        case .prominent:
            .white.opacity(0.22)
        case .inline:
            Color.black.opacity(0.08)
        case .settings:
            Color.black.opacity(0.075)
        }
    }
}

struct ShortcutKeyChordView: View {
    let tokens: [ShortcutKeyToken]
    var style: ShortcutKeyChordStyle = .inline

    init(tokens: [ShortcutKeyToken], style: ShortcutKeyChordStyle = .inline) {
        self.tokens = tokens
        self.style = style
    }

    init(_ preset: CaptureHotKeyPreset, style: ShortcutKeyChordStyle = .inline) {
        self.tokens = preset.shortcutTokens
        self.style = style
    }

    init(_ hotKey: CaptureHotKey, style: ShortcutKeyChordStyle = .inline) {
        self.tokens = hotKey.shortcutTokens
        self.style = style
    }

    var body: some View {
        HStack(spacing: style.spacing) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                ShortcutKeycap(token: token, style: style)

                if index < tokens.count - 1 {
                    Text("+")
                        .font(.system(size: style.fontSize, weight: .bold, design: .rounded))
                        .foregroundStyle(style.foreground.opacity(style == .prominent ? 0.70 : 0.55))
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        tokens.map(\.accessibilityLabel).joined(separator: " plus ")
    }
}

private struct ShortcutKeycap: View {
    let token: ShortcutKeyToken
    let style: ShortcutKeyChordStyle

    var body: some View {
        HStack(spacing: 4) {
            if let symbol = token.symbol {
                Text(symbol)
                    .font(.system(size: style.fontSize + 1, weight: .black, design: .rounded))
            }

            Text(token.label)
                .font(.system(size: style.fontSize, weight: .bold, design: .rounded))
        }
        .foregroundStyle(style.foreground.opacity(style == .prominent ? 0.92 : 1))
        .padding(.horizontal, style.horizontalPadding)
        .frame(height: style.keyHeight)
        .background(style.keyBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(style.keyStroke, lineWidth: 1)
        )
    }
}

extension CaptureHotKey {
    var shortcutTokens: [ShortcutKeyToken] {
        var tokens: [ShortcutKeyToken] = []
        if carbonModifiers & UInt32(cmdKey) != 0 {
            tokens.append(.command)
        }
        if carbonModifiers & UInt32(controlKey) != 0 {
            tokens.append(.control)
        }
        if carbonModifiers & UInt32(optionKey) != 0 {
            tokens.append(.option)
        }
        if carbonModifiers & UInt32(shiftKey) != 0 {
            tokens.append(.shift)
        }
        tokens.append(ShortcutKeyToken(label: keyLabel.isEmpty ? "key" : keyLabel))
        return tokens
    }

    var readableShortcutTitle: String {
        shortcutTokens
            .map { token in
                [token.symbol, token.label.capitalized]
                    .compactMap { $0 }
                    .joined(separator: " ")
            }
            .joined(separator: " + ")
    }
}

extension CaptureHotKeyPreset {
    var shortcutTokens: [ShortcutKeyToken] {
        hotKey.shortcutTokens
    }

    var readableShortcutTitle: String {
        hotKey.readableShortcutTitle
    }
}

extension Array where Element == ShortcutKeyToken {
    static let commandT: [ShortcutKeyToken] = [.command, ShortcutKeyToken(label: "T")]
    static let commandOptionM: [ShortcutKeyToken] = [.command, .option, ShortcutKeyToken(label: "M")]
}

private extension ShortcutKeyToken {
    static let command = ShortcutKeyToken(symbol: "⌘", label: "command")
    static let control = ShortcutKeyToken(symbol: "⌃", label: "control")
    static let option = ShortcutKeyToken(symbol: "⌥", label: "option")
    static let shift = ShortcutKeyToken(symbol: "⇧", label: "shift")
    static let space = ShortcutKeyToken(label: "space")
}

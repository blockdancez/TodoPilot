import SwiftUI

struct TodoPilotModalShell<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String?
    var headerSystemImage: String?
    var headerBadge: String?
    var headerBadgeStyle: TodoPilotModalHeaderBadgeStyle
    var sourceLabel: String?
    var sourceText: String?
    var width: CGFloat
    var height: CGFloat?
    var chromePolicy: TodoPilotModalShellChromePolicy
    var showsContentScrollIndicators: Bool
    var allowsContentScrolling: Bool
    var layout: TodoPilotModalShellLayout
    let onClose: () -> Void
    private let content: Content
    private let footer: Footer

    init(
        title: String,
        subtitle: String? = nil,
        headerSystemImage: String? = nil,
        headerBadge: String? = nil,
        headerBadgeStyle: TodoPilotModalHeaderBadgeStyle = .accent,
        sourceLabel: String? = nil,
        sourceText: String? = nil,
        width: CGFloat = 760,
        height: CGFloat? = nil,
        chromePolicy: TodoPilotModalShellChromePolicy = .contentDialog,
        showsContentScrollIndicators: Bool = true,
        allowsContentScrolling: Bool = true,
        layout: TodoPilotModalShellLayout = .standard,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.headerSystemImage = headerSystemImage
        self.headerBadge = headerBadge
        self.headerBadgeStyle = headerBadgeStyle
        self.sourceLabel = sourceLabel
        self.sourceText = sourceText
        self.width = width
        self.height = height
        self.chromePolicy = chromePolicy
        self.showsContentScrollIndicators = showsContentScrollIndicators
        self.allowsContentScrolling = allowsContentScrolling
        self.layout = layout
        self.onClose = onClose
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ZStack {
            Color.clear
            modalSurface
        }
        .padding(layout.outerRenderInset)
        .frame(width: layout.outerFrameLength(for: width))
        .frame(height: height.map { layout.outerFrameLength(for: $0) })
        .presentationBackground(.clear)
    }

    private var modalSurface: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(TodoPilotTheme.rowStroke)
                .frame(height: 1)

            contentArea
            .background(TodoPilotModalTheme.contentBackground)

            Rectangle()
                .fill(TodoPilotTheme.rowStroke)
                .frame(height: 1)

            footer
                .padding(.horizontal, 30)
                .padding(.vertical, layout.footerVerticalPadding)
                .background(TodoPilotModalTheme.footerBackground)
        }
        .frame(width: width)
        .frame(height: height)
        .background(modalShape.fill(TodoPilotModalTheme.surface))
        .clipShape(modalShape)
        .overlay(
            modalShape
                .stroke(TodoPilotModalTheme.floatingHairline.opacity(layout.outerStrokeOpacity), lineWidth: 1)
        )
        .shadow(color: TodoPilotModalTheme.floatingAmbientShadow.opacity(layout.ambientShadowOpacity), radius: layout.ambientShadowRadius, x: 0, y: layout.ambientShadowY)
        .shadow(color: TodoPilotModalTheme.floatingKeyShadow.opacity(layout.keyShadowOpacity), radius: layout.keyShadowRadius, x: 0, y: layout.keyShadowY)
        .compositingGroup()
    }

    private var modalShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
    }

    @ViewBuilder
    private var contentArea: some View {
        if allowsContentScrolling {
            ScrollView(.vertical, showsIndicators: showsContentScrollIndicators) {
                contentStack
            }
        } else {
            contentStack
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        }
    }

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: layout.contentSpacing) {
            if let sourceText = sourceText?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceText.isEmpty {
                TodoPilotSourceExcerpt(label: sourceLabel ?? "", text: sourceText)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, layout.contentHorizontalPadding)
        .padding(.vertical, layout.contentVerticalPadding)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: layout.headerSpacing) {
            headerMark

            VStack(alignment: .leading, spacing: layout.headerTextSpacing) {
                HStack(spacing: 12) {
                    Text(title)
                        .font(.system(size: layout.titleFontSize, weight: .heavy))
                        .foregroundStyle(TodoPilotTheme.primaryText)
                        .lineLimit(1)

                    if let headerBadge = headerBadge?.trimmingCharacters(in: .whitespacesAndNewlines), !headerBadge.isEmpty {
                        Text(headerBadge)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(headerBadgeStyle.foreground)
                            .padding(.horizontal, 11)
                            .frame(height: 28)
                            .background(headerBadgeStyle.background, in: Capsule())
                    }
                }

                if let subtitle = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: layout.subtitleFontSize, weight: .semibold))
                        .foregroundStyle(TodoPilotTheme.secondaryText)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 20)

            if chromePolicy.showsHeaderCloseButton {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: layout.closeIconSize, weight: .bold))
                        .foregroundStyle(TodoPilotTheme.secondaryText)
                        .frame(width: layout.closeButtonSize, height: layout.closeButtonSize)
                        .background(Color.black.opacity(layout.closeButtonBackgroundOpacity), in: Circle())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(0.92)
            }
        }
        .padding(.horizontal, layout.headerHorizontalPadding)
        .padding(.top, layout.headerTopPadding)
        .padding(.bottom, layout.headerBottomPadding)
        .background(TodoPilotModalTheme.surface)
    }

    @ViewBuilder
    private var headerMark: some View {
        if let headerSystemImage {
            Image(systemName: headerSystemImage)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(TodoPilotTheme.accent)
                .frame(width: 30, height: 30)
        } else {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(TodoPilotTheme.accent)
                .frame(width: 5, height: layout.accentRailHeight)
        }
    }
}
struct TodoPilotModalShellChromePolicy: Equatable {
    static let contentDialog = TodoPilotModalShellChromePolicy(showsHeaderCloseButton: false)
    static let closableContentDialog = TodoPilotModalShellChromePolicy(showsHeaderCloseButton: true)

    let showsHeaderCloseButton: Bool
}

enum TodoPilotModalHeaderBadgeStyle: Equatable {
    case accent
    case neutral

    var foreground: Color {
        switch self {
        case .accent:
            return TodoPilotTheme.accent
        case .neutral:
            return TodoPilotTheme.primaryText.opacity(0.78)
        }
    }

    var background: Color {
        switch self {
        case .accent:
            return TodoPilotTheme.accent.opacity(0.09)
        case .neutral:
            return Color.black.opacity(0.065)
        }
    }
}

struct TodoPilotModalShellLayout: Equatable {
    static let standard = TodoPilotModalShellLayout()
    static let designReferenceFloating = TodoPilotModalShellLayout(
        headerTopPadding: 20,
        headerBottomPadding: 18,
        headerHorizontalPadding: 32,
        headerSpacing: 14,
        headerTextSpacing: 4,
        titleFontSize: 22,
        subtitleFontSize: 13,
        accentRailHeight: 36,
        closeButtonSize: 32,
        closeIconSize: 14,
        closeButtonBackgroundOpacity: 0.045,
        contentHorizontalPadding: 32,
        contentVerticalPadding: 22,
        contentSpacing: 18,
        footerVerticalPadding: 18,
        cornerRadius: 22,
        outerRenderInset: 0,
        outerStrokeOpacity: 0.24,
        keyShadowOpacity: 0.020,
        keyShadowRadius: 5,
        keyShadowY: 1,
        ambientShadowOpacity: 0.040,
        ambientShadowRadius: 20,
        ambientShadowY: 8
    )
    static let contentFocusedFloating = TodoPilotModalShellLayout(
        headerTopPadding: 20,
        headerBottomPadding: 18,
        headerHorizontalPadding: 30,
        headerSpacing: 14,
        headerTextSpacing: 5,
        titleFontSize: 23,
        subtitleFontSize: 14,
        accentRailHeight: 38,
        closeButtonSize: 32,
        closeIconSize: 14,
        closeButtonBackgroundOpacity: 0.035,
        contentHorizontalPadding: 30,
        contentVerticalPadding: 22,
        contentSpacing: 20,
        footerVerticalPadding: 18,
        outerRenderInset: 24,
        outerStrokeOpacity: 0.22,
        keyShadowOpacity: 0.018,
        keyShadowRadius: 5,
        keyShadowY: 1,
        ambientShadowOpacity: 0.036,
        ambientShadowRadius: 18,
        ambientShadowY: 7
    )
    var headerTopPadding: CGFloat = 28
    var headerBottomPadding: CGFloat = 24
    var headerHorizontalPadding: CGFloat = 30
    var headerSpacing: CGFloat = 16
    var headerTextSpacing: CGFloat = 7
    var titleFontSize: CGFloat = 25
    var subtitleFontSize: CGFloat = 15
    var accentRailHeight: CGFloat = 44
    var closeButtonSize: CGFloat = 34
    var closeIconSize: CGFloat = 15
    var closeButtonBackgroundOpacity: Double = 0.045
    var contentHorizontalPadding: CGFloat = 30
    var contentVerticalPadding: CGFloat = 26
    var contentSpacing: CGFloat = 24
    var footerVerticalPadding: CGFloat = 20
    var cornerRadius: CGFloat = 24
    var outerRenderInset: CGFloat = 0
    var outerStrokeOpacity: Double = 0.085
    var keyShadowOpacity: Double = 0.13
    var keyShadowRadius: CGFloat = 34
    var keyShadowY: CGFloat = 18
    var ambientShadowOpacity: Double = 0.050
    var ambientShadowRadius: CGFloat = 18
    var ambientShadowY: CGFloat = 8

    func outerFrameLength(for length: CGFloat) -> CGFloat {
        length + outerRenderInset * 2
    }

    func outerFrameSize(for size: CGSize) -> CGSize {
        CGSize(
            width: outerFrameLength(for: size.width),
            height: outerFrameLength(for: size.height)
        )
    }
}

enum TodoPilotModalTheme {
    static let surface = Color.white
    static let contentBackground = Color(red: 0.987, green: 0.990, blue: 0.996)
    static let footerBackground = Color(red: 0.990, green: 0.992, blue: 0.997)
    static let outerStroke = Color.black.opacity(0.085)
    static let floatingHairline = Color(red: 0.56, green: 0.60, blue: 0.68)
    static let floatingAmbientShadow = Color(red: 0.25, green: 0.29, blue: 0.36)
    static let floatingKeyShadow = Color(red: 0.10, green: 0.12, blue: 0.16)
    static let controlBackground = Color(red: 0.955, green: 0.965, blue: 0.982)
    static let controlStroke = Color.black.opacity(0.060)
    static let elevatedStroke = Color.black.opacity(0.070)
}

struct TodoPilotSourceExcerpt: View {
    let label: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.quote")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(TodoPilotTheme.accent)
                .frame(width: 30, height: 30)
                .background(TodoPilotTheme.accent.opacity(0.10), in: Circle())
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TodoPilotTheme.secondaryText.opacity(0.76))
                }

                Text(text)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TodoPilotTheme.secondaryText)
                    .lineLimit(3)
                    .help(text)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TodoPilotModalTheme.controlBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TodoPilotModalTheme.controlStroke, lineWidth: 1)
        )
    }
}

struct TodoPilotModalTextEditor: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 220
    var showsShadow = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)

            TextEditor(text: $text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(TodoPilotTheme.primaryText)
                .scrollContentBackground(.hidden)
                .padding(16)

            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(TodoPilotTheme.secondaryText.opacity(0.62))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 22)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: minHeight)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TodoPilotModalTheme.controlStroke, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(showsShadow ? 0.035 : 0), radius: 16, x: 0, y: 8)
    }
}

struct TodoPilotModalPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        TodoPilotModalPrimaryButtonBody(configuration: configuration, isEnabled: isEnabled)
    }
}

private struct TodoPilotModalPrimaryButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let isEnabled: Bool
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .frame(minHeight: 50)
            .background(
                TodoPilotTheme.accent
                    .opacity(backgroundOpacity),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .shadow(color: TodoPilotTheme.accent.opacity(isEnabled ? (isHovering ? 0.30 : 0.22) : 0), radius: isHovering ? 18 : 14, y: isHovering ? 10 : 8)
            .scaleEffect(configuration.isPressed ? 0.985 : (isEnabled && isHovering ? 1.015 : 1))
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.16), value: isHovering)
            .onHover { isHovering = isEnabled && $0 }
    }

    private var backgroundOpacity: Double {
        guard isEnabled else {
            return 0.42
        }
        if configuration.isPressed {
            return 0.86
        }
        return isHovering ? 0.92 : 1
    }
}

struct TodoPilotModalQuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        TodoPilotModalQuietButtonBody(configuration: configuration, isEnabled: isEnabled)
    }
}

private struct TodoPilotModalQuietButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let isEnabled: Bool
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .frame(minHeight: 44)
            .background(
                (isEnabled && isHovering ? TodoPilotTheme.accent.opacity(0.07) : Color.clear),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.14), value: isHovering)
            .onHover { isHovering = isEnabled && $0 }
    }

    private var foreground: Color {
        guard isEnabled else {
            return TodoPilotTheme.secondaryText.opacity(0.45)
        }
        return isHovering ? TodoPilotTheme.accent : TodoPilotTheme.secondaryText
    }
}

struct TodoPilotModalGhostButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        TodoPilotModalGhostButtonBody(configuration: configuration, isEnabled: isEnabled)
    }
}

private struct TodoPilotModalGhostButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let isEnabled: Bool
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(
                background,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isEnabled && isHovering ? TodoPilotTheme.accent.opacity(0.28) : TodoPilotModalTheme.controlStroke, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : (isEnabled && isHovering ? 1.01 : 1))
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.16), value: isHovering)
            .onHover { isHovering = isEnabled && $0 }
    }

    private var foreground: Color {
        guard isEnabled else {
            return TodoPilotTheme.secondaryText.opacity(0.44)
        }
        return isHovering ? TodoPilotTheme.accent : TodoPilotTheme.secondaryText
    }

    private var background: Color {
        if configuration.isPressed {
            return Color.white.opacity(0.70)
        }
        if isEnabled && isHovering {
            return TodoPilotTheme.accent.opacity(0.08)
        }
        return Color.white.opacity(0.95)
    }
}

struct TodoPilotModalFormCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(TodoPilotModalTheme.elevatedStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.045), radius: 18, x: 0, y: 10)
    }
}

private struct ConfirmationFooterGhostButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let width: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(foreground(configuration: configuration))
            .lineLimit(1)
            .frame(width: width, height: 44)
            .background(background(configuration: configuration), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(TodoPilotModalTheme.controlStroke, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.76 : 1)
    }

    private func foreground(configuration: Configuration) -> Color {
        guard isEnabled else {
            return TodoPilotTheme.secondaryText.opacity(0.44)
        }
        return configuration.isPressed ? TodoPilotTheme.accent : TodoPilotTheme.primaryText.opacity(0.78)
    }

    private func background(configuration: Configuration) -> Color {
        guard isEnabled else {
            return Color.white.opacity(0.58)
        }
        return configuration.isPressed ? TodoPilotTheme.accent.opacity(0.08) : Color.white.opacity(0.92)
    }
}

private struct ConfirmationFooterPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let width: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .frame(width: width, height: 50)
            .background(
                TodoPilotTheme.accent.opacity(backgroundOpacity(configuration: configuration)),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .shadow(color: TodoPilotTheme.accent.opacity(isEnabled ? 0.20 : 0), radius: 13, y: 8)
            .opacity(configuration.isPressed ? 0.90 : 1)
    }

    private func backgroundOpacity(configuration: Configuration) -> Double {
        guard isEnabled else {
            return 0.42
        }
        return configuration.isPressed ? 0.86 : 1
    }
}

private struct CandidateFieldContainer<Content: View>: View {
    var minHeight: CGFloat = 36
    var alignment: Alignment = .center
    private let content: Content

    init(minHeight: CGFloat = 36, alignment: Alignment = .center, @ViewBuilder content: () -> Content) {
        self.minHeight = minHeight
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: alignment)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(TodoPilotModalTheme.controlStroke, lineWidth: 1)
            )
    }
}

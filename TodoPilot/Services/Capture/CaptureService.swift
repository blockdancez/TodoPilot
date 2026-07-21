import AppKit
import CoreGraphics
import Foundation

struct CapturedRegion: Equatable {
    let bounds: CGRect
    let displayID: CGDirectDisplayID
    let image: CGImage?
}

@MainActor
protocol ScreenCaptureService {
    func startSelectionCapture(copy: AppCopy) async throws -> CapturedRegion
}

@MainActor
final class ScreenCaptureCoordinator: ScreenCaptureService {
    func startSelectionCapture(copy: AppCopy) async throws -> CapturedRegion {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw TodoPilotError.permissionRequired("Screen Recording permission is required before TodoPilot can capture the selected region.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            ScreenCaptureSelectionSession(continuation: continuation, copy: copy).start()
        }
    }
}

private extension CGImage {
    func deepCopiedForOCR() -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

@MainActor
private final class ScreenCaptureSelectionSession {
    private static var activeSessions: [ObjectIdentifier: ScreenCaptureSelectionSession] = [:]

    private let continuation: CheckedContinuation<CapturedRegion, Error>
    private let copy: AppCopy
    private var windows: [NSWindow] = []
    private var didComplete = false

    init(continuation: CheckedContinuation<CapturedRegion, Error>, copy: AppCopy) {
        self.continuation = continuation
        self.copy = copy
    }

    func start() {
        Self.activeSessions[ObjectIdentifier(self)] = self

        let displays = CaptureOverlayDisplay.activeDisplays()
        guard !displays.isEmpty else {
            finish(with: .failure(TodoPilotError.permissionRequired("No active screen was found for capture.")))
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let displayFrames = displays.map(\.frame)
        let mainScreenIndex = displays.firstIndex(where: \.isMain)
        let preferredScreenIndex = CaptureOverlayFocusPolicy.preferredScreenIndex(
            screenFrames: displayFrames,
            mouseLocation: mouseLocation,
            mainScreenIndex: mainScreenIndex
        )
        let startupOrder = CaptureOverlayStartupOrderPolicy.orderedIndices(
            displayCount: displays.count,
            preferredScreenIndex: preferredScreenIndex
        )
        guard let primaryIndex = startupOrder.first else {
            finish(with: .failure(TodoPilotError.permissionRequired("No active screen was found for capture.")))
            return
        }

        NSCursor.crosshair.set()
        makeAndShowOverlayWindow(display: displays[primaryIndex], makeKey: true)

        let remainingDisplays = startupOrder.dropFirst().map { displays[$0] }
        guard !remainingDisplays.isEmpty else {
            return
        }
        Task { @MainActor [weak self] in
            self?.showRemainingOverlayWindows(remainingDisplays)
        }
    }

    func complete(display: CaptureOverlayDisplay, localSelection: CGRect) {
        guard localSelection.width >= CaptureOverlayLayout.minimumSelectionSide,
              localSelection.height >= CaptureOverlayLayout.minimumSelectionSide else {
            cancel()
            return
        }

        let placement = CaptureOverlayScreenPlacement(screenFrame: display.frame)
        let globalSelection = placement.globalSelection(from: localSelection)

        hideOverlayBeforeCapture()
        let image = captureImage(display: display, localSelection: localSelection)
        finish(with: .success(CapturedRegion(bounds: globalSelection, displayID: display.id, image: image)))
    }

    func cancel() {
        finish(with: .failure(TodoPilotError.permissionRequired("Capture was cancelled.")))
    }

    private func finish(with result: Result<CapturedRegion, Error>) {
        guard !didComplete else {
            return
        }
        didComplete = true
        NSCursor.arrow.set()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        Self.activeSessions.removeValue(forKey: ObjectIdentifier(self))

        switch result {
        case let .success(region):
            continuation.resume(returning: region)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }

    private func captureImage(display: CaptureOverlayDisplay, localSelection: CGRect) -> CGImage? {
        guard let fullImage = CGDisplayCreateImage(display.id) else {
            return nil
        }

        let placement = CaptureOverlayScreenPlacement(screenFrame: display.frame)
        let cropRect = placement.pixelCropRect(
            from: localSelection,
            imageSize: CGSize(width: fullImage.width, height: fullImage.height)
        )

        return fullImage.cropping(to: cropRect)?.deepCopiedForOCR()
    }

    private func hideOverlayBeforeCapture() {
        windows.forEach { window in
            window.orderOut(nil)
            window.displayIfNeeded()
        }
        NSCursor.arrow.set()
    }

    @discardableResult
    private func makeAndShowOverlayWindow(display: CaptureOverlayDisplay, makeKey: Bool) -> NSWindow? {
        guard !didComplete else {
            return nil
        }

        let overlayView = CaptureOverlayView(display: display, session: self, copy: copy)
        let window = CaptureOverlayWindow.makeOverlayWindow(display: display, contentView: overlayView)
        windows.append(window)
        window.orderFrontRegardless()

        if makeKey {
            window.makeKey()
            window.makeFirstResponder(window.contentView)
        }

        return window
    }

    private func showRemainingOverlayWindows(_ displays: [CaptureOverlayDisplay]) {
        guard !didComplete else {
            return
        }

        displays.forEach { display in
            makeAndShowOverlayWindow(display: display, makeKey: false)
        }
    }
}

private final class CaptureOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    static func makeOverlayWindow(display: CaptureOverlayDisplay, contentView: NSView) -> CaptureOverlayWindow {
        let placement = CaptureOverlayScreenPlacement(screenFrame: display.frame)
        let window = CaptureOverlayWindow(
            contentRect: placement.contentBounds,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: nil
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isFloatingPanel = true
        window.worksWhenModal = true
        window.becomesKeyOnlyIfNeeded = false
        window.level = CaptureOverlayWindowPolicy.level
        window.collectionBehavior = CaptureOverlayWindowPolicy.collectionBehavior
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.isMovable = false
        window.isReleasedWhenClosed = false
        window.contentView = contentView
        contentView.frame = placement.contentBounds
        window.setFrame(placement.screenFrame, display: false)
        return window
    }
}

struct CaptureOverlayDisplay: Equatable, Identifiable {
    let id: CGDirectDisplayID
    let frame: CGRect
    let backingScaleFactor: CGFloat
    let isMain: Bool

    var contentBounds: CGRect {
        CGRect(origin: .zero, size: frame.size)
    }

    static func activeDisplays(
        screens: [NSScreen] = NSScreen.screens,
        mainDisplayID: CGDirectDisplayID = CGMainDisplayID()
    ) -> [CaptureOverlayDisplay] {
        screens.compactMap { screen in
            guard let displayID = screen.displayID else {
                return nil
            }

            return CaptureOverlayDisplay(
                id: displayID,
                frame: screen.frame,
                backingScaleFactor: screen.backingScaleFactor,
                isMain: displayID == mainDisplayID
            )
        }
    }
}

struct CaptureOverlayWindowPolicy: Equatable {
    static var level: NSWindow.Level {
        .screenSaver
    }

    static var collectionBehavior: NSWindow.CollectionBehavior {
        [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
    }
}

struct CaptureOverlayScreenPlacement: Equatable {
    let screenFrame: CGRect

    var contentBounds: CGRect {
        CGRect(origin: .zero, size: screenFrame.size)
    }

    func globalSelection(from localSelection: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.minX + localSelection.minX,
            y: screenFrame.maxY - localSelection.maxY,
            width: localSelection.width,
            height: localSelection.height
        )
    }

    func pixelCropRect(from localSelection: CGRect, imageSize: CGSize) -> CGRect {
        guard screenFrame.width > 0, screenFrame.height > 0 else {
            return .zero
        }

        let scaleX = imageSize.width / screenFrame.width
        let scaleY = imageSize.height / screenFrame.height
        return CGRect(
            x: localSelection.minX * scaleX,
            y: localSelection.minY * scaleY,
            width: localSelection.width * scaleX,
            height: localSelection.height * scaleY
        ).integral
    }
}

struct CaptureOverlayFocusPolicy: Equatable {
    static func preferredScreenIndex(
        screenFrames: [CGRect],
        mouseLocation: CGPoint,
        mainScreenIndex: Int?
    ) -> Int? {
        if let index = screenFrames.firstIndex(where: { $0.contains(mouseLocation) }) {
            return index
        }

        if let mainScreenIndex, screenFrames.indices.contains(mainScreenIndex) {
            return mainScreenIndex
        }

        return screenFrames.indices.first
    }
}

struct CaptureOverlayStartupOrderPolicy: Equatable {
    static func orderedIndices(displayCount: Int, preferredScreenIndex: Int?) -> [Int] {
        let indices = Array(0..<max(0, displayCount))
        guard let preferredScreenIndex,
              indices.contains(preferredScreenIndex) else {
            return indices
        }

        return [preferredScreenIndex] + indices.filter { $0 != preferredScreenIndex }
    }
}

struct CaptureOverlayLayout: Equatable {
    static let minimumSelectionSide: CGFloat = 8

    let bounds: CGRect

    var dimOpacity: CGFloat { 0.34 }
    var selectedDimOpacity: CGFloat { 0.28 }

    var promptCardRect: CGRect {
        let width = min(max(bounds.width * 0.24, 250), min(320, bounds.width - 48))
        let height = min(96, bounds.height - 48)
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        ).integral
    }

    var cancelButtonRect: CGRect {
        let width = min(130, max(104, bounds.width - 32))
        let height: CGFloat = 44
        return CGRect(
            x: bounds.maxX - width - 32,
            y: bounds.maxY - height - 28,
            width: width,
            height: height
        ).integral
    }

    var cancelHelpRect: CGRect {
        let diameter: CGFloat = 42
        return CGRect(
            x: min(bounds.maxX - diameter - 16, cancelButtonRect.maxX - diameter / 2),
            y: min(bounds.maxY - diameter - 8, cancelButtonRect.maxY + 8),
            width: diameter,
            height: diameter
        ).integral
    }
}

private final class CaptureOverlayView: NSView {
    private weak var session: ScreenCaptureSelectionSession?
    private let display: CaptureOverlayDisplay
    private let copy: AppCopy
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var selectionRect: CGRect = .zero

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    init(display: CaptureOverlayDisplay, session: ScreenCaptureSelectionSession, copy: AppCopy) {
        self.display = display
        self.session = session
        self.copy = copy
        super.init(frame: display.contentBounds)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)

        let point = convert(event.locationInWindow, from: nil)
        if cancelButtonRect.contains(point) {
            session?.cancel()
            return
        }

        dragStart = point
        dragCurrent = point
        selectionRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else {
            return
        }
        let current = convert(event.locationInWindow, from: nil)
        dragCurrent = current
        selectionRect = CGRect(
            x: min(dragStart.x, current.x),
            y: min(dragStart.y, current.y),
            width: abs(current.x - dragStart.x),
            height: abs(current.y - dragStart.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if selectionRect.isEmpty, let dragStart {
            let current = convert(event.locationInWindow, from: nil)
            selectionRect = CGRect(
                x: min(dragStart.x, current.x),
                y: min(dragStart.y, current.y),
                width: abs(current.x - dragStart.x),
                height: abs(current.y - dragStart.y)
            )
        }
        session?.complete(display: display, localSelection: selectionRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            session?.cancel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let layout = CaptureOverlayLayout(bounds: bounds)

        guard !selectionRect.isEmpty else {
            NSColor.black.withAlphaComponent(layout.dimOpacity).setFill()
            bounds.fill()
            drawPromptCard(in: layout.promptCardRect)
            drawCancelControl(in: layout.cancelButtonRect)
            drawCancelHelpBubble(in: layout.cancelHelpRect)
            return
        }

        let overlayPath = NSBezierPath(rect: bounds)
        overlayPath.append(NSBezierPath(rect: selectionRect))
        overlayPath.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(layout.selectedDimOpacity).setFill()
        overlayPath.fill()

        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: selectionRect)
        path.lineWidth = 2.5
        path.stroke()

        drawCancelControl(in: layout.cancelButtonRect)
        drawCancelHelpBubble(in: layout.cancelHelpRect)
        drawSizeBadge(for: selectionRect)
        drawLoupe(for: selectionRect)
    }

    private var cancelButtonRect: CGRect {
        CaptureOverlayLayout(bounds: bounds).cancelButtonRect
    }

    private func drawPromptCard(in rect: CGRect) {
        drawElevatedRoundedRect(rect, radius: 14, fill: NSColor.black.withAlphaComponent(0.78))

        let title = copy.dragToSelectScreenArea
        let subtitle = copy.escToCancel
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.62)
        ]

        let attributedTitle = NSAttributedString(string: title, attributes: titleAttributes)
        let attributedSubtitle = NSAttributedString(string: subtitle, attributes: subtitleAttributes)
        let titleSize = attributedTitle.size()
        let subtitleSize = attributedSubtitle.size()
        let spacing: CGFloat = 10
        let contentHeight = titleSize.height + spacing + subtitleSize.height
        let titleRect = CGRect(
            x: rect.midX - titleSize.width / 2,
            y: rect.midY - contentHeight / 2,
            width: titleSize.width,
            height: titleSize.height
        )
        let subtitleRect = CGRect(
            x: rect.midX - subtitleSize.width / 2,
            y: titleRect.maxY + spacing,
            width: subtitleSize.width,
            height: subtitleSize.height
        )

        attributedTitle.draw(in: titleRect)
        attributedSubtitle.draw(in: subtitleRect)
    }

    private func drawCancelControl(in rect: CGRect) {
        drawElevatedRoundedRect(rect, radius: 12, fill: NSColor.black.withAlphaComponent(0.78))

        let text = copy.cancelWithEscape
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        let textRect = CGRect(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        attributedText.draw(in: textRect)
    }

    private func drawCancelHelpBubble(in rect: CGRect) {
        guard rect.minY < bounds.maxY - 4 else {
            return
        }

        NSColor.white.withAlphaComponent(0.94).setFill()
        NSBezierPath(ovalIn: rect).fill()

        let text = "?"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor.black.withAlphaComponent(0.72)
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        attributedText.draw(in: CGRect(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        ))
    }

    private func drawSizeBadge(for rect: CGRect) {
        let scale = window?.backingScaleFactor ?? display.backingScaleFactor
        let text = "\(Int(rect.width * scale)) x \(Int(rect.height * scale))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        let badgeRect = CGRect(
            x: rect.minX,
            y: max(8, rect.minY - textSize.height - 12),
            width: textSize.width + 16,
            height: textSize.height + 8
        )

        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 6, yRadius: 6).fill()
        attributedText.draw(in: badgeRect.insetBy(dx: 8, dy: 4))
    }

    private func drawLoupe(for rect: CGRect) {
        let diameter: CGFloat = 84
        let x = min(max(rect.maxX + 14, 12), bounds.maxX - diameter - 12)
        let y = min(max(rect.minY, 58), bounds.maxY - diameter - 12)
        let loupeRect = CGRect(x: x, y: y, width: diameter, height: diameter)

        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(ovalIn: loupeRect).fill()

        NSColor.systemTeal.setStroke()
        let loupePath = NSBezierPath(ovalIn: loupeRect)
        loupePath.lineWidth = 2
        loupePath.stroke()

        let center = CGPoint(x: loupeRect.midX, y: loupeRect.midY)
        let crosshair = NSBezierPath()
        crosshair.move(to: CGPoint(x: center.x - 22, y: center.y))
        crosshair.line(to: CGPoint(x: center.x + 22, y: center.y))
        crosshair.move(to: CGPoint(x: center.x, y: center.y - 22))
        crosshair.line(to: CGPoint(x: center.x, y: center.y + 22))
        crosshair.lineWidth = 1
        NSColor.white.withAlphaComponent(0.82).setStroke()
        crosshair.stroke()

        let point = dragCurrent ?? CGPoint(x: rect.midX, y: rect.midY)
        let text = "\(Int(point.x)), \(Int(point.y))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        attributedText.draw(in: CGRect(
            x: center.x - textSize.width / 2,
            y: loupeRect.maxY - textSize.height - 12,
            width: textSize.width,
            height: textSize.height
        ))
    }

    private func drawElevatedRoundedRect(_ rect: CGRect, radius: CGFloat, fill: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return
        }

        context.saveGState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = CGSize(width: 0, height: -8)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.26)
        shadow.set()

        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        context.restoreGState()
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        let value = deviceDescription.first { key, _ in
            key.rawValue == "NSScreenNumber"
        }?.value

        if let number = value as? NSNumber {
            return CGDirectDisplayID(number.uint32Value)
        }

        if let integer = value as? Int {
            return CGDirectDisplayID(integer)
        }

        guard let unsigned = value as? UInt32 else {
            return nil
        }
        return CGDirectDisplayID(unsigned)
    }
}

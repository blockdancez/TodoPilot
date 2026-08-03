import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusIslandWindowController: ObservableObject {
    private weak var environment: AppEnvironment?
    private var panel: StatusIslandPanel?
    private var hostingView: StatusIslandHostingView<AnyView>?
    private var cancellables: Set<AnyCancellable> = []
    private var observerTokens: [NSObjectProtocol] = []
    private var dismissMonitor: Any?
    private var isExpanded = false
    private var isExpanding = false
    private var isCollapsing = false
    private var lastMetrics: StatusIslandMetrics?
    private var lastScreen: NSScreen?
    private let hoverPolicy = StatusIslandHoverPolicy.default
    private var hoverCollapseWorkItem: DispatchWorkItem?
    private var expandContentWorkItem: DispatchWorkItem?
    private var collapsePanelShrinkWorkItem: DispatchWorkItem?

    func configure(environment: AppEnvironment) {
        guard self.environment !== environment else {
            updateVisibility()
            return
        }

        self.environment = environment
        cancellables.removeAll()
        observerTokens.forEach(NotificationCenter.default.removeObserver)
        observerTokens.removeAll()

        environment.taskStore.$tasks
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateSoon()
                }
            }
            .store(in: &cancellables)

        environment.settingsStore.$settings
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateSoon()
                }
            }
            .store(in: &cancellables)

        environment.agentRunStore.$runs
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateSoon()
                }
            }
            .store(in: &cancellables)

        observerTokens.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reposition(animated: false)
            }
        })

        updateVisibility()
    }

    deinit {
        observerTokens.forEach(NotificationCenter.default.removeObserver)
        if let dismissMonitor {
            NSEvent.removeMonitor(dismissMonitor)
        }
        hoverCollapseWorkItem?.cancel()
        expandContentWorkItem?.cancel()
        collapsePanelShrinkWorkItem?.cancel()
    }

    private func updateSoon() {
        DispatchQueue.main.async { [weak self] in
            self?.updateVisibility()
        }
    }

    private func updateVisibility(animated: Bool? = nil) {
        guard let environment else {
            dismiss()
            return
        }

        guard environment.settingsStore.settings.statusIslandMode == .centered else {
            dismiss()
            return
        }

        let targetScreen = targetScreen()
        let metrics = StatusIslandMetrics(
            screen: targetScreen,
            isExpanded: isExpanded,
            keepsExpandedPanelFrame: isExpanding || isCollapsing
        )
        let panel = ensurePanel(metrics: metrics)
        let rootView = AnyView(StatusIslandFloatingView(
            taskStore: environment.taskStore,
            isExpanded: isExpanded,
            metrics: metrics,
            onOpenToday: { [weak self, weak environment] in
                self?.setExpanded(false)
                environment?.openMainWindowFromStatusIsland()
            },
            onStartCapture: { [weak self, weak environment] in
                self?.setExpanded(false)
                environment?.requestStartCapturePipeline(source: "status_island")
            },
            onComplete: { [weak environment] taskID in
                environment?.taskStore.complete(taskID)
            },
            onSnooze: { [weak environment] taskID in
                environment?.taskStore.snooze(taskID, minutes: 10)
            }
        ).environmentObject(environment))
        let hostingView = ensureHostingView(rootView: rootView, metrics: metrics)
        hostingView.rootView = rootView
        hostingView.hitTestFrame = metrics.hitTestFrame
        hostingView.hitTestSlop = hoverPolicy.hitTestSlop
        if hostingView.frame.size != metrics.panelSize {
            hostingView.setFrameSize(metrics.panelSize)
            hostingView.frame = CGRect(origin: .zero, size: metrics.panelSize)
        }
        if panel.contentView !== hostingView {
            panel.contentView = hostingView
        }
        lastMetrics = metrics
        lastScreen = targetScreen
        reposition(animated: animated ?? panel.isVisible)
        panel.orderFrontRegardless()
    }

    private func ensurePanel(metrics: StatusIslandMetrics) -> StatusIslandPanel {
        if let panel {
            return panel
        }

        let panel = StatusIslandPanel(
            contentRect: CGRect(origin: .zero, size: metrics.panelSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.isMovable = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovableByWindowBackground = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 14)
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .stationary,
            .ignoresCycle
        ]
        self.panel = panel
        return panel
    }

    private func ensureHostingView(
        rootView: AnyView,
        metrics: StatusIslandMetrics
    ) -> StatusIslandHostingView<AnyView> {
        if let hostingView {
            return hostingView
        }

        let hostingView = StatusIslandHostingView(rootView: rootView)
        hostingView.onHoverStateChanged = { [weak self] isInside in
            Task { @MainActor in
                self?.handleHoverState(isInside: isInside)
            }
        }
        hostingView.hitTestFrame = metrics.hitTestFrame
        hostingView.setFrameSize(metrics.panelSize)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        self.hostingView = hostingView
        return hostingView
    }

    private func setExpanded(_ expanded: Bool) {
        if expanded {
            expandFromCompactIfNeeded()
            return
        }

        collapseToCompactIfNeeded()
    }

    private func expandFromCompactIfNeeded() {
        guard !isExpanding else {
            return
        }
        guard !isExpanded || isCollapsing else {
            return
        }

        hoverCollapseWorkItem?.cancel()
        hoverCollapseWorkItem = nil
        expandContentWorkItem?.cancel()
        expandContentWorkItem = nil
        collapsePanelShrinkWorkItem?.cancel()
        collapsePanelShrinkWorkItem = nil
        isCollapsing = false
        isExpanding = true
        isExpanded = false
        installDismissMonitor()
        updateVisibility(animated: false)
        scheduleExpandContent()
    }

    private func collapseToCompactIfNeeded() {
        guard isExpanded || isExpanding else {
            return
        }

        hoverCollapseWorkItem?.cancel()
        hoverCollapseWorkItem = nil
        expandContentWorkItem?.cancel()
        expandContentWorkItem = nil
        collapsePanelShrinkWorkItem?.cancel()
        collapsePanelShrinkWorkItem = nil
        let shouldKeepExpandedPanelDuringCollapse = isExpanded
        isExpanding = false
        isCollapsing = shouldKeepExpandedPanelDuringCollapse
        isExpanded = false
        removeDismissMonitor()
        updateVisibility()
        if shouldKeepExpandedPanelDuringCollapse {
            scheduleCollapsePanelShrink()
        }
    }

    private func dismiss() {
        isExpanded = false
        isExpanding = false
        isCollapsing = false
        hoverCollapseWorkItem?.cancel()
        hoverCollapseWorkItem = nil
        expandContentWorkItem?.cancel()
        expandContentWorkItem = nil
        collapsePanelShrinkWorkItem?.cancel()
        collapsePanelShrinkWorkItem = nil
        removeDismissMonitor()
        panel?.orderOut(nil)
        panel?.contentView = nil
        hostingView = nil
    }

    private func reposition(animated: Bool) {
        guard let panel else {
            return
        }

        let screen = lastScreen ?? targetScreen()
        let metrics = lastMetrics ?? StatusIslandMetrics(screen: screen, isExpanded: isExpanded)
        let placement = StatusIslandPlacement(screen: screen, metrics: metrics)
        guard panel.frame.integral != placement.frame.integral else {
            return
        }
        if animated {
            panel.animator().setFrame(placement.frame, display: true)
        } else {
            panel.setFrame(placement.frame, display: true)
        }
    }

    private func scheduleExpandContent() {
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.isExpanding, !self.isExpanded else {
                    return
                }
                self.isExpanded = true
                self.isExpanding = false
                self.expandContentWorkItem = nil
                self.updateVisibility(animated: false)
            }
        }
        expandContentWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func scheduleCollapsePanelShrink() {
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, !self.isExpanded, self.isCollapsing else {
                    return
                }
                self.isCollapsing = false
                self.collapsePanelShrinkWorkItem = nil
                self.updateVisibility(animated: false)
            }
        }
        collapsePanelShrinkWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + StatusIslandTransitionTiming.collapsePanelShrinkDelay,
            execute: workItem
        )
    }

    private func installDismissMonitor() {
        guard dismissMonitor == nil else {
            return
        }
        dismissMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.setExpanded(false)
            }
        }
    }

    private func removeDismissMonitor() {
        if let dismissMonitor {
            NSEvent.removeMonitor(dismissMonitor)
            self.dismissMonitor = nil
        }
    }

    private func scheduleHoverCollapseIfNeeded() {
        guard StatusIslandHoverCollapsePolicy.shouldScheduleCollapse(
            hasPendingCollapse: hoverCollapseWorkItem != nil,
            policy: hoverPolicy
        ) else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.hoverCollapseWorkItem = nil
                guard self.isExpanded, !self.isMouseInsideIslandHitTestFrame() else {
                    return
                }
                self.setExpanded(false)
            }
        }
        hoverCollapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverPolicy.collapseDelay, execute: workItem)
    }

    private func handleHoverState(isInside: Bool) {
        if isInside {
            hoverCollapseWorkItem?.cancel()
            hoverCollapseWorkItem = nil
            if hoverPolicy.expandsOnMouseEnter, !isExpanded {
                setExpanded(true)
            }
        } else if isExpanded {
            scheduleHoverCollapseIfNeeded()
        }
    }

    private func isMouseInsideIslandHitTestFrame() -> Bool {
        guard let panel, let hostingView else {
            return false
        }

        let windowPoint = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let localPoint = hostingView.convert(windowPoint, from: nil)
        return hostingView.hitTestFrame
            .insetBy(dx: -hoverPolicy.hitTestSlop, dy: -hoverPolicy.hitTestSlop)
            .contains(localPoint)
    }

    private func targetScreen() -> NSScreen? {
        if let notchedScreen = NSScreen.screens.first(where: {
            StatusIslandScreenGeometry(screen: $0).hasUsableCameraHousing
        }) {
            return notchedScreen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }
}

private final class StatusIslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

private final class StatusIslandHostingView<Content: View>: NSHostingView<Content> {
    var hitTestFrame: CGRect = .zero {
        didSet {
            guard oldValue != hitTestFrame else {
                return
            }
            updateTrackingAreas()
        }
    }
    var hitTestSlop: CGFloat = StatusIslandHoverPolicy.default.hitTestSlop
    var onHoverStateChanged: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard hitTestFrame.insetBy(dx: -hitTestSlop, dy: -hitTestSlop).contains(point) else {
            return nil
        }
        return super.hitTest(point) ?? self
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
            self.hoverTrackingArea = nil
        }

        super.updateTrackingAreas()

        guard !hitTestFrame.isEmpty else {
            return
        }

        let trackingArea = NSTrackingArea(
            rect: hitTestFrame.insetBy(dx: -hitTestSlop, dy: -hitTestSlop),
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverStateChanged?(true)
    }

    override func mouseMoved(with event: NSEvent) {
        onHoverStateChanged?(isPointInsideHitTestFrame(event.locationInWindow))
    }

    override func mouseExited(with event: NSEvent) {
        onHoverStateChanged?(false)
    }

    private func isPointInsideHitTestFrame(_ windowPoint: NSPoint) -> Bool {
        let localPoint = convert(windowPoint, from: nil)
        return hitTestFrame
            .insetBy(dx: -hitTestSlop, dy: -hitTestSlop)
            .contains(localPoint)
    }
}

struct StatusIslandHoverPolicy: Equatable {
    static let `default` = StatusIslandHoverPolicy(
        expandsOnMouseEnter: true,
        collapsesAfterMouseExit: true,
        collapseDelay: 0.32,
        hitTestSlop: 0,
        inputMode: .trackingArea
    )

    let expandsOnMouseEnter: Bool
    let collapsesAfterMouseExit: Bool
    let collapseDelay: TimeInterval
    let hitTestSlop: CGFloat
    let inputMode: StatusIslandHoverInputMode
}

enum StatusIslandHoverInputMode: Equatable {
    case trackingArea
}

struct StatusIslandHoverCollapsePolicy: Equatable {
    static func shouldScheduleCollapse(
        hasPendingCollapse: Bool,
        policy: StatusIslandHoverPolicy
    ) -> Bool {
        policy.collapsesAfterMouseExit && !hasPendingCollapse
    }
}

struct StatusIslandCompactCarouselPolicy: Equatable {
    static let `default` = StatusIslandCompactCarouselPolicy(interval: 3)

    let interval: TimeInterval

    func task(from tasks: [TodoTask], at date: Date) -> TodoTask? {
        guard !tasks.isEmpty, interval > 0 else {
            return tasks.first
        }

        let tick = max(0, Int(floor(date.timeIntervalSinceReferenceDate / interval)))
        return tasks[tick % tasks.count]
    }
}

struct StatusIslandTaskSnapshot {
    let orderedActiveTasks: [TodoTask]
    let runningAgentTasks: [TodoTask]
    private let runsByTaskID: [TodoTask.ID: AgentRun]

    init(activeTasks: [TodoTask], runs: [AgentRun]) {
        let repairedActiveTasks = TodoTaskIdentityRepair.deduplicated(activeTasks)
        let tasksByID = repairedActiveTasks.reduce(into: [TodoTask.ID: TodoTask]()) { result, task in
            result[task.id] = task
        }
        let activeRuns = runs
            .filter { $0.state == .running }
            .sorted { $0.startedAt < $1.startedAt }
        var runningTaskIDs = Set<TodoTask.ID>()
        let runningAgentTasks = activeRuns.compactMap { run -> TodoTask? in
            guard runningTaskIDs.insert(run.taskID).inserted else {
                return nil
            }
            return tasksByID[run.taskID]
        }
        self.runningAgentTasks = runningAgentTasks
        self.orderedActiveTasks = runningAgentTasks
            + repairedActiveTasks.filter { !runningTaskIDs.contains($0.id) }
        self.runsByTaskID = runs.reduce(into: [:]) { result, run in
            if result[run.taskID] == nil {
                result[run.taskID] = run
            }
        }
    }

    var carouselTasks: [TodoTask] {
        runningAgentTasks.isEmpty ? orderedActiveTasks : runningAgentTasks
    }

    func run(for taskID: TodoTask.ID) -> AgentRun? {
        runsByTaskID[taskID]
    }
}

@MainActor
final class StatusIslandTaskSnapshotCache: ObservableObject {
    private var lastTasks: [TodoTask]?
    private var lastRuns: [AgentRun]?
    private var nextTemporalRefresh: Date?
    private var cachedSnapshot: StatusIslandTaskSnapshot?
    private(set) var recomputationCount = 0

    func snapshot(taskStore: TaskStore, runs: [AgentRun], now: Date) -> StatusIslandTaskSnapshot {
        let tasks = taskStore.tasks
        let crossedTemporalBoundary = nextTemporalRefresh.map { now >= $0 } ?? false
        if !crossedTemporalBoundary,
           tasks == lastTasks,
           runs == lastRuns,
           let cachedSnapshot {
            return cachedSnapshot
        }

        let activeTasks = taskStore.activeTasks(asOf: now)
        let snapshot = StatusIslandTaskSnapshot(activeTasks: activeTasks, runs: runs)
        lastTasks = tasks
        lastRuns = runs
        nextTemporalRefresh = activeTasks
            .compactMap(\.dueAt)
            .filter { $0 >= now }
            .min()?
            .addingTimeInterval(0.001)
        cachedSnapshot = snapshot
        recomputationCount += 1
        return snapshot
    }
}

struct StatusIslandHeaderTitlePolicy: Equatable {
    static func showsCarouselTitle(isExpanded: Bool) -> Bool {
        !isExpanded
    }

    static func carouselTitleOpacity(isExpanded: Bool) -> Double {
        showsCarouselTitle(isExpanded: isExpanded) ? 1 : 0
    }

    static func hidesCarouselTitleFromAccessibility(isExpanded: Bool) -> Bool {
        !showsCarouselTitle(isExpanded: isExpanded)
    }
}

struct StatusIslandAgentIconPolicy: Equatable {
    static let expandedTaskIconSize: CGFloat = 16

    static func compactIconSize(isNotchedScreen: Bool) -> CGFloat {
        isNotchedScreen ? 11 : 14
    }

    static func provider(for task: TodoTask, run: AgentRun?) -> AgentProvider? {
        guard task.source == .codeAgent, run?.taskID == task.id else {
            return nil
        }
        return run?.provider
    }
}

struct StatusIslandTransitionTiming: Equatable {
    static let collapsePanelShrinkDelay: TimeInterval = 0.30
}

struct StatusIslandShadowStyle: Equatable {
    let opacity: Double
    let radius: CGFloat
    let y: CGFloat

    static func surface(isExpanded: Bool) -> StatusIslandShadowStyle {
        isExpanded
            ? StatusIslandShadowStyle(opacity: 0.20, radius: 16, y: 8)
            : StatusIslandShadowStyle(opacity: 0, radius: 0, y: 0)
    }
}

struct StatusIslandScreenGeometry: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
    let auxiliaryTopLeftArea: CGRect
    let auxiliaryTopRightArea: CGRect
    let safeAreaTopInset: CGFloat
    let isBuiltInDisplay: Bool

    init(
        frame: CGRect = CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect? = nil,
        auxiliaryTopLeftArea: CGRect = .zero,
        auxiliaryTopRightArea: CGRect = .zero,
        safeAreaTopInset: CGFloat = 0,
        isBuiltInDisplay: Bool = false
    ) {
        self.frame = frame
        self.visibleFrame = visibleFrame ?? frame
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
        self.safeAreaTopInset = safeAreaTopInset
        self.isBuiltInDisplay = isBuiltInDisplay
    }

    init(screen: NSScreen?) {
        guard let screen else {
            self.init()
            return
        }

        self.init(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea ?? .zero,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea ?? .zero,
            safeAreaTopInset: screen.safeAreaInsets.top,
            isBuiltInDisplay: screen.isBuiltInDisplay
        )
    }

    var hasUsableCameraHousing: Bool {
        if notchSize.width > 0 {
            return true
        }
        if !auxiliaryTopLeftArea.isEmpty || !auxiliaryTopRightArea.isEmpty {
            return true
        }

        let menuBarGap = max(0, frame.maxY - visibleFrame.maxY)
        return safeAreaTopInset > menuBarGap + 4
    }

    var cameraHousingHeight: CGFloat {
        let notchSize = notchSize
        if notchSize.height > 0 {
            return notchSize.height
        }

        let menuBarGap = max(0, frame.maxY - visibleFrame.maxY)
        if !auxiliaryTopLeftArea.isEmpty || !auxiliaryTopRightArea.isEmpty {
            let visibleTopHeight = max(auxiliaryTopLeftArea.height, auxiliaryTopRightArea.height)
            return max(34, visibleTopHeight, menuBarGap, safeAreaTopInset)
        }
        if safeAreaTopInset > menuBarGap + 4 {
            return max(34, safeAreaTopInset)
        }
        return 0
    }

    var cameraHousingWidth: CGFloat {
        let notchSize = notchSize
        if notchSize.width > 0 {
            return notchSize.width
        }

        if !auxiliaryTopLeftArea.isEmpty, !auxiliaryTopRightArea.isEmpty {
            let widthFromAreas = frame.width - auxiliaryTopLeftArea.width - auxiliaryTopRightArea.width + 4
            if widthFromAreas > 80 {
                return widthFromAreas
            }
            let gap = auxiliaryTopRightArea.minX - auxiliaryTopLeftArea.maxX
            if gap > 80 {
                return gap
            }
        }
        return 0
    }

    var notchSize: CGSize {
        guard auxiliaryTopLeftArea.width > 0, auxiliaryTopRightArea.width > 0 else {
            return .zero
        }

        let width = frame.width - auxiliaryTopLeftArea.width - auxiliaryTopRightArea.width
        guard width > 80 else {
            return .zero
        }

        let height = max(
            safeAreaTopInset,
            auxiliaryTopLeftArea.height,
            auxiliaryTopRightArea.height,
            frame.maxY - visibleFrame.maxY
        )
        return CGSize(width: width, height: height)
    }
}

struct StatusIslandPlacement {
    private let screenGeometry: StatusIslandScreenGeometry
    private let metrics: StatusIslandMetrics

    init(screen: NSScreen?, metrics: StatusIslandMetrics) {
        self.screenGeometry = StatusIslandScreenGeometry(screen: screen)
        self.metrics = metrics
    }

    init(screenGeometry: StatusIslandScreenGeometry, metrics: StatusIslandMetrics) {
        self.screenGeometry = screenGeometry
        self.metrics = metrics
    }

    var frame: CGRect {
        let screenFrame = screenGeometry.frame
        let topY = screenFrame.maxY
        let size = metrics.panelSize
        let origin = CGPoint(
            x: screenFrame.midX - size.width / 2,
            y: topY - size.height
        )
        return CGRect(origin: origin, size: size)
    }
}

struct StatusIslandMetrics {
    let isNotchedScreen: Bool
    let notchHeight: CGFloat
    let notchWidth: CGFloat
    let panelSize: CGSize
    let islandSize: CGSize
    let compactHeight: CGFloat
    let hitTestFrame: CGRect
    let cornerRadius: CGFloat
    let headerRowHeight: CGFloat
    let horizontalContentInset: CGFloat
    let bottomShadowInset: CGFloat
    let compactWidth: CGFloat
    let expandedWidth: CGFloat
    let sideShadowInset: CGFloat

    init(
        screen: NSScreen?,
        isExpanded: Bool,
        keepsExpandedPanelFrame: Bool = false
    ) {
        self.init(
            screenGeometry: StatusIslandScreenGeometry(screen: screen),
            isExpanded: isExpanded,
            keepsExpandedPanelFrame: keepsExpandedPanelFrame
        )
    }

    init(
        screenGeometry: StatusIslandScreenGeometry,
        isExpanded: Bool,
        keepsExpandedPanelFrame: Bool = false
    ) {
        let screenFrame = screenGeometry.frame
        let hasNotch = screenGeometry.hasUsableCameraHousing
        let detectedHeight = screenGeometry.cameraHousingHeight
        let detectedWidth = screenGeometry.cameraHousingWidth
        isNotchedScreen = hasNotch
        notchHeight = hasNotch ? max(30, min(38, detectedHeight)) : 0
        notchWidth = hasNotch ? max(150, min(236, detectedWidth)) : 0
        compactHeight = hasNotch ? max(32, min(38, notchHeight)) : 42
        headerRowHeight = compactHeight
        horizontalContentInset = hasNotch ? 16 : 18
        bottomShadowInset = hasNotch ? 30 : 26
        sideShadowInset = hasNotch ? 26 : 26
        cornerRadius = hasNotch ? min(18, compactHeight / 2) : 22

        let screenWidthLimit = max(260, screenFrame.width - 96)
        let compactTarget = hasNotch ? max(notchWidth + 118, 270) : 340
        let compactMax = hasNotch ? min(screenWidthLimit, 332) : min(screenWidthLimit, 380)
        compactWidth = min(compactTarget, compactMax) - 4
        let expandedTarget = hasNotch ? max(notchWidth + 310, 500) : 500
        expandedWidth = min(expandedTarget, min(screenWidthLimit, hasNotch ? 560 : 500))
        let expandedHeight: CGFloat = hasNotch ? 304 : 322

        islandSize = isExpanded
            ? CGSize(width: expandedWidth, height: expandedHeight)
            : CGSize(width: compactWidth, height: compactHeight)
        panelSize = isExpanded || keepsExpandedPanelFrame
            ? CGSize(
                width: expandedWidth + sideShadowInset * 2,
                height: expandedHeight + bottomShadowInset
            )
            : islandSize
        hitTestFrame = CGRect(
            x: (panelSize.width - islandSize.width) / 2,
            y: 0,
            width: islandSize.width,
            height: islandSize.height
        )
    }

}

private extension NSScreen {
    var isBuiltInDisplay: Bool {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(screenNumber.uint32Value) != 0
    }
}

private struct StatusIslandFloatingView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject var taskStore: TaskStore
    @StateObject private var taskSnapshotCache = StatusIslandTaskSnapshotCache()
    let isExpanded: Bool
    let metrics: StatusIslandMetrics
    let onOpenToday: () -> Void
    let onStartCapture: () -> Void
    let onComplete: (TodoTask.ID) -> Void
    let onSnooze: (TodoTask.ID) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: StatusIslandCompactCarouselPolicy.default.interval)) { timeline in
            let snapshot = taskSnapshotCache.snapshot(
                taskStore: taskStore,
                runs: environment.agentRunStore.runs,
                now: timeline.date
            )

            ZStack(alignment: .top) {
                StatusIslandSurface(
                    taskSnapshot: snapshot,
                    isExpanded: isExpanded,
                    metrics: metrics,
                    now: timeline.date,
                    onOpenToday: onOpenToday,
                    onStartCapture: onStartCapture,
                    onComplete: onComplete,
                    onSnooze: onSnooze
                )
            }
            .frame(width: metrics.panelSize.width, height: metrics.panelSize.height, alignment: .top)
        }
        .animation(.interactiveSpring(response: 0.30, dampingFraction: 0.88, blendDuration: 0.06), value: isExpanded)
        .accessibilityElement(children: .contain)
    }
}

private struct StatusIslandSurface: View {
    @EnvironmentObject private var environment: AppEnvironment
    let taskSnapshot: StatusIslandTaskSnapshot
    let isExpanded: Bool
    let metrics: StatusIslandMetrics
    let now: Date
    let onOpenToday: () -> Void
    let onStartCapture: () -> Void
    let onComplete: (TodoTask.ID) -> Void
    let onSnooze: (TodoTask.ID) -> Void

    var body: some View {
        let shadowStyle = StatusIslandShadowStyle.surface(isExpanded: isExpanded)

        VStack(spacing: 0) {
            StatusIslandHeaderContent(
                taskSnapshot: taskSnapshot,
                metrics: metrics,
                isExpanded: isExpanded,
                now: now
            )
            .frame(width: metrics.islandSize.width, height: metrics.compactHeight, alignment: .top)

            if isExpanded {
                expandedContent
                    .transition(.asymmetric(
                        insertion: .opacity
                            .combined(with: .scale(scale: 0.975, anchor: .top)),
                        removal: .opacity
                            .combined(with: .scale(scale: 0.99, anchor: .top))
                    ))
            }
        }
        .frame(width: metrics.islandSize.width, height: metrics.islandSize.height, alignment: .top)
        .background(
            NotchFusedIslandShape(radius: metrics.cornerRadius)
                .fill(Color.black.opacity(0.985))
        )
        .clipShape(NotchFusedIslandShape(radius: metrics.cornerRadius))
        .overlay(
            NotchFusedIslandShape(radius: metrics.cornerRadius)
                .stroke(.white.opacity(isExpanded ? 0.09 : 0.12), lineWidth: 1)
        )
        .shadow(
            color: .black.opacity(shadowStyle.opacity),
            radius: shadowStyle.radius,
            y: shadowStyle.y
        )
        .contentShape(NotchFusedIslandShape(radius: metrics.cornerRadius))
        .help(taskSnapshot.orderedActiveTasks.first?.title ?? "TodoPilot")
        .accessibilityLabel(environment.copy.statusIsland)
    }

    private var expandedContent: some View {
        let copy = environment.copy

        return VStack(spacing: 0) {
            HStack {
                Text(copy.todayTodo)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))

                Spacer()

                Button(action: onStartCapture) {
                    Label(copy.frameCapture, systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(red: 0.27, green: 0.50, blue: 1.0))
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)

            VStack(spacing: 0) {
                ForEach(Array(taskSnapshot.orderedActiveTasks.prefix(4))) { task in
                    StatusIslandTaskRow(
                        task: task,
                        run: taskSnapshot.run(for: task.id),
                        now: now,
                        onComplete: { onComplete(task.id) },
                        onSnooze: { onSnooze(task.id) }
                    )
                    .environmentObject(environment)
                }

                if taskSnapshot.orderedActiveTasks.isEmpty {
                    Text(copy.clear)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, minHeight: 118)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 172, alignment: .top)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)

            Button(action: onOpenToday) {
                HStack(spacing: 6) {
                    Text(copy.viewAll)
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
    }

}

private struct StatusIslandHeaderContent: View {
    @EnvironmentObject private var environment: AppEnvironment
    let taskSnapshot: StatusIslandTaskSnapshot
    let metrics: StatusIslandMetrics
    let isExpanded: Bool
    let now: Date

    var body: some View {
        let carouselTask = StatusIslandCompactCarouselPolicy.default.task(from: taskSnapshot.carouselTasks, at: now)
        let activeCount = taskSnapshot.orderedActiveTasks.count
        let overdueCount = taskSnapshot.orderedActiveTasks.lazy.filter { $0.isOverdue(at: now) }.count
        let countBackground = overdueCount > 0 ? Color(red: 1, green: 0.30, blue: 0.31) : Color.white
        let countForeground = overdueCount > 0 ? Color.white : Color.black
        let title = carouselTask?.title ?? "TodoPilot"
        let provider = carouselTask.flatMap { task in
            StatusIslandAgentIconPolicy.provider(
                for: task,
                run: taskSnapshot.run(for: task.id)
            )
        }
        let agentIcon = provider.flatMap { AgentProviderIconResolver.shared.image(for: $0) }
        let titleColor = (carouselTask?.isOverdue(at: now) ?? false)
            ? Color(red: 1, green: 0.42, blue: 0.44)
            : Color.white.opacity(0.94)

        if metrics.isNotchedScreen {
            HStack(spacing: rowSpacing) {
                PixelPlaneMark(animated: true, variant: .statusIsland)
                    .frame(width: iconSize.width, height: iconSize.height)
                    .offset(x: -1, y: 0)

                headerTitleSlot(title, provider: provider, agentIcon: agentIcon, color: titleColor)

                compactCount(
                    activeCount,
                    foreground: countForeground,
                    background: countBackground,
                    fontSize: 11
                )
            }
            .padding(.horizontal, metrics.horizontalContentInset)
            .frame(height: metrics.headerRowHeight)
            .frame(width: metrics.islandSize.width, height: metrics.compactHeight, alignment: .center)
        } else {
            HStack(spacing: rowSpacing) {
                PixelPlaneMark(animated: false, variant: .compact)
                    .frame(width: iconSize.width, height: iconSize.height)
                    .offset(x: -2, y: 1)

                headerTitleSlot(title, provider: provider, agentIcon: agentIcon, color: titleColor)

                if isExpanded {
                    Image(systemName: "chevron.up")
                        .font(.system(size: chevronSize, weight: .bold))
                        .foregroundStyle(.white.opacity(0.64))
                }

                compactCount(
                    activeCount,
                    foreground: countForeground,
                    background: countBackground,
                    fontSize: 12
                )
            }
            .padding(.horizontal, metrics.horizontalContentInset)
            .frame(width: metrics.islandSize.width, height: metrics.compactHeight, alignment: .center)
        }
    }

    private func headerTitleSlot(
        _ title: String,
        provider: AgentProvider?,
        agentIcon: NSImage?,
        color: Color
    ) -> some View {
        compactTitle(title, provider: provider, agentIcon: agentIcon, color: color)
            .opacity(StatusIslandHeaderTitlePolicy.carouselTitleOpacity(isExpanded: isExpanded))
            .accessibilityHidden(StatusIslandHeaderTitlePolicy.hidesCarouselTitleFromAccessibility(isExpanded: isExpanded))
            .animation(.easeInOut(duration: 0.16), value: isExpanded)
    }

    private func compactTitle(
        _ title: String,
        provider: AgentProvider?,
        agentIcon: NSImage?,
        color: Color
    ) -> some View {
        HStack(spacing: 5) {
            if let agentIcon {
                StatusIslandAgentLogo(
                    image: agentIcon,
                    size: StatusIslandAgentIconPolicy.compactIconSize(
                        isNotchedScreen: metrics.isNotchedScreen
                    )
                )
            }

            Text(title)
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .id("\(provider?.rawValue ?? "TASK"):\(title)")
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.18), value: title)
            .accessibilityLabel(title)
    }

    private func compactCount(
        _ count: Int,
        foreground: Color,
        background: Color,
        fontSize: CGFloat
    ) -> some View {
        Text("\(count)")
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(foreground)
            .frame(minWidth: countSize, minHeight: countSize)
            .background(background, in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
    }

    private var iconSize: CGSize {
        if metrics.isNotchedScreen {
            let height = max(20, min(22, metrics.compactHeight - 14))
            return CGSize(width: height * PixelPlaneMarkLayout.assetAspectRatio, height: height)
        }

        return CGSize(width: 40, height: 18)
    }

    private var rowSpacing: CGFloat {
        metrics.isNotchedScreen ? 8 : 12
    }

    private var titleSize: CGFloat {
        metrics.isNotchedScreen ? 12 : 15
    }

    private var countSize: CGFloat {
        metrics.isNotchedScreen ? 22 : 24
    }

    private var chevronSize: CGFloat {
        metrics.isNotchedScreen ? 8 : 10
    }
}

private struct NotchFusedIslandShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(radius, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct StatusIslandTaskRow: View {
    @EnvironmentObject private var environment: AppEnvironment
    let task: TodoTask
    let run: AgentRun?
    let now: Date
    let onComplete: () -> Void
    let onSnooze: () -> Void

    var body: some View {
        let isOverdue = task.isOverdue(at: now)
        let provider = StatusIslandAgentIconPolicy.provider(
            for: task,
            run: run
        )
        let agentIcon = provider.flatMap { AgentProviderIconResolver.shared.image(for: $0) }

        HStack(spacing: 12) {
            Button(action: onComplete) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(isOverdue ? Color(red: 1, green: 0.30, blue: 0.31).opacity(0.72) : .white.opacity(0.32), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(environment.copy.done)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let agentIcon {
                        StatusIslandAgentLogo(
                            image: agentIcon,
                            size: StatusIslandAgentIconPolicy.expandedTaskIconSize
                        )
                    }

                    Text(task.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isOverdue ? Color(red: 1, green: 0.42, blue: 0.44) : .white.opacity(0.82))
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                .accessibilityLabel(task.title)

                if let dueAt = task.dueAt {
                    HStack(spacing: 4) {
                        if isOverdue {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text(environment.copy.overdue)
                        }
                        Text(dueAt, style: .time)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isOverdue ? Color(red: 1, green: 0.42, blue: 0.44) : .white.opacity(0.36))
                }
            }

            Spacer()

            Circle()
                .fill(isOverdue ? Color(red: 1, green: 0.30, blue: 0.31) : priorityColor)
                .frame(width: 7, height: 7)

            Button(action: onSnooze) {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(environment.copy.snooze)
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
    }

    private var priorityColor: Color {
        switch task.priority {
        case .high:
            Color(red: 1, green: 0.30, blue: 0.31)
        case .medium:
            Color(red: 1, green: 0.68, blue: 0.08)
        case .low:
            Color(red: 0.22, green: 0.78, blue: 0.18)
        }
    }
}

private struct StatusIslandAgentLogo: View {
    let image: NSImage
    let size: CGFloat

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

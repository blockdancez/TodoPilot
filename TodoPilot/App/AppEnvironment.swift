import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppEnvironment: ObservableObject {
    let taskStore: TaskStore
    let agentRunStore: AgentRunStore
    let agentReminderQueue: AgentCompletionReminderQueue
    let agentMonitorCoordinator: AgentMonitorCoordinator
    let agentHookInstaller: AgentHookInstaller
    let settingsStore: LocalSettingsStore
    let captureSessionRecorder: CaptureSessionRecording
    let logger: PrivacyLogger
    let telemetry: TelemetryClient
    let captureService: ScreenCaptureService
    let ocrService: OCRService
    let calendarImportService: CalendarImportService
    let reminderScheduler: ReminderScheduler
    let diagnosticsReporter: DiagnosticsReporter
    let dataExporter: TaskDataExporter
    let migrationCoordinator: LocalMigrationCoordinator
    let hotKeyMonitor: GlobalHotKeyMonitor

    @Published private(set) var hotKeyRegistrationError: String?
    @Published private(set) var agentIntegrationSnapshots: [AgentHookInstaller.Provider: AgentIntegrationSnapshot] = [:]
    @Published private(set) var agentIntegrationMessage: String?
    @Published private(set) var agentIntegrationOperation: AgentIntegrationOperation = .idle

    private var didRegisterHotKey = false
    private var mainWindowOpener: (() -> Void)?
    private var dueTaskReminderScheduler: DueTaskReminderScheduler?
    private var recentProductFlightReminderRequests: [TodoTask.ID: Date] = [:]
    private let floatingCapturePipelineController = FloatingCapturePipelineController()
    private var applicationTerminationObserver: NSObjectProtocol?
    private var agentOpenObserver: NSObjectProtocol?
    private var agentDetectionGeneration = 0

    private init(
        taskStore: TaskStore,
        agentRunStore: AgentRunStore,
        agentReminderQueue: AgentCompletionReminderQueue,
        agentMonitorCoordinator: AgentMonitorCoordinator,
        agentHookInstaller: AgentHookInstaller,
        settingsStore: LocalSettingsStore,
        captureSessionRecorder: CaptureSessionRecording,
        logger: PrivacyLogger,
        telemetry: TelemetryClient,
        captureService: ScreenCaptureService,
        ocrService: OCRService,
        calendarImportService: CalendarImportService,
        reminderScheduler: ReminderScheduler,
        diagnosticsReporter: DiagnosticsReporter,
        dataExporter: TaskDataExporter,
        migrationCoordinator: LocalMigrationCoordinator,
        hotKeyMonitor: GlobalHotKeyMonitor
    ) {
        self.taskStore = taskStore
        self.agentRunStore = agentRunStore
        self.agentReminderQueue = agentReminderQueue
        self.agentMonitorCoordinator = agentMonitorCoordinator
        self.agentHookInstaller = agentHookInstaller
        self.settingsStore = settingsStore
        self.captureSessionRecorder = captureSessionRecorder
        self.logger = logger
        self.telemetry = telemetry
        self.captureService = captureService
        self.ocrService = ocrService
        self.calendarImportService = calendarImportService
        self.reminderScheduler = reminderScheduler
        self.diagnosticsReporter = diagnosticsReporter
        self.dataExporter = dataExporter
        self.migrationCoordinator = migrationCoordinator
        self.hotKeyMonitor = hotKeyMonitor
    }

    static func bootstrap() -> AppEnvironment {
        let logger = PrivacyLogger()
        let localStore = CoreDataLocalStore()
        let settingsStore = LocalSettingsStore()
        let agentRunStore = AgentRunStore(persistence: localStore)
        let taskStore = TaskStore(
            seed: TodoTask.previewTasks,
            persistence: localStore,
            agentUserOverrideObserver: { taskID, override in
                _ = agentRunStore.recordUserOverride(taskID: taskID, override: override)
            }
        )
        let reminderScheduler = LocalReminderScheduler(logger: logger)
        let agentReminderQueue = AgentCompletionReminderQueue(
            taskStore: taskStore,
            settingsStore: settingsStore,
            logger: logger,
            schedule: { task, actions, options in
                await reminderScheduler.scheduleReminder(for: task, actions: actions, options: options)
            },
            stateHandler: { runIDs, state in
                for runID in runIDs {
                    _ = agentRunStore.updateReminderState(runID: runID, state: state)
                }
            },
            activateSource: { item in
                AgentApplicationActivator.activate(
                    provider: item.provider,
                    originBundleID: item.originBundleID,
                    originProcessID: item.originProcessID
                )
            }
        )
        let agentMonitorCoordinator = AgentMonitorCoordinator(
            taskStore: taskStore,
            runStore: agentRunStore,
            settingsStore: settingsStore,
            reminderQueue: agentReminderQueue,
            logger: logger
        )
        let migrationCoordinator = LocalMigrationCoordinator()
        _ = try? migrationCoordinator.ensureMigrated()
        let telemetry = LocalTelemetryClient(logger: logger)
        telemetry.track(.appFirstOpen, properties: ["mode": .publicText("offline")])

        let environment = AppEnvironment(
            taskStore: taskStore,
            agentRunStore: agentRunStore,
            agentReminderQueue: agentReminderQueue,
            agentMonitorCoordinator: agentMonitorCoordinator,
            agentHookInstaller: AgentHookInstaller(),
            settingsStore: settingsStore,
            captureSessionRecorder: localStore,
            logger: logger,
            telemetry: telemetry,
            captureService: ScreenCaptureCoordinator(),
            ocrService: VisionOCRService(),
            calendarImportService: CalendarImportService(),
            reminderScheduler: reminderScheduler,
            diagnosticsReporter: DiagnosticsReporter(),
            dataExporter: TaskDataExporter(),
            migrationCoordinator: migrationCoordinator,
            hotKeyMonitor: GlobalHotKeyMonitor()
        )
        environment.registerConfiguredHotKeyIfNeeded()
        if !Self.isRunningUnderXCTest {
            environment.configureAgentLifecycleObservation()
            environment.agentMonitorCoordinator.recoverAfterUnexpectedTermination()
            environment.refreshAgentIntegrationStatus()
            if settingsStore.settings.agentMonitoringEnabled {
                environment.agentMonitorCoordinator.start()
            }
            environment.startDueTaskReminderSchedulerIfNeeded()
        }
        return environment
    }

    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var detectedAgentProviders: [AgentHookInstaller.Provider] {
        AgentHookInstaller.Provider.allCases.filter { provider in
            guard let detection = agentIntegrationSnapshots[provider]?.detection else { return false }
            return detection.executableURL != nil || detection.configurationPresent
        }
    }

    var hasInstalledAgentProvider: Bool {
        AgentHookInstaller.Provider.allCases.contains(where: agentHookInstaller.hasInstalledHook)
    }

    func registerConfiguredHotKeyIfNeeded() {
        guard !didRegisterHotKey else { return }
        let hotKey = settingsStore.settings.captureHotKey.normalizedToPreset
        do {
            try applyCaptureHotKey(hotKey, persist: false)
        } catch {
            hotKeyRegistrationError = copy.shortcutAlreadyInUse(hotKey.readableShortcutTitle)
            logger.error("capture_hotkey_registration_failed")
        }
    }

    func suspendCaptureHotKeyForEditing() {
        hotKeyMonitor.stop()
        didRegisterHotKey = false
        hotKeyRegistrationError = nil
    }

    func restoreCaptureHotKeyAfterEditing() {
        _ = updateCaptureHotKey(settingsStore.settings.captureHotKey)
    }

    @discardableResult
    func updateCaptureHotKey(_ hotKey: CaptureHotKey) -> Bool {
        do {
            try applyCaptureHotKey(hotKey.normalizedToPreset, persist: true)
            return true
        } catch {
            hotKeyRegistrationError = copy.shortcutAlreadyInUse(hotKey.readableShortcutTitle)
            logger.error("capture_hotkey_registration_failed")
            return false
        }
    }

    func updateFlightRemindersEnabled(_ enabled: Bool) {
        objectWillChange.send()
        settingsStore.updateFlightRemindersEnabled(enabled)
        reminderScheduler.muteAllReminders(!enabled)
    }

    func updateFlightReminderSoundEnabled(_ enabled: Bool) {
        objectWillChange.send()
        settingsStore.updateFlightReminderSoundEnabled(enabled)
    }

    func updateFlightReminderFrequency(_ frequency: FlightReminderFrequency) {
        objectWillChange.send()
        settingsStore.updateFlightReminderFrequency(frequency)
    }

    func updateFlightReminderLeadTime(_ leadTime: FlightReminderLeadTime) {
        objectWillChange.send()
        settingsStore.updateFlightReminderLeadTime(leadTime)
    }

    func updateFlightReminderAtDeadlineEnabled(_ enabled: Bool) {
        objectWillChange.send()
        settingsStore.updateFlightReminderAtDeadlineEnabled(enabled)
    }

    func updateConservativeFlightSilenceEnabled(_ enabled: Bool) {
        objectWillChange.send()
        settingsStore.updateConservativeFlightSilenceEnabled(enabled)
    }

    func updateStatusIslandMode(_ mode: StatusIslandMode) {
        objectWillChange.send()
        settingsStore.updateStatusIslandMode(mode)
    }

    func updateDefaultTodaySortMode(_ mode: DefaultTodaySortMode) {
        objectWillChange.send()
        settingsStore.updateDefaultTodaySortMode(mode)
    }

    func updateLanguage(_ language: AppLanguage) {
        objectWillChange.send()
        settingsStore.updateLanguage(language)
    }

    func refreshAgentIntegrationStatus() {
        agentDetectionGeneration += 1
        let generation = agentDetectionGeneration
        if !agentIntegrationOperation.isBusy { agentIntegrationOperation = .detecting }
        Task { [weak self] in
            let detections = await Task.detached(priority: .utility) {
                AgentProviderDetector().detectAll()
            }.value
            guard let self, generation == agentDetectionGeneration else { return }
            var snapshots: [AgentHookInstaller.Provider: AgentIntegrationSnapshot] = [:]
            for detection in detections {
                snapshots[detection.provider] = AgentIntegrationSnapshot(
                    provider: detection.provider,
                    detection: detection,
                    health: resolvedAgentIntegrationHealth(for: detection)
                )
            }
            agentIntegrationSnapshots = snapshots
            if agentIntegrationOperation == .detecting { agentIntegrationOperation = .idle }
        }
    }

    @discardableResult
    func authorizeAgentMonitoring(providers: Set<AgentHookInstaller.Provider>) async -> Bool {
        guard !providers.isEmpty, !agentIntegrationOperation.isBusy else { return false }
        agentIntegrationOperation = .installing(providers)
        let installer = agentHookInstaller
        let result = await Task.detached(priority: .userInitiated) {
            Result { try installer.install(providers: providers) }
        }.value
        agentIntegrationOperation = .idle
        switch result {
        case .success:
            for provider in providers { setAgentProviderSetting(provider, enabled: true) }
            settingsStore.updateAgentMonitoringEnabled(true)
            agentMonitorCoordinator.start()
            agentIntegrationMessage = "installed"
            refreshAgentIntegrationStatus()
            return true
        case let .failure(error):
            agentIntegrationMessage = "install_failed"
            logger.error("agent_hooks_install_failed", metadata: [
                "error_type": .publicText(String(describing: type(of: error)))
            ])
            return false
        }
    }

    func uninstallAgentMonitoring(providers: Set<AgentHookInstaller.Provider>) async {
        guard !providers.isEmpty, !agentIntegrationOperation.isBusy else { return }
        agentIntegrationOperation = .uninstalling(providers)
        let installer = agentHookInstaller
        let result = await Task.detached(priority: .userInitiated) {
            Result { try installer.uninstall(providers: providers) }
        }.value
        agentIntegrationOperation = .idle
        if case .success = result {
            for provider in providers {
                setAgentProviderSetting(provider, enabled: false)
                agentMonitorCoordinator.markProviderDisabled(provider.agentProvider)
            }
            if !hasAnyEnabledAgentProvider {
                settingsStore.updateAgentMonitoringEnabled(false)
                agentMonitorCoordinator.stop(markActiveLost: false)
            }
            agentIntegrationMessage = "uninstalled"
            refreshAgentIntegrationStatus()
        } else {
            agentIntegrationMessage = "uninstall_failed"
        }
    }

    func updateAgentMonitoringEnabled(_ enabled: Bool) {
        guard !enabled || hasInstalledAgentProvider else {
            settingsStore.updateAgentMonitoringEnabled(false)
            agentIntegrationMessage = "authorization_required"
            return
        }
        settingsStore.updateAgentMonitoringEnabled(enabled)
        enabled ? agentMonitorCoordinator.start() : agentMonitorCoordinator.stop(markActiveLost: true)
        refreshAgentIntegrationStatus()
    }

    func updateAgentProviderMonitoring(_ provider: AgentHookInstaller.Provider, enabled: Bool) {
        setAgentProviderSetting(provider, enabled: enabled)
        if enabled, settingsStore.settings.agentMonitoringEnabled {
            agentMonitorCoordinator.start()
        } else if !enabled {
            agentMonitorCoordinator.markProviderDisabled(provider.agentProvider)
        }
        refreshAgentIntegrationStatus()
    }

    func confirmCodexHooksTrusted() {
        settingsStore.updateCodexHooksTrustConfirmed(true)
        refreshAgentIntegrationStatus()
    }

    @discardableResult
    func testAgentBridge() async -> Bool {
        let isListening = agentMonitorCoordinator.isListening
        let endpointConnected = await Task.detached(priority: .utility) {
            AgentBridgeRuntime.endpointHasPrivateOwnership() && AgentBridgeProbe.canConnect()
        }.value
        return isListening && endpointConnected
    }

    func skipAgentOnboarding() {
        settingsStore.updateAgentOnboardingSkipped(true)
    }

    func agentIntegrationHealth(for provider: AgentHookInstaller.Provider) -> AgentIntegrationHealth {
        guard let detection = agentIntegrationSnapshots[provider]?.detection else { return .notInstalled }
        return resolvedAgentIntegrationHealth(for: detection)
    }

    func configureAgentLifecycleObservation() {
        guard applicationTerminationObserver == nil else { return }
        applicationTerminationObserver = NotificationCenter.default.addObserver(
            forName: .applicationTerminationRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.agentMonitorCoordinator.prepareForApplicationTermination()
            }
        }
        agentOpenObserver = NotificationCenter.default.addObserver(
            forName: .requestOpenAgentTasks,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.openMainWindow(posting: .openAgentTasks) }
        }
    }

    func setMainWindowOpener(_ opener: @escaping () -> Void) {
        mainWindowOpener = opener
    }

    func openMainWindowFromStatusIsland() {
        openMainWindow(posting: .openTodayList)
    }

    func requestStartCapturePipeline(source: String) {
        guard settingsStore.settings.captureEnabled else { return }
        floatingCapturePipelineController.start(environment: self, source: source)
    }

    func scheduleNextFlightReminder(reason: String) async {
        guard let task = taskStore.nextAction else { return }
        await scheduleFlightReminder(for: task, reason: reason)
    }

    @discardableResult
    func showDemoFlightReminder() async -> ReminderScheduleOutcome? {
        guard let task = taskStore.nextAction else { return nil }
        return await scheduleFlightReminder(for: task, reason: FlightReminderTriggerPolicy.demoFlight, options: .demo)
    }

    @discardableResult
    func scheduleFlightReminder(
        for task: TodoTask,
        reason: String,
        options: ReminderScheduleOptions = .standard
    ) async -> ReminderScheduleOutcome {
        guard FlightReminderTriggerPolicy.allows(reason: reason) else { return .skipped(.unsupportedTrigger) }
        var resolvedOptions = options
        resolvedOptions.playSound = settingsStore.settings.flightReminderSoundEnabled
        resolvedOptions.frequency = settingsStore.settings.flightReminderFrequency
        if !settingsStore.settings.conservativeFlightSilenceEnabled {
            resolvedOptions.bypassConservativePause = true
        }
        guard settingsStore.settings.flightRemindersEnabled || resolvedOptions.bypassMute else {
            return .skipped(.muted)
        }
        guard reserveProductFlightReminderRequestIfNeeded(for: task, reason: reason, at: Date()) else {
            return .skipped(.rateLimited)
        }
        let outcome = await reminderScheduler.scheduleReminder(
            for: task,
            actions: makeFlightReminderActions(),
            options: resolvedOptions
        )
        if case .shown = outcome {
            telemetry.track(.airplaneReminderShown, properties: ["reason": .publicText(reason)])
        }
        return outcome
    }

    private func applyCaptureHotKey(_ hotKey: CaptureHotKey, persist: Bool) throws {
        try hotKeyMonitor.startCaptureHotKey(hotKey) { [weak self] in
            self?.requestStartCapturePipeline(source: "hotkey")
        }
        if persist { settingsStore.updateCaptureHotKey(hotKey) }
        hotKeyRegistrationError = nil
        didRegisterHotKey = true
    }

    private func openMainWindow(posting notificationName: Notification.Name) {
        NSApp.activate(ignoringOtherApps: true)
        if mainTodoPilotWindows.isEmpty { mainWindowOpener?() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.bringMainWindowForward()
            NotificationCenter.default.post(name: notificationName, object: nil)
        }
    }

    private var mainTodoPilotWindows: [NSWindow] {
        NSApp.windows.filter { !($0 is NSPanel) && ($0.identifier?.rawValue == "TodoPilotMainWindow" || $0.title == "TodoPilot") }
    }

    private func bringMainWindowForward() {
        for window in mainTodoPilotWindows {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func reserveProductFlightReminderRequestIfNeeded(for task: TodoTask, reason: String, at date: Date) -> Bool {
        guard FlightReminderTriggerPolicy.dedupesRecentProductTrigger(reason: reason) else { return true }
        recentProductFlightReminderRequests = recentProductFlightReminderRequests.filter {
            date.timeIntervalSince($0.value) < FlightReminderTriggerPolicy.productTriggerDedupeWindow
        }
        if let recent = recentProductFlightReminderRequests[task.id],
           date.timeIntervalSince(recent) < FlightReminderTriggerPolicy.productTriggerDedupeWindow {
            return false
        }
        recentProductFlightReminderRequests[task.id] = date
        return true
    }

    private func startDueTaskReminderSchedulerIfNeeded() {
        guard dueTaskReminderScheduler == nil else { return }
        let scheduler = DueTaskReminderScheduler(
            taskStore: taskStore,
            settingsStore: settingsStore,
            logger: logger,
            scheduleReminder: { [weak self] task, phase in
                guard let self else { return .skipped(.unsupportedTrigger) }
                var options = ReminderScheduleOptions.standard
                if phase == .deadline { options.bannerStyle = .deadline }
                return await self.scheduleFlightReminder(
                    for: task,
                    reason: FlightReminderTriggerPolicy.dueTaskReminder,
                    options: options
                )
            }
        )
        dueTaskReminderScheduler = scheduler
        scheduler.start()
    }

    private func makeFlightReminderActions() -> FlightReminderActions {
        FlightReminderActions(
            completeTitle: copy.done,
            snoozeTitle: copy.snooze10Minutes,
            complete: { [weak self] taskID in self?.taskStore.complete(taskID) },
            snooze10Minutes: { [weak self] taskID in self?.taskStore.snooze(taskID, minutes: 10) },
            openDetails: { [weak self] _ in self?.openMainWindow(posting: .openTodayList) },
            muteAll: { [weak self] in self?.updateFlightRemindersEnabled(false) },
            dismiss: { _ in }
        )
    }

    private func resolvedAgentIntegrationHealth(for detection: AgentProviderDetector.Detection) -> AgentIntegrationHealth {
        AgentIntegrationHealthResolver.resolve(
            AgentIntegrationHealthResolver.Context(
                provider: detection.provider,
                operation: agentIntegrationOperation,
                configurationStatus: detection.configurationStatus,
                compatibility: detection.compatibility,
                hookInstalled: agentHookInstaller.hasInstalledHook(for: detection.provider),
                executablePresent: detection.executableURL != nil,
                configurationPresent: detection.configurationPresent,
                agentMonitoringEnabled: settingsStore.settings.agentMonitoringEnabled,
                providerMonitoringEnabled: agentProviderSetting(detection.provider),
                listenerIsAvailable: agentMonitorCoordinator.isListening,
                codexHooksTrustConfirmed: settingsStore.settings.codexHooksTrustConfirmed,
                hasVerifiedEvent: settingsStore.isAgentConnectionVerified(detection.provider.agentProvider)
            )
        )
    }

    private func agentProviderSetting(_ provider: AgentHookInstaller.Provider) -> Bool {
        switch provider {
        case .claudeCode: settingsStore.settings.claudeCodeMonitoringEnabled
        case .codex: settingsStore.settings.codexMonitoringEnabled
        case .cursor: settingsStore.settings.cursorMonitoringEnabled
        }
    }

    private func setAgentProviderSetting(_ provider: AgentHookInstaller.Provider, enabled: Bool) {
        switch provider {
        case .claudeCode: settingsStore.updateClaudeCodeMonitoringEnabled(enabled)
        case .codex: settingsStore.updateCodexMonitoringEnabled(enabled)
        case .cursor: settingsStore.updateCursorMonitoringEnabled(enabled)
        }
    }

    private var hasAnyEnabledAgentProvider: Bool {
        AgentHookInstaller.Provider.allCases.contains {
            agentProviderSetting($0) && agentHookInstaller.hasInstalledHook(for: $0)
        }
    }
}

struct CapturePipelineEntryPolicy: Equatable {
    static let floatingReview = CapturePipelineEntryPolicy(
        opensMainWindowBeforeSelection: false,
        presentsReviewAfterOCR: true
    )

    let opensMainWindowBeforeSelection: Bool
    let presentsReviewAfterOCR: Bool
}

struct FloatingCapturePanelChromePolicy: Equatable {
    static let modal = FloatingCapturePanelChromePolicy(
        styleMask: [.borderless, .nonactivatingPanel],
        isOpaque: false,
        hasSystemShadow: false,
        isMovableByWindowBackground: true
    )

    let styleMask: NSWindow.StyleMask
    let isOpaque: Bool
    let hasSystemShadow: Bool
    let isMovableByWindowBackground: Bool

    var exposesSystemWindowControls: Bool {
        styleMask.contains(.titled)
            || styleMask.contains(.closable)
            || styleMask.contains(.miniaturizable)
            || styleMask.contains(.resizable)
    }
}

struct FloatingCapturePanelPresentationPolicy: Equatable {
    static var level: NSWindow.Level {
        NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 20)
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

    static func centeredFrame(size: CGSize, in screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

struct FlightReminderTriggerPolicy: Equatable {
    static let demoFlight = "demo_flight"
    static let dueTaskReminder = "due_task_reminder"
    static let manualTaskCreated = "manual_task_created"
    static let taskEdited = "task_edited"
    static let nextActionChanged = "next_action_changed"
    static let taskConfirmed = "task_confirmed"
    static let productTriggerDedupeWindow: TimeInterval = 2

    private static let allowedReasons: Set<String> = [
        demoFlight,
        dueTaskReminder,
        manualTaskCreated,
        taskEdited,
        nextActionChanged,
        taskConfirmed
    ]

    private static let productTriggeredReasons: Set<String> = [
        manualTaskCreated,
        taskEdited,
        nextActionChanged,
        taskConfirmed
    ]

    static func allows(reason: String) -> Bool {
        allowedReasons.contains(reason)
    }

    static func dedupesRecentProductTrigger(reason: String) -> Bool {
        productTriggeredReasons.contains(reason)
    }
}

private final class FloatingCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private extension NSScreen {
    var todoPilotDisplayID: CGDirectDisplayID? {
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

@MainActor
final class FloatingCapturePipelineController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var isRunning = false

    func start(environment: AppEnvironment, source: String) {
        if isRunning {
            environment.logger.info("capture_pipeline_request_skipped", metadata: [
                "reason": .publicText("already_running"),
                "source": .publicText(source)
            ])
            return
        }

        if let panel, panel.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }

        isRunning = true
        Task {
            await run(environment: environment, source: source)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingPanel = notification.object as? NSPanel, closingPanel === panel else {
            return
        }
        panel = nil
    }

    private func run(environment: AppEnvironment, source: String) async {
        defer {
            isRunning = false
        }

        var capturedDisplayID: CGDirectDisplayID?
        let captureStartedAt = Date()
        let captureSessionID = environment.captureSessionRecorder.startCaptureSession(
            surface: source,
            screenCount: NSScreen.screens.count,
            startedAt: captureStartedAt
        )
        environment.telemetry.track(.captureStarted, properties: [
            "surface": .publicText(source)
        ])

        do {
            let capturedRegion = try await environment.captureService.startSelectionCapture(copy: environment.copy)
            capturedDisplayID = capturedRegion.displayID
            let captureDuration = Int(Date().timeIntervalSince(captureStartedAt) * 1000)
            environment.captureSessionRecorder.completeCaptureSession(
                captureSessionID,
                completedAt: Date(),
                displayID: capturedRegion.displayID,
                bounds: capturedRegion.bounds
            )
            environment.telemetry.track(.captureCompleted, properties: [
                "duration_ms": .numeric(captureDuration),
                "width": .numeric(Int(capturedRegion.bounds.width)),
                "height": .numeric(Int(capturedRegion.bounds.height)),
                "has_image": .boolean(capturedRegion.image != nil)
            ])

            guard let image = capturedRegion.image else {
                throw TodoPilotError.permissionRequired("TodoPilot could not read the selected screen region.")
            }

            showProgressPanel(environment: environment, displayID: capturedRegion.displayID)
            let ocrStartedAt = Date()
            let ocrResult = try await withTodoPilotTimeout(
                seconds: 10,
                message: environment.copy.ocrTimeout
            ) {
                try await environment.ocrService.recognizeText(in: image, language: environment.appLanguage)
            }
            environment.telemetry.track(.ocrCompleted, properties: [
                "duration_ms": .numeric(Int(Date().timeIntervalSince(ocrStartedAt) * 1000)),
                "block_count": .numeric(ocrResult.blocks.count),
                "text_length": .numeric(ocrResult.text.count),
                "has_low_confidence": .boolean(ocrResult.hasLowConfidenceBlocks)
            ])

            let text = ocrResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                showErrorPanel(
                    environment: environment,
                    message: environment.copy.noTextFound,
                    source: source,
                    displayID: capturedRegion.displayID
                )
                return
            }

            showReviewPanel(
                environment: environment,
                displayID: capturedRegion.displayID,
                session: OCRReviewSession(
                    text: text,
                    ocrResult: ocrResult,
                    createdFromManualText: false
                )
            )
        } catch {
            let message = error.localizedDescription
            if message.localizedCaseInsensitiveContains("cancelled") {
                environment.captureSessionRecorder.cancelCaptureSession(captureSessionID, completedAt: Date())
                environment.logger.info("capture_pipeline_cancelled", metadata: [
                    "source": .publicText(source)
                ])
                return
            }

            environment.captureSessionRecorder.failCaptureSession(captureSessionID, completedAt: Date())
            environment.logger.error("capture_pipeline_failed", metadata: [
                "error_type": .publicText(String(describing: type(of: error))),
                "source": .publicText(source)
            ])
            showErrorPanel(
                environment: environment,
                message: message,
                source: source,
                displayID: capturedDisplayID
            )
        }
    }

    private func showProgressPanel(environment: AppEnvironment, displayID: CGDirectDisplayID?) {
        showPanel(
            size: CGSize(width: 320, height: 148),
            displayID: displayID,
            content: FloatingCaptureProgressView(message: environment.copy.reading)
                .environmentObject(environment)
        )
    }

    private func showReviewPanel(
        environment: AppEnvironment,
        displayID: CGDirectDisplayID?,
        session: OCRReviewSession
    ) {
        showPanel(
            size: CGSize(width: 1100, height: 700),
            displayID: displayID,
            content: FloatingCaptureReviewFlowView(
                initialSession: session,
                onClose: { [weak self] in
                    self?.closePanel()
                }
            )
            .environmentObject(environment)
        )
    }

    private func showErrorPanel(
        environment: AppEnvironment,
        message: String,
        source: String,
        displayID: CGDirectDisplayID?
    ) {
        showPanel(
            size: CGSize(width: 460, height: 300),
            displayID: displayID,
            content: FloatingCaptureErrorView(
                message: message,
                canOpenPrivacySettings: message.localizedCaseInsensitiveContains("Screen Recording"),
                onRetry: { [weak self, weak environment] in
                    guard let self, let environment else {
                        return
                    }
                    self.closePanel()
                    self.start(environment: environment, source: "\(source)_retry")
                },
                onClose: { [weak self] in
                    self?.closePanel()
                }
            )
            .environmentObject(environment)
        )
    }

    private func showPanel<Content: View>(
        size: CGSize,
        displayID: CGDirectDisplayID?,
        content: Content
    ) {
        let targetScreen = Self.screen(displayID: displayID)
        let screenFrame = targetScreen?.frame
            ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let frame = FloatingCapturePanelPresentationPolicy.centeredFrame(
            size: size,
            in: screenFrame
        )

        let chrome = FloatingCapturePanelChromePolicy.modal
        let panel = panel ?? FloatingCapturePanel(
            contentRect: frame,
            styleMask: chrome.styleMask,
            backing: .buffered,
            defer: false
        )
        panel.setFrame(frame, display: false)
        panel.styleMask = chrome.styleMask
        panel.title = "TodoPilot"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = chrome.isOpaque
        panel.backgroundColor = .clear
        panel.hasShadow = chrome.hasSystemShadow
        panel.isMovableByWindowBackground = chrome.isMovableByWindowBackground
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.worksWhenModal = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = FloatingCapturePanelPresentationPolicy.level
        panel.collectionBehavior = FloatingCapturePanelPresentationPolicy.collectionBehavior
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        let hostingView = NSHostingView(
            rootView: ZStack {
                content
            }
            .frame(width: size.width, height: size.height)
            .background(Color.clear)
        )
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.isOpaque = false
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.superview?.wantsLayer = true
        panel.contentView?.superview?.layer?.isOpaque = false
        panel.contentView?.superview?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.delegate = self
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private static func screen(displayID: CGDirectDisplayID?) -> NSScreen? {
        if let displayID,
           let screen = NSScreen.screens.first(where: { $0.todoPilotDisplayID == displayID }) {
            return screen
        }

        return NSScreen.main ?? NSScreen.screens.first
    }

    private func closePanel() {
        guard let panel else {
            return
        }
        panel.delegate = nil
        panel.close()
        self.panel = nil
    }
}

private struct FloatingCaptureProgressView: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.regular)
            Text(message)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TodoPilotTheme.primaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

private struct FloatingCaptureErrorView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let message: String
    let canOpenPrivacySettings: Bool
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        let copy = environment.copy

        TodoPilotModalShell(
            title: copy.capture,
            subtitle: copy.captureNeedsAttention,
            width: 460,
            height: 300,
            onClose: onClose
        ) {
            Text(message)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TodoPilotTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } footer: {
            HStack(spacing: 12) {
                if canOpenPrivacySettings {
                    Button {
                        openScreenRecordingSettings()
                    } label: {
                        Label(copy.openPrivacySettings, systemImage: "gearshape")
                    }
                    .buttonStyle(TodoPilotModalGhostButtonStyle())
                }

                Spacer()

                Button(copy.close, action: onClose)
                    .buttonStyle(TodoPilotModalQuietButtonStyle())
                Button {
                    onRetry()
                } label: {
                    Label(copy.startCapture, systemImage: "viewfinder")
                }
                .buttonStyle(TodoPilotModalPrimaryButtonStyle())
            }
        }
    }

    private func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        environment.telemetry.track(.permissionScreenRecordingPrompted, properties: [
            "source": .publicText("floating_capture_error")
        ])
        NSWorkspace.shared.open(url)
    }
}

private struct FloatingCaptureReviewFlowView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let onClose: () -> Void

    @State private var reviewSession: OCRReviewSession?
    @State private var taskDraft: OCRTaskDraftPrefill?

    init(initialSession: OCRReviewSession, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _reviewSession = State(initialValue: initialSession)
    }

    var body: some View {
        Group {
            if let taskDraft {
                TaskEditorSheet(
                    mode: .create,
                    initialTitle: taskDraft.title,
                    initialDetail: taskDraft.detail,
                    onSave: { editedTask in
                        let task = environment.taskStore.addManualTask(
                            title: editedTask.title,
                            detail: editedTask.detail,
                            priority: editedTask.priority,
                            dueAt: editedTask.dueAt
                        )
                        environment.telemetry.track(.taskCreated, properties: [
                            "source": .publicText("capture_manual")
                        ])
                        Task {
                            await environment.scheduleFlightReminder(
                                for: task,
                                reason: FlightReminderTriggerPolicy.manualTaskCreated
                            )
                        }
                        onClose()
                    }
                )
                .environmentObject(environment)
            } else if let reviewSession {
                OCRReviewSheet(
                    session: reviewSession,
                    presentationContext: .floatingPanel,
                    onUseText: { editedText in
                        taskDraft = OCRTaskDraftPrefill(reviewedText: editedText)
                        self.reviewSession = nil
                    },
                    onCancel: onClose
                )
                .environmentObject(environment)
            }
        }
    }
}

import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settingsStore: LocalSettingsStore
    @State private var selection: Section = .today
    @State private var settingsInitialSection: SettingsPane = .general
    @State private var settingsViewIdentity = UUID()
    @State private var onboardingPresentation: AgentOnboardingPresentation?

    var body: some View {
        HStack(spacing: 0) {
            RootSidebar(selection: $selection)
                .environmentObject(environment)

            Rectangle()
                .fill(RootTheme.divider)
                .frame(width: 1)

            ZStack {
                RootTheme.appBackground
                    .ignoresSafeArea()

                switch selection {
                case .today:
                    TodayListView(
                        taskStore: environment.taskStore,
                        calendarImport: environment.calendarImportService
                    )
                        .environmentObject(environment)
                case .history:
                    HistoryView(taskStore: environment.taskStore)
                        .environmentObject(environment)
                case .settings:
                    SettingsView(initialSection: settingsInitialSection)
                        .id(settingsViewIdentity)
                        .environmentObject(environment)
                case .diagnostics:
                    DiagnosticsView()
                        .environmentObject(environment)
                }
            }
        }
        .frame(minWidth: 980, minHeight: 660)
        .background(RootTheme.appBackground)
        .ignoresSafeArea(.container, edges: .top)
        .onReceive(NotificationCenter.default.publisher(for: .openDiagnostics)) { _ in
            selection = .diagnostics
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTodayList)) { _ in
            selection = .today
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAgentTasks)) { _ in
            selection = .today
        }
        .onReceive(NotificationCenter.default.publisher(for: .startCapturePipeline)) { _ in
            environment.requestStartCapturePipeline(source: "main_window")
        }
        .onReceive(NotificationCenter.default.publisher(for: .muteFlightReminders)) { _ in
            environment.updateFlightRemindersEnabled(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showOnboardingGuide)) { _ in
            if onboardingPresentation == nil {
                onboardingPresentation = .firstLaunch
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .applicationTerminationRequested)) { _ in
            onboardingPresentation = nil
        }
        .onAppear {
            environment.registerConfiguredHotKeyIfNeeded()
            reconcileAutomaticOnboardingPresentation()
        }
        .sheet(item: $onboardingPresentation, onDismiss: {
            reconcileAutomaticOnboardingPresentation()
        }) { _ in
            OnboardingGuideView(
                onFinish: {
                    finishOnboarding()
                },
                onOpenSettings: {
                    finishOnboarding()
                    settingsInitialSection = .general
                    settingsViewIdentity = UUID()
                    selection = .settings
                },
                onOpenAgentSettings: {
                    finishOnboarding()
                    settingsInitialSection = .agents
                    settingsViewIdentity = UUID()
                    selection = .settings
                }
            )
            .environmentObject(environment)
            .environmentObject(settingsStore)
        }
    }

    private func reconcileAutomaticOnboardingPresentation() {
        guard onboardingPresentation == nil, !AppTerminationState.isTerminating else {
            return
        }
        let settings = settingsStore.settings
        onboardingPresentation = AgentOnboardingPresentationPolicy.presentation(
            onboardingCompleted: settings.onboardingCompleted
        )
    }

    private func finishOnboarding() {
        settingsStore.updateOnboardingCompleted(true)
        onboardingPresentation = nil
    }
}

private enum RootTheme {
    static let appBackground = Color(red: 0.97, green: 0.98, blue: 0.98)
    static let sidebarBackground = Color(red: 0.965, green: 0.975, blue: 0.975)
    static let selectedFill = Color.black.opacity(0.085)
    static let hoverFill = Color.black.opacity(0.045)
    static let divider = Color.black.opacity(0.08)
    static let panel = Color.white.opacity(0.92)
    static let panelStroke = Color.black.opacity(0.11)
    static let softStroke = Color.black.opacity(0.065)
    static let primaryText = Color(red: 0.13, green: 0.14, blue: 0.16)
    static let secondaryText = Color(red: 0.48, green: 0.51, blue: 0.56)
    static let mutedText = Color(red: 0.58, green: 0.61, blue: 0.66)
    static let accent = Color(red: 0.18, green: 0.42, blue: 1)
    static let warning = Color(red: 0.84, green: 0.35, blue: 0.04)
    static let success = Color(red: 0.12, green: 0.62, blue: 0.34)
    static let amber = Color(red: 0.85, green: 0.52, blue: 0.07)
    static let destructive = Color(red: 0.95, green: 0.20, blue: 0.20)
}

struct RootSidebarLayout: Equatable {
    static let width: CGFloat = 270
    static let headerLeadingPadding: CGFloat = 32
    static let headerTrailingPadding: CGFloat = 24
    static let sectionHorizontalPadding: CGFloat = 24

    static var headerContentWidth: CGFloat {
        width - headerLeadingPadding - headerTrailingPadding
    }

    static var sectionContentWidth: CGFloat {
        width - sectionHorizontalPadding * 2
    }
}

private struct RootSidebar: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Binding var selection: Section

    var body: some View {
        let copy = environment.copy

        VStack(alignment: .leading, spacing: 32) {
            HStack(spacing: 14) {
                AccountPlaneAvatar(size: 58, planeWidth: 44, showCheck: false)

                VStack(alignment: .leading, spacing: 2) {
                    Text("TodoPilot")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(RootTheme.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 7) {
                        Text(sidebarIdentityText(copy))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(RootTheme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.88)
                            .truncationMode(.tail)

                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: RootSidebarLayout.headerContentWidth, alignment: .leading)
            .padding(.top, 52)
            .padding(.leading, RootSidebarLayout.headerLeadingPadding)
            .padding(.trailing, RootSidebarLayout.headerTrailingPadding)

            VStack(spacing: 8) {
                ForEach(Section.sidebarItems) { item in
                    SidebarItemButton(
                        item: item,
                        title: item.title(copy),
                        isSelected: selection == item
                    ) {
                        guard selection != item else { return }
                        selection = item
                    }
                }
            }
            .frame(width: RootSidebarLayout.sectionContentWidth, alignment: .leading)
            .padding(.horizontal, RootSidebarLayout.sectionHorizontalPadding)

            Spacer()

            LocalModeCard()
                .environmentObject(environment)
                .frame(width: RootSidebarLayout.sectionContentWidth, alignment: .leading)
                .padding(.horizontal, RootSidebarLayout.sectionHorizontalPadding)
                .padding(.bottom, 28)
        }
        .frame(width: RootSidebarLayout.width, alignment: .topLeading)
        .background(RootTheme.sidebarBackground)
    }

    private func sidebarIdentityText(_ copy: AppCopy) -> String {
        copy.taskCaptureTodayFocus
    }
}

private struct LocalModeCard: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        let copy = environment.copy
        VStack(alignment: .leading, spacing: 8) {
            Label(rootText(copy, en: "Local mode", zh: "本地模式"), systemImage: "lock.shield")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(RootTheme.accent)

            Text(rootText(copy, en: "Capture and OCR stay on this Mac", zh: "截图与 OCR 始终留在本机"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(RootTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.93, green: 0.95, blue: 1.0), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(RootTheme.accent.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct SidebarItemButton: View {
    let item: Section
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(RootTheme.primaryText)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(itemBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
    }

    private var itemBackground: Color {
        if isSelected {
            return RootTheme.accent.opacity(0.10)
        }
        if isHovering {
            return RootTheme.hoverFill
        }
        return .clear
    }
}

private enum Section: String, CaseIterable, Identifiable {
    case today
    case history
    case settings
    case diagnostics

    var id: String { rawValue }

    static let sidebarItems: [Section] = [.today, .history, .settings]

    func title(_ copy: AppCopy) -> String {
        switch self {
        case .today:
            copy.todayTodo
        case .history:
            copy.history
        case .settings:
            copy.settings
        case .diagnostics:
            copy.diagnostics
        }
    }

    var systemImage: String {
        switch self {
        case .today:
            "checklist"
        case .history:
            "clock.arrow.circlepath"
        case .settings:
            "gearshape"
        case .diagnostics:
            "stethoscope"
        }
    }
}

private extension OnboardingStep {
    func title(_ copy: AppCopy) -> String {
        switch self {
        case .permission:
            rootText(copy, en: "Screen Recording", zh: "授权屏幕录制")
        case .capture:
            rootText(copy, en: "Capture & confirm", zh: "捕获与确认")
        case .agents:
            rootText(copy, en: "Local Code Agents", zh: "本机 Code Agent")
        case .reminders:
            rootText(copy, en: "Privacy & reminders", zh: "隐私与提醒")
        }
    }

    func systemImage(_ screenRecordingGranted: Bool) -> String {
        switch self {
        case .permission:
            screenRecordingGranted ? "checkmark.shield" : "lock.shield"
        case .capture:
            "viewfinder"
        case .agents:
            "terminal"
        case .reminders:
            "airplane"
        }
    }
}

private struct OnboardingGuideView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settingsStore: LocalSettingsStore
    @Environment(\.scenePhase) private var scenePhase
    let onFinish: () -> Void
    let onOpenSettings: () -> Void
    let onOpenAgentSettings: () -> Void
    @State private var step: OnboardingStep
    @State private var screenRecordingGranted = CGPreflightScreenCaptureAccess()
    @State private var hasOpenedScreenRecordingSettings = false
    @State private var permissionCheckFailed = false

    init(
        onFinish: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenAgentSettings: @escaping () -> Void
    ) {
        self.onFinish = onFinish
        self.onOpenSettings = onOpenSettings
        self.onOpenAgentSettings = onOpenAgentSettings
        _step = State(initialValue: .permission)
    }

    private var availableSteps: [OnboardingStep] {
        AgentOnboardingPresentationPolicy.firstLaunchSteps(
            hasDetectedAgentProviders: !environment.detectedAgentProviders.isEmpty
        )
    }

    private var hasCompletedAgentDetection: Bool {
        environment.agentIntegrationSnapshots.count >= AgentHookInstaller.Provider.allCases.count
    }

    private var agentStepState: AgentOnboardingStepState {
        AgentOnboardingPresentationPolicy.agentStepState(
            monitoringEnabled: settingsStore.settings.agentMonitoringEnabled,
            hasCompletedDetection: hasCompletedAgentDetection,
            hasDetectedProviders: !environment.detectedAgentProviders.isEmpty
        )
    }

    private var privacyContinuation: AgentOnboardingPrivacyContinuation {
        AgentOnboardingPresentationPolicy.privacyContinuation(
            hasCompletedDetection: hasCompletedAgentDetection,
            hasDetectedAgentProviders: !environment.detectedAgentProviders.isEmpty
        )
    }

    private var nextStep: OnboardingStep? {
        guard let index = availableSteps.firstIndex(of: step),
              availableSteps.indices.contains(index + 1) else {
            return nil
        }
        return availableSteps[index + 1]
    }

    private var previousStep: OnboardingStep? {
        guard let index = availableSteps.firstIndex(of: step), index > 0 else {
            return nil
        }
        return availableSteps[index - 1]
    }

    var body: some View {
        let copy = environment.copy

        let chrome = AgentOnboardingPresentationPolicy.chrome(for: step)

        TodoPilotModalShell(
            title: chrome == .agentAuthorization
                ? rootText(copy, en: "Enable Code Agent monitoring", zh: "启用 Code Agent 监控")
                : rootText(copy, en: "Welcome to TodoPilot", zh: "欢迎使用 TodoPilot"),
            subtitle: chrome == .agentAuthorization
                ? rootText(copy, en: "Authorize and install once, then TodoPilot can monitor local Code Agent tasks automatically.", zh: "授权安装后，TodoPilot 会自动监听本机 Code Agent 任务。")
                : rootText(copy, en: "Start with the required macOS permission, then set up the capture-to-today loop.", zh: "先完成 macOS 必需权限，再了解从捕获到今日执行的闭环。"),
            width: 720,
            height: 560,
            onClose: closeGuide
        ) {
            VStack(alignment: .leading, spacing: 12) {
                OnboardingStepIndicator(currentStep: step, steps: availableSteps)
                    .environmentObject(environment)

                HStack(alignment: .top, spacing: 22) {
                    Image(systemName: step.systemImage(screenRecordingGranted))
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(RootTheme.accent)
                        .frame(width: 72, height: 72)
                        .background(RootTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 14) {
                        Text(step.title(copy))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(RootTheme.primaryText)
                            .lineLimit(2)

                        stepContent(copy)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } footer: {
            HStack(spacing: 12) {
                Button(step == .agents
                    ? rootText(copy, en: "Not now", zh: "暂不开启")
                    : rootText(copy, en: "Skip", zh: "跳过")) {
                    if step == .agents {
                        environment.skipAgentOnboarding()
                        advanceOrFinish()
                    } else {
                        onFinish()
                    }
                }
                .buttonStyle(TodoPilotModalQuietButtonStyle())
                .disabled(
                    step == .agents
                        && (environment.agentIntegrationOperation.isInstalling || agentStepState == .detecting)
                )

                Spacer()

                if let previous = previousStep {
                    Button(rootText(copy, en: "Back", zh: "上一步")) {
                        withAnimation(.snappy(duration: 0.18)) {
                            step = previous
                        }
                    }
                    .buttonStyle(TodoPilotModalGhostButtonStyle())
                    .disabled(step == .agents && environment.agentIntegrationOperation.isInstalling)
                }

                if step == .reminders {
                    Button {
                        onOpenSettings()
                    } label: {
                        Label(rootText(copy, en: "Open Settings", zh: "打开设置"), systemImage: "gearshape")
                    }
                    .buttonStyle(TodoPilotModalGhostButtonStyle())
                }

                Button {
                    handlePrimaryAction()
                } label: {
                    if step == .agents && environment.agentIntegrationOperation.isInstalling {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(rootText(copy, en: "Installing…", zh: "正在安装…"))
                        }
                    } else {
                        Label(primaryButtonTitle(copy), systemImage: primaryButtonSystemImage)
                    }
                }
                .buttonStyle(TodoPilotModalPrimaryButtonStyle())
                .disabled(
                    (step == .agents
                        && (environment.agentIntegrationOperation.isInstalling || agentStepState == .detecting))
                        || (step == .reminders && privacyContinuation == .waitForDetection)
                )
            }
        }
        .interactiveDismissDisabled(true)
        .onAppear {
            refreshScreenRecordingStatus()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                refreshScreenRecordingStatus()
            }
        }
    }

    @ViewBuilder
    private func stepContent(_ copy: AppCopy) -> some View {
        switch step {
        case .permission:
            OnboardingBulletList(items: [
                rootText(copy, en: "Screen Recording is required before TodoPilot can frame text on your screen.", zh: "框选屏幕文字前，需要先允许 TodoPilot 使用屏幕录制权限。"),
                rootText(copy, en: "Click Open Privacy Settings, then allow TodoPilot in Privacy & Security > Screen Recording.", zh: "点击打开隐私设置，在“隐私与安全性 > 屏幕录制”里勾选 TodoPilot。"),
                rootText(copy, en: "After granting access, return to TodoPilot. If macOS does not refresh the status, restart the app once.", zh: "授权后回到 TodoPilot；如果状态未刷新，请重启应用让 macOS 生效。")
            ])

            OnboardingPermissionCallout(
                isGranted: screenRecordingGranted,
                didCheckFail: permissionCheckFailed,
                onOpenSettings: {
                    openScreenRecordingSettings(source: "onboarding_first_step")
                }
            )
            .environmentObject(environment)
            .padding(.top, 2)
        case .capture:
            VStack(alignment: .leading, spacing: 12) {
                OnboardingShortcutBullet(hotKey: environment.settingsStore.settings.captureHotKey)
                    .environmentObject(environment)

                OnboardingBulletList(items: [
                    rootText(copy, en: "You can customize this shortcut anytime in Settings > Shortcuts.", zh: "你可以随时在“设置 > 快捷键”里自定义这个快捷键。"),
                    rootText(copy, en: "If OCR fails, Paste Text keeps the workflow local and usable.", zh: "如果 OCR 失败，可用粘贴文本在本地继续。"),
                    rootText(copy, en: "Nothing enters Today until you confirm the recognized tasks.", zh: "任务进入今日列表前必须由你确认。")
                ])
            }
        case .agents:
            VStack(alignment: .leading, spacing: 14) {
                switch agentStepState {
                case .detecting:
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(rootText(copy, en: "Detecting supported Code Agents on this Mac…", zh: "正在检测本机支持的 Code Agent…"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(RootTheme.secondaryText)
                    }
                case .readyToInstall:
                    OnboardingBulletList(items: [
                        rootText(copy, en: "TodoPilot detected: \(detectedProviderNames).", zh: "已检测到：\(detectedProviderNames)。"),
                        rootText(copy, en: "After authorization, TodoPilot monitors when Code Agent tasks start, finish or need attention.", zh: "授权后，TodoPilot 会监听 Code Agent 任务的开始、完成和异常状态。"),
                        rootText(copy, en: "Tasks are added to Todo automatically and updated when their status changes.", zh: "任务开始时自动加入 Todo，完成或异常时自动更新并提醒。"),
                        rootText(copy, en: "You can turn monitoring off or uninstall it anytime in Settings.", zh: "你可以随时在设置中关闭或卸载。")
                    ])
                case .unavailable:
                    OnboardingBulletList(items: [
                        rootText(copy, en: "No supported Code Agent was detected yet.", zh: "暂未检测到支持的 Code Agent。"),
                        rootText(copy, en: "TodoPilot supports local Codex, Claude Code, and Cursor monitoring.", zh: "TodoPilot 支持本机 Codex、Claude Code 和 Cursor 监控。"),
                        rootText(copy, en: "Install or update an Agent, then enable monitoring later in Settings > Agent Monitoring.", zh: "安装或更新 Agent 后，可随时前往“设置 > Agent 监控”开启。")
                    ])
                case .enabled:
                    OnboardingBulletList(items: [
                        rootText(copy, en: "Code Agent monitoring is already enabled on this Mac.", zh: "本机 Code Agent 监控已经开启。"),
                        rootText(copy, en: "Tasks are added to Todo automatically and updated when their status changes.", zh: "任务开始时自动加入 Todo，完成或异常时自动更新并提醒。"),
                        rootText(copy, en: "You can manage providers or uninstall TodoPilot hooks in Settings.", zh: "你可以在设置中管理 Provider 或卸载 TodoPilot Hook。")
                    ])
                }

                if environment.detectedAgentProviders.contains(.codex) {
                    Text(rootText(
                        copy,
                        en: "Codex app: open Settings > Hooks > User configuration, then trust both pending items. Codex CLI: enter /hooks.",
                        zh: "Codex 桌面版：打开“设置 → 钩子 → 用户配置”，分别信任两项待审核内容；Codex CLI 可输入 /hooks。"
                    ))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(RootTheme.warning)
                }

                if environment.agentIntegrationMessage == "install_failed" {
                    Text(rootText(copy, en: "Installation did not complete. Try again here or open Settings for help.", zh: "安装未完成，请重试，或前往设置中处理。"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(RootTheme.warning)
                } else if environment.agentIntegrationMessage == "upgrade_required" {
                    Text(rootText(copy, en: "This Agent version does not support monitoring yet. Upgrade it and try again.", zh: "当前 Agent 版本暂不支持监控，请升级后重试。"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(RootTheme.warning)
                }
            }
        case .reminders:
            VStack(alignment: .leading, spacing: 14) {
                OnboardingBulletList(items: [
                    rootText(copy, en: "After local OCR, enter the task title and details yourself before adding it to Today.", zh: "本地 OCR 后，由你手动填写任务标题和详情，再加入今日列表。"),
                    rootText(copy, en: "Screenshots are not uploaded by default, and Apple Vision OCR runs locally.", zh: "截图默认不会上传，Apple Vision OCR 在本地运行。"),
                    rootText(copy, en: "OCR text stays on this Mac; the status island and flight reminders also run locally.", zh: "OCR 文本始终留在本机；状态岛和飞行提醒也在本地运行。"),
                    rootText(copy, en: "You can keep using TodoPilot locally without logging in.", zh: "你可以不登录，直接使用本地模式。")
                ])

                if privacyContinuation == .waitForDetection {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(rootText(copy, en: "Checking this Mac for supported Code Agents…", zh: "正在检测本机支持的 Code Agent…"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(RootTheme.secondaryText)
                    }
                }
            }
        }
    }

    private func primaryButtonTitle(_ copy: AppCopy) -> String {
        switch step {
        case .permission where !screenRecordingGranted && !hasOpenedScreenRecordingSettings:
            copy.openPrivacySettings
        case .permission where !screenRecordingGranted:
            rootText(copy, en: "Check Permission", zh: "检查权限")
        case .reminders where privacyContinuation == .waitForDetection:
            rootText(copy, en: "Detecting Code Agents…", zh: "正在检测 Code Agent…")
        case .agents:
            switch agentStepState {
            case .detecting:
                rootText(copy, en: "Detecting…", zh: "检测中…")
            case .readyToInstall:
                rootText(copy, en: "Authorize & Install", zh: "授权并安装")
            case .unavailable, .enabled:
                rootText(copy, en: "Continue", zh: "继续")
            }
        default:
            nextStep == nil
                ? rootText(copy, en: "Start Local Mode", zh: "开始本地模式")
                : rootText(copy, en: "Next", zh: "下一步")
        }
    }

    private var primaryButtonSystemImage: String {
        switch step {
        case .permission where !screenRecordingGranted:
            "gearshape"
        case .reminders where privacyContinuation == .waitForDetection:
            "magnifyingglass"
        case .agents:
            switch agentStepState {
            case .detecting:
                "magnifyingglass"
            case .readyToInstall:
                "checkmark.shield"
            case .unavailable:
                "arrow.right"
            case .enabled:
                "checkmark"
            }
        default:
            nextStep == nil ? "checkmark" : "arrow.right"
        }
    }

    private func handlePrimaryAction() {
        if step == .permission {
            refreshScreenRecordingStatus()

            guard screenRecordingGranted else {
                if hasOpenedScreenRecordingSettings {
                    permissionCheckFailed = true
                }
                openScreenRecordingSettings(
                    source: "onboarding_primary",
                    clearsPermissionCheckFailure: !hasOpenedScreenRecordingSettings
                )
                return
            }
        }

        if step == .agents {
            switch agentStepState {
            case .detecting:
                return
            case .unavailable, .enabled:
                advanceOrFinish()
            case .readyToInstall:
                let providers = Set(environment.detectedAgentProviders)
                Task { @MainActor in
                    guard await environment.authorizeAgentMonitoring(providers: providers) else {
                        return
                    }
                    if AgentOnboardingPresentationPolicy.agentInstallationSuccessAction == .openAgentSettings {
                        onOpenAgentSettings()
                    }
                }
            }
            return
        }

        if step == .reminders, privacyContinuation == .waitForDetection {
            return
        }

        advanceOrFinish()
    }

    private func closeGuide() {
        guard !environment.agentIntegrationOperation.isInstalling else {
            return
        }
        if AgentOnboardingPresentationPolicy.shouldMarkAgentOnboardingSkippedWhenClosing(
            isShowingAgentStep: step == .agents
        ) {
            environment.skipAgentOnboarding()
        }
        onFinish()
    }

    private func advanceOrFinish() {
        if let next = nextStep {
            withAnimation(.snappy(duration: 0.18)) {
                step = next
            }
        } else {
            onFinish()
        }
    }

    private var detectedProviderNames: String {
        environment.detectedAgentProviders.map(\.displayName).joined(separator: "、")
    }

    private func refreshScreenRecordingStatus() {
        let isGranted = CGPreflightScreenCaptureAccess()
        screenRecordingGranted = isGranted
        if isGranted {
            permissionCheckFailed = false
        }
    }

    private func openScreenRecordingSettings(source: String, clearsPermissionCheckFailure: Bool = true) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        hasOpenedScreenRecordingSettings = true
        if clearsPermissionCheckFailure {
            permissionCheckFailed = false
        }
        environment.telemetry.track(.permissionScreenRecordingPrompted, properties: [
            "source": .publicText(source)
        ])
        NSWorkspace.shared.open(url)
    }
}

private struct OnboardingStepIndicator: View {
    @EnvironmentObject private var environment: AppEnvironment
    let currentStep: OnboardingStep
    let steps: [OnboardingStep]

    var body: some View {
        let copy = environment.copy

        HStack(spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(spacing: 7) {
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(index <= (steps.firstIndex(of: currentStep) ?? 0) ? .white : RootTheme.secondaryText)
                        .frame(width: 22, height: 22)
                        .background(
                            index <= (steps.firstIndex(of: currentStep) ?? 0) ? RootTheme.accent : Color.black.opacity(0.08),
                            in: Circle()
                        )

                    Text(step.title(copy))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(step == currentStep ? RootTheme.primaryText : RootTheme.secondaryText)
                        .lineLimit(1)
                }

                if index < steps.count - 1 {
                    Rectangle()
                        .fill(Color.black.opacity(0.08))
                        .frame(width: 28, height: 1)
                }
            }
        }
    }
}

private struct OnboardingBulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RootTheme.accent)
                        .padding(.top, 2)

                    Text(item)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(RootTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct OnboardingShortcutBullet: View {
    @EnvironmentObject private var environment: AppEnvironment
    let hotKey: CaptureHotKey

    var body: some View {
        let copy = environment.copy

        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RootTheme.accent)
                .padding(.top, 5)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    shortcutLead(copy)
                    shortcutAction(copy)
                }

                VStack(alignment: .leading, spacing: 6) {
                    shortcutLead(copy)
                    shortcutAction(copy)
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(RootTheme.secondaryText)
        }
    }

    private func shortcutLead(_ copy: AppCopy) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(rootText(copy, en: "Press", zh: "按"))
            ShortcutKeyChordView(hotKey, style: .inline)
        }
    }

    private func shortcutAction(_ copy: AppCopy) -> some View {
        Text(rootText(
            copy,
            en: "then drag over text you want to turn into tasks.",
            zh: "后拖拽框选想转成任务的文字。"
        ))
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct OnboardingPermissionCallout: View {
    @EnvironmentObject private var environment: AppEnvironment
    let isGranted: Bool
    let didCheckFail: Bool
    let onOpenSettings: () -> Void

    var body: some View {
        let copy = environment.copy

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                OnboardingStatusPill(
                    title: isGranted
                        ? rootText(copy, en: "Permission ready", zh: "权限已就绪")
                        : rootText(copy, en: "Permission needed", zh: "需要权限"),
                    style: isGranted ? .ready : .warning
                )

                Button {
                    onOpenSettings()
                } label: {
                    Label(copy.openPrivacySettings, systemImage: "gearshape")
                }
                .buttonStyle(TodoPilotModalGhostButtonStyle())
                .disabled(isGranted)
            }

            Text(statusMessage(copy))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(RootTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (isGranted ? Color.green.opacity(0.08) : Color.orange.opacity(0.10)),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isGranted ? Color.green.opacity(0.16) : Color.orange.opacity(0.20), lineWidth: 1)
        )
    }

    private func statusMessage(_ copy: AppCopy) -> String {
        if isGranted {
            return rootText(copy, en: "TodoPilot can start capture as soon as you finish the guide.", zh: "完成引导后，TodoPilot 就可以直接开始框选捕获。")
        }

        if didCheckFail {
            return rootText(copy, en: "TodoPilot still cannot see the permission. Confirm the toggle is enabled, then restart the app if macOS asks for it.", zh: "TodoPilot 还未检测到权限。请确认开关已开启；如果 macOS 提示需要重启，请重启应用后继续。")
        }

        return rootText(copy, en: "Opening the privacy pane now keeps the first capture from being interrupted later.", zh: "现在先打开隐私设置授权，后面第一次框选时就不会被打断。")
    }
}

private enum OnboardingStatusPillStyle {
    case ready
    case warning

    var foreground: Color {
        switch self {
        case .ready:
            Color(red: 0.10, green: 0.48, blue: 0.24)
        case .warning:
            Color(red: 0.76, green: 0.45, blue: 0.02)
        }
    }

    var background: Color {
        switch self {
        case .ready:
            Color(red: 0.10, green: 0.60, blue: 0.28).opacity(0.12)
        case .warning:
            Color(red: 1.00, green: 0.66, blue: 0.12).opacity(0.14)
        }
    }
}

private struct OnboardingStatusPill: View {
    let title: String
    let style: OnboardingStatusPillStyle

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(style.foreground)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(style.background, in: Capsule())
    }
}

private struct HistoryView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject var taskStore: TaskStore

    var body: some View {
        let copy = environment.copy
        let recentHistoryTasks = taskStore.recentHistoryTasks
        let completedTasks = recentHistoryTasks.filter { task in
            task.deletedAt == nil && task.status == .done
        }
        let deletedTasks = recentHistoryTasks.filter { $0.deletedAt != nil }

        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                PageTitle(title: copy.history, note: copy.historyDisplayLimitNote, subtitle: copy.openDoneSummary(
                    open: deletedTasks.count,
                    done: completedTasks.count
                ))

                HistorySection(title: copy.done) {
                    if completedTasks.isEmpty {
                        HistoryEmptyRow(text: copy.clear)
                    } else {
                        ForEach(completedTasks) { task in
                            HistoryTaskRow(
                                task: task,
                                accessory: Text(task.updatedAt, style: .relative),
                                primaryHelp: copy.undo,
                                onPrimaryAction: { taskStore.undoDone(task.id) },
                                onDelete: {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        taskStore.softDelete(task.id)
                                    }
                                }
                            )
                            .environmentObject(environment)
                        }
                    }
                }

                HistorySection(title: copy.deleted) {
                    if deletedTasks.isEmpty {
                        HistoryEmptyRow(text: copy.clear)
                    } else {
                        ForEach(deletedTasks) { task in
                            HistoryTaskRow(
                                task: task,
                                accessory: Text(copy.restore),
                                primaryHelp: copy.restore,
                                onPrimaryAction: { taskStore.restoreDeleted(task.id) }
                            )
                            .environmentObject(environment)
                        }
                    }
                }
            }
            .padding(.top, 44)
            .padding(.horizontal, 48)
            .padding(.bottom, 48)
        }
        .background(RootTheme.appBackground)
    }
}

private struct AccountPlaneAvatar: View {
    let size: CGFloat
    let planeWidth: CGFloat
    var showCheck: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(Color.black)
                PixelPlaneMark()
                    .frame(width: planeWidth, height: max(18, planeWidth * 0.45))
            }
            .frame(width: size, height: size)

            if showCheck {
                Image(systemName: "checkmark")
                    .font(.system(size: size > 60 ? 14 : 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size > 60 ? 25 : 18, height: size > 60 ? 25 : 18)
                    .background(RootTheme.success, in: Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: size > 60 ? 3 : 2))
                    .offset(x: size > 60 ? 4 : 2, y: size > 60 ? 4 : 2)
            }
        }
        .frame(width: size + (showCheck ? 6 : 0), height: size + (showCheck ? 6 : 0))
    }
}

private struct PageTitle: View {
    let title: String
    let note: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(RootTheme.primaryText)
                Text(note)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(RootTheme.secondaryText)
            }
            Text(subtitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(RootTheme.secondaryText)
        }
    }
}

private struct HistorySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(RootTheme.secondaryText)
            LazyVStack(spacing: 10, content: content)
        }
    }
}

private struct HistoryTaskRow<Accessory: View>: View {
    @EnvironmentObject private var environment: AppEnvironment
    let task: TodoTask
    let accessory: Accessory
    let primaryHelp: String
    let onPrimaryAction: () -> Void
    var onDelete: (() -> Void)? = nil
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPrimaryAction) {
                HStack(spacing: 12) {
                    Image(systemName: task.deletedAt == nil && task.status == .done ? "checkmark.circle" : "trash")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(RootTheme.secondaryText)

                    Text(task.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(RootTheme.primaryText)
                        .lineLimit(1)

                    Spacer()

                    accessory
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(RootTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(primaryHelp)

            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(RootTheme.destructive)
                        .frame(width: 32, height: 32)
                        .background(RootTheme.destructive.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(environment.copy.delete)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background((isHovering ? Color.white.opacity(0.96) : Color.white.opacity(0.86)), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isHovering ? RootTheme.accent.opacity(0.20) : Color.black.opacity(0.045), lineWidth: 1)
        )
        .shadow(color: .black.opacity(isHovering ? 0.040 : 0), radius: 10, y: 4)
        .offset(y: isHovering ? -1 : 0)
        .animation(.easeOut(duration: 0.16), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

private struct HistoryEmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(RootTheme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .padding(.horizontal, 16)
            .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct OCRReviewSession: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var ocrResult: OCRResult?
    var createdFromManualText: Bool
}

enum OCRReviewPresentationContext: Equatable {
    case sheet
    case floatingPanel

    var dismissesHostAfterAction: Bool {
        self == .sheet
    }
}

struct OCRReviewSheet: View {
    private static let maxReviewedTextLength = 12_000
    private static let designWidth: CGFloat = 820
    private static let designHeight: CGFloat = 580
    private static let editorHeight: CGFloat = 282

    let session: OCRReviewSession
    let presentationContext: OCRReviewPresentationContext
    let onUseText: (String) -> Void
    let onCancel: () -> Void

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var undoTextStack: [String]
    @State private var redoTextStack: [String] = []

    init(
        session: OCRReviewSession,
        presentationContext: OCRReviewPresentationContext = .sheet,
        onUseText: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.session = session
        self.presentationContext = presentationContext
        self.onUseText = onUseText
        self.onCancel = onCancel
        _text = State(initialValue: session.text)
        _undoTextStack = State(initialValue: [])
    }

    var body: some View {
        let copy = environment.copy
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isTextOverLimit = text.count > Self.maxReviewedTextLength

        TodoPilotModalShell(
            title: session.createdFromManualText ? copy.reviewPastedText : copy.reviewOCRText,
            headerSystemImage: session.createdFromManualText ? "doc.text" : "text.viewfinder",
            headerBadge: session.createdFromManualText ? copy.localTextBadge : copy.localOCRBadge,
            width: Self.designWidth,
            height: Self.designHeight,
            chromePolicy: .closableContentDialog,
            showsContentScrollIndicators: false,
            allowsContentScrolling: false,
            layout: .designReferenceFloating,
            onClose: {
                onCancel()
                dismissHostIfNeeded()
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text(session.createdFromManualText ? copy.pasteText : rootText(copy, en: "Recognized Text", zh: "识别结果"))
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(TodoPilotTheme.primaryText)

                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TodoPilotTheme.accent)
                        .frame(width: 30, height: 30)
                        .background(TodoPilotTheme.accent.opacity(0.10), in: Circle())

                    Spacer()

                    HStack(spacing: 18) {
                        OCRReviewHistoryButton(
                            systemImage: "arrow.uturn.backward",
                            accessibilityLabel: copy.undo,
                            isEnabled: !undoTextStack.isEmpty
                        ) {
                            undoTextChange()
                        }

                        OCRReviewHistoryButton(
                            systemImage: "arrow.uturn.forward",
                            accessibilityLabel: rootText(copy, en: "Redo", zh: "重做"),
                            isEnabled: !redoTextStack.isEmpty
                        ) {
                            redoTextChange()
                        }
                    }

                    Text(copy.textCharacterCount(text.count, max: Self.maxReviewedTextLength))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(isTextOverLimit ? .orange : TodoPilotTheme.secondaryText)
                        .monospacedDigit()
                        .frame(minWidth: 92, alignment: .trailing)
                }

                OCRReviewEditor(
                    text: Binding(
                        get: { text },
                        set: { recordTextChange($0) }
                    ),
                    placeholder: session.createdFromManualText ? copy.pasteText : copy.reviewOCRText,
                    minHeight: Self.editorHeight
                )

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        if session.ocrResult?.hasLowConfidenceBlocks == true {
                            Label(copy.lowConfidenceSummary, systemImage: "exclamationmark.triangle")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.orange)
                        }

                        if isTextOverLimit {
                            Label(rootText(copy, en: "Keep the reviewed text under \(Self.maxReviewedTextLength) characters.", zh: "检查文本请控制在 \(Self.maxReviewedTextLength) 字以内。"), systemImage: "exclamationmark.triangle")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.orange)
                        }

                        Label(rootText(copy, en: "Recognition and task creation stay on this Mac.", zh: "识别和任务创建始终在本机完成。"), systemImage: "lock.shield")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TodoPilotTheme.secondaryText)
                    }

                    Spacer(minLength: 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } footer: {
            HStack(spacing: 12) {
                Button(copy.cancel) {
                    onCancel()
                    dismissHostIfNeeded()
                }
                .buttonStyle(OCRReviewFooterGhostButtonStyle(width: 92))

                Spacer()

                Button {
                    onUseText(trimmedText)
                    dismissHostIfNeeded()
                } label: {
                    Label(copy.useTextAsTask, systemImage: "list.bullet")
                }
                .buttonStyle(OCRReviewFooterPrimaryButtonStyle(width: 164))
                .disabled(trimmedText.isEmpty || isTextOverLimit)
            }
        }
    }

    private func dismissHostIfNeeded() {
        guard presentationContext.dismissesHostAfterAction else {
            return
        }
        dismiss()
    }

    private func recordTextChange(_ newText: String) {
        guard newText != text else {
            return
        }
        undoTextStack.append(text)
        if undoTextStack.count > 100 {
            undoTextStack.removeFirst(undoTextStack.count - 100)
        }
        redoTextStack.removeAll()
        text = newText
    }

    private func undoTextChange() {
        guard let previousText = undoTextStack.popLast() else {
            return
        }
        redoTextStack.append(text)
        text = previousText
    }

    private func redoTextChange() {
        guard let nextText = redoTextStack.popLast() else {
            return
        }
        undoTextStack.append(text)
        text = nextText
    }
}

private struct OCRReviewEditor: View {
    @Binding var text: String
    let placeholder: String
    let minHeight: CGFloat

    private var lineCount: Int {
        max(1, text.components(separatedBy: .newlines).count)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .trailing, spacing: 12) {
                ForEach(1...lineCount, id: \.self) { index in
                    Text("\(index)")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(TodoPilotTheme.secondaryText.opacity(0.70))
                        .frame(width: 28, alignment: .trailing)
                }
            }
            .padding(.top, 22)
            .padding(.horizontal, 10)
            .frame(minHeight: minHeight, alignment: .topTrailing)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(TodoPilotModalTheme.controlStroke.opacity(0.80))
                    .frame(width: 1)
            }

            ZStack(alignment: .topLeading) {
                OCRPlainTextView(text: $text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)

                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(TodoPilotTheme.secondaryText.opacity(0.58))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        }
        .frame(minHeight: minHeight)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(TodoPilotModalTheme.controlStroke.opacity(1.25), lineWidth: 1)
        )
        .clipped()
    }
}

private struct OCRReviewHistoryButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 26, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconColor: Color {
        isEnabled ? TodoPilotTheme.secondaryText : TodoPilotTheme.secondaryText.opacity(0.42)
    }
}

private struct OCRPlainTextView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.font = .systemFont(ofSize: 15, weight: .regular)
        textView.textContainerInset = .zero
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }
        if textView.string != text {
            textView.string = text
        }
        textView.font = .systemFont(ofSize: 15, weight: .regular)
        textView.textColor = .labelColor
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            text = textView.string
        }
    }
}

private struct OCRReviewFooterGhostButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let width: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(isEnabled ? TodoPilotTheme.secondaryText : TodoPilotTheme.secondaryText.opacity(0.42))
            .frame(width: width, height: 44)
            .background(Color.white.opacity(isEnabled ? 0.86 : 0.58), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(TodoPilotModalTheme.controlStroke, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct OCRReviewFooterPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let width: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: width, height: 50)
            .background(
                TodoPilotTheme.accent.opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.42),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .shadow(color: TodoPilotTheme.accent.opacity(isEnabled ? 0.20 : 0), radius: 13, y: 8)
    }
}

private func rootText(_ copy: AppCopy, en: String, zh: String) -> String {
    copy.language == .chinese ? zh : en
}

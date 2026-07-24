import AppKit
import Carbon
import SwiftUI

enum AppVersionPresentation {
    static func displayVersion(
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> String {
        guard let version = infoDictionary["CFBundleShortVersionString"] as? String else {
            return "—"
        }
        let normalizedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedVersion.isEmpty ? "—" : "v\(normalizedVersion)"
    }
}

struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settingsStore: LocalSettingsStore

    @State private var selectedSection: SettingsPane
    @State private var exportMessage: String?
    @State private var shortcutMessage: String?
    @State private var isRecordingCaptureHotKey = false
    @State private var showClearConfirmation = false

    init(initialSection: SettingsPane = .general) {
        _selectedSection = State(initialValue: initialSection)
    }

    var body: some View {
        let copy = environment.copy

        HStack(spacing: 0) {
            SettingsPaneSidebar(selectedSection: $selectedSection)
                .environmentObject(environment)

            Rectangle()
                .fill(SettingsTheme.divider)
                .frame(width: 1)

            ScrollView {
                detailContent(copy)
                    .frame(maxWidth: 760, alignment: .topLeading)
                    .padding(.top, 38)
                    .padding(.leading, 38)
                    .padding(.trailing, 56)
                    .padding(.bottom, 72)
            }
            .scrollIndicators(.visible)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(SettingsTheme.appBackground)
        }
        .background(SettingsTheme.appBackground)
        .alert(copy.clearAllLocalTasks, isPresented: $showClearConfirmation) {
            Button(copy.cancel, role: .cancel) {}
            Button(copy.clearButton, role: .destructive) {
                let count = environment.taskStore.tasks.count
                environment.taskStore.clearAllData()
                environment.logger.info("local_tasks_cleared", metadata: [
                    "count": .numeric(count)
                ])
            }
        } message: {
            Text(copy.clearLocalTasksHelp)
        }
    }

    @ViewBuilder
    private func detailContent(_ copy: AppCopy) -> some View {
        switch selectedSection {
        case .general:
            generalPane(copy)
        case .privacy:
            privacyPane(copy)
        case .flight:
            flightPane(copy)
        case .agents:
            agentPane(copy)
        case .shortcuts:
            shortcutsPane(copy)
        case .export:
            exportPane(copy)
        }
    }

    private func generalPane(_ copy: AppCopy) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsPaneTitle(title: text(copy, en: "General Settings", zh: "通用设置"))

            SettingsRows {
                SettingsRow(
                    title: text(copy, en: "Show status island on launch", zh: "启动时自动显示状态岛"),
                    subtitle: text(copy, en: "Show the top black capsule after app launch.", zh: "开机后自动显示顶部黑色胶囊。")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settingsStore.settings.statusIslandMode != .hidden },
                        set: { isEnabled in
                            environment.updateStatusIslandMode(isEnabled ? .centered : .hidden)
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                SettingsRule()

                SettingsRow(
                    title: text(copy, en: "Status island position", zh: "状态岛位置"),
                    subtitle: text(copy, en: "Top center notch area, menu bar icon mode, or hidden.", zh: "顶部刘海区、菜单栏图标模式或隐藏。")
                ) {
                    SettingsMenuButton(
                        selection: Binding(
                            get: { settingsStore.settings.statusIslandMode },
                            set: { environment.updateStatusIslandMode($0) }
                        ),
                        options: StatusIslandMode.allCases.map {
                            SettingsMenuOption(value: $0, title: copy.statusIslandModeTitle($0))
                        }
                    )
                    .frame(width: 210)
                }

                SettingsRule()

                SettingsRow(
                    title: text(copy, en: "Default sorting", zh: "默认排序"),
                    subtitle: text(copy, en: "How tasks are ordered in Today List.", zh: "Today List 中的任务排序方式。")
                ) {
                    SettingsMenuButton(
                        selection: Binding(
                            get: { settingsStore.settings.defaultTodaySortMode },
                            set: { environment.updateDefaultTodaySortMode($0) }
                        ),
                        options: DefaultTodaySortMode.allCases.map {
                            SettingsMenuOption(value: $0, title: $0.title(copy))
                        }
                    )
                    .frame(width: 190)
                }

                SettingsRule()

                SettingsRow(
                    title: text(copy, en: "App language", zh: "应用语言"),
                    subtitle: text(copy, en: "Remember your preferred interface language.", zh: "记住你的界面语言偏好。")
                ) {
                    Picker("", selection: Binding(
                        get: { settingsStore.settings.language },
                        set: { language in
                            environment.updateLanguage(language)
                            exportMessage = nil
                            shortcutMessage = nil
                        }
                    )) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                }

                SettingsRule()

                SettingsRow(
                    title: text(copy, en: "App version", zh: "应用版本"),
                    subtitle: text(copy, en: "The version currently installed on this Mac.", zh: "当前安装在这台 Mac 上的版本。")
                ) {
                    SettingsStatusPill(
                        title: AppVersionPresentation.displayVersion(),
                        style: .neutral
                    )
                }

                SettingsRule()

                SettingsRow(
                    title: text(copy, en: "First launch guide", zh: "首次启动引导"),
                    subtitle: text(copy, en: "Review capture, privacy, local mode, and flight reminder basics.", zh: "重新查看捕获、隐私、本地模式和飞行提醒说明。")
                ) {
                    Button {
                        NotificationCenter.default.post(name: .showOnboardingGuide, object: nil)
                    } label: {
                        Label(text(copy, en: "Show Guide", zh: "查看引导"), systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func privacyPane(_ copy: AppCopy) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsPaneTitle(title: text(copy, en: "Privacy & Data", zh: "隐私与数据"))

            SettingsInfoBanner(
                systemImage: "shield",
                text: text(
                    copy,
                    en: "Screenshots and OCR text stay on this Mac. Tasks are created only after your manual confirmation.",
                    zh: "截图与 OCR 文本始终留在本机，任务仅在你手动确认后创建。"
                )
            )

            SettingsRows {
                SettingsRow(
                    title: text(copy, en: "Screenshots stay local", zh: "截图不上传"),
                    subtitle: text(copy, en: "Frame captures are processed locally and never uploaded.", zh: "框选截图仅在本地处理，绝不上传。")
                ) {
                    SettingsStatusPill(title: text(copy, en: "On", zh: "已开启"), style: .blue)
                }

                SettingsRule()

                SettingsRow(
                    title: text(copy, en: "Error log redaction", zh: "错误日志脱敏"),
                    subtitle: text(copy, en: "Task text and OCR raw text are removed from logs.", zh: "日志自动移除任务正文和 OCR 原文。")
                ) {
                    SettingsStatusPill(title: copy.redacted, style: .neutral)
                }

                SettingsRule()

                SettingsRow(
                    title: text(copy, en: "Offline runtime", zh: "离线运行"),
                    subtitle: text(copy, en: "This edition has no account tokens or service credentials.", zh: "此版本不使用账号令牌或服务凭据。")
                ) {
                    SettingsStatusPill(title: text(copy, en: "Local", zh: "本地"), style: .neutral)
                }
            }

            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Text(text(copy, en: "Clear all local data...", zh: "清除所有本地数据..."))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(SettingsTheme.destructive)
            }
            .buttonStyle(.plain)
        }
    }

    private func flightPane(_ copy: AppCopy) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsPaneTitle(title: copy.flightReminders)

            SettingsRows {
                SettingsRow(
                    title: text(copy, en: "Enable flight reminders", zh: "启用飞行提醒"),
                    subtitle: text(copy, en: "Pixel plane reminders for important tasks.", zh: "像素风小飞机横穿屏幕提醒关键任务。")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settingsStore.settings.flightRemindersEnabled },
                        set: { environment.updateFlightRemindersEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                SettingsRule()

                SettingsRow(
                    title: text(copy, en: "Reminder sound", zh: "提醒声音"),
                    subtitle: text(copy, en: "Play a light prompt sound when the plane passes.", zh: "飞机经过时播放轻微提示音。")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settingsStore.settings.flightReminderSoundEnabled },
                        set: { environment.updateFlightReminderSoundEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                SettingsRule()

                SettingsRow(
                    title: text(copy, en: "Task flight reminder time", zh: "任务飞机提醒时间"),
                    subtitle: text(copy, en: "Choose how long before a task's due time the plane should fly across.", zh: "选择在任务截止前多久触发小飞机飞过提醒。")
                ) {
                    SettingsMenuButton(
                        selection: Binding(
                            get: { settingsStore.settings.flightReminderLeadTime },
                            set: { environment.updateFlightReminderLeadTime($0) }
                        ),
                        options: FlightReminderLeadTime.allCases.map {
                            SettingsMenuOption(value: $0, title: $0.title(copy))
                        }
                    )
                    .frame(width: 230)
                }

                SettingsRule()

                SettingsRow(
                    title: text(copy, en: "Remind again at due time", zh: "截止时再次提醒"),
                    subtitle: text(copy, en: "After the early plane reminder, fly again when the task reaches its due time.", zh: "提前提醒后，任务真正到截止时间时再飞一次。")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settingsStore.settings.flightReminderAtDeadlineEnabled },
                        set: { environment.updateFlightReminderAtDeadlineEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                SettingsRule()

                SettingsRow(
                    title: text(copy, en: "Reminder frequency", zh: "提醒频率"),
                    subtitle: text(copy, en: "Maximum reminder frequency per task and per hour.", zh: "单任务 30 分钟内和全局每小时的最多触发次数。")
                ) {
                    SettingsMenuButton(
                        selection: Binding(
                            get: { settingsStore.settings.flightReminderFrequency },
                            set: { environment.updateFlightReminderFrequency($0) }
                        ),
                        options: FlightReminderFrequency.allCases.map {
                            SettingsMenuOption(value: $0, title: $0.title(copy))
                        }
                    )
                    .frame(width: 210)
                }

                SettingsRule()

                SettingsRow(
                    title: text(copy, en: "Silence during full screen / casting", zh: "全屏/投屏时静音"),
                    subtitle: text(copy, en: "Pause reminders during mirrored display or common meeting apps.", zh: "演示或会议时不展示飞行提醒内容。")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settingsStore.settings.conservativeFlightSilenceEnabled },
                        set: { environment.updateConservativeFlightSilenceEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                SettingsRule()

                SettingsRow(
                    title: text(copy, en: "Flight theme", zh: "飞行主题"),
                    subtitle: text(copy, en: "Switch plane and banner styles.", zh: "切换飞机和旗帜样式。")
                ) {
                    HStack(spacing: 10) {
                        SettingsThemeChip(title: text(copy, en: "Blue pixel plane", zh: "蓝色像素机"), isSelected: true)
                    }
                }
            }
        }
    }

    private func shortcutsPane(_ copy: AppCopy) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsPaneTitle(title: copy.shortcut)

            SettingsRows {
                SettingsRow(
                    title: copy.frameCapture,
                    subtitle: text(copy, en: "Trigger screen frame selection mode.", zh: "触发屏幕框选模式。")
                ) {
                    VStack(alignment: .trailing, spacing: 8) {
                        ShortcutKeyChordView(settingsStore.settings.captureHotKey, style: .settings)

                        HStack(spacing: 8) {
                            Button {
                                if isRecordingCaptureHotKey {
                                    cancelCaptureHotKeyEditing()
                                } else {
                                    beginCaptureHotKeyEditing(copy)
                                }
                            } label: {
                                Label(
                                    isRecordingCaptureHotKey
                                        ? copy.shortcutListening
                                        : copy.shortcutChange,
                                    systemImage: "keyboard.badge.ellipsis"
                                )
                            }
                            .buttonStyle(.bordered)

                            Button {
                                applyCaptureHotKey(.preset(.optionSpace), copy: copy)
                            } label: {
                                Text(copy.shortcutDefault)
                            }
                            .buttonStyle(.bordered)
                            .disabled(settingsStore.settings.captureHotKey == .preset(.optionSpace))
                        }

                        ShortcutRecorderHost(
                            isRecording: $isRecordingCaptureHotKey,
                            onCapture: { hotKey in
                                applyCaptureHotKey(hotKey, copy: copy)
                            },
                            onInvalid: {
                                shortcutMessage = copy.shortcutInvalidCombination
                            },
                            onCancel: {
                                cancelCaptureHotKeyEditing()
                            }
                        )
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                        .onDisappear {
                            if isRecordingCaptureHotKey {
                                cancelCaptureHotKeyEditing()
                            }
                        }
                    }
                }

                if let shortcutMessage {
                    Text(shortcutMessage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(environment.hotKeyRegistrationError == nil ? SettingsTheme.secondaryText : .orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 12)
                }

                SettingsRule()

                SettingsRow(
                    title: copy.openTodayList,
                    subtitle: text(copy, en: "Expand or focus the Today task panel.", zh: "展开或聚焦今日任务面板。")
                ) {
                    ShortcutKeyChordView(tokens: .commandT, style: .settings)
                }

                SettingsRule()

                SettingsRow(
                    title: copy.muteFlightReminders,
                    subtitle: text(copy, en: "Temporarily close all flight reminders.", zh: "临时关闭所有飞行提醒。")
                ) {
                    ShortcutKeyChordView(tokens: .commandOptionM, style: .settings)
                }
            }
        }
    }

    private func exportPane(_ copy: AppCopy) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsPaneTitle(title: text(copy, en: "Export & Integrations", zh: "导出与集成"))

            VStack(alignment: .leading, spacing: 12) {
                SettingsIntegrationRow(
                    title: "Apple Reminders",
                    status: "v1.0",
                    statusStyle: .warning,
                    actionTitle: nil,
                    action: nil
                )
                SettingsIntegrationRow(
                    title: text(copy, en: "CSV Export", zh: "CSV 导出"),
                    status: text(copy, en: "Available", zh: "可用"),
                    statusStyle: .success,
                    actionTitle: copy.copy,
                    action: { exportCSV(copy) }
                )
                SettingsIntegrationRow(
                    title: text(copy, en: "Markdown Export", zh: "Markdown 导出"),
                    status: text(copy, en: "Available", zh: "可用"),
                    statusStyle: .success,
                    actionTitle: copy.copy,
                    action: { exportMarkdown(copy) }
                )
            }

            if let exportMessage {
                Text(exportMessage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SettingsTheme.secondaryText)
            }
        }
    }

    private func agentPane(_ copy: AppCopy) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsPaneTitle(title: text(copy, en: "Code Agents", zh: "Code Agent"))

            SettingsInfoBanner(
                systemImage: "terminal",
                text: text(
                    copy,
                    en: "Set up once: install monitoring, complete any trust prompts, then start a new Agent task. TodoPilot shows Connected after it receives the task status.",
                    zh: "仅需设置一次：安装监控、按提示完成信任，再新建一个 Agent 任务。TodoPilot 收到任务状态后会显示“已连接”。"
                )
            )

            if environment.agentIntegrationOperation == .detecting {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                    Text(text(copy, en: "Detecting local Code Agents…", zh: "正在检测本机 Code Agent…"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SettingsTheme.secondaryText)
                }
                .accessibilityIdentifier("agent-detection-progress")
            }

            SettingsRows {
                SettingsRow(
                    title: text(copy, en: "Enable Agent monitoring", zh: "启用 Agent 监控"),
                    subtitle: environment.hasInstalledAgentProvider
                        ? text(copy, en: "Closing the main window keeps monitoring; quitting TodoPilot stops it.", zh: "关闭主窗口后继续监控；明确退出 TodoPilot 时停止。")
                        : text(copy, en: "Authorize and install at least one provider below first.", zh: "请先在下方授权并安装至少一个 Provider。")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settingsStore.settings.agentMonitoringEnabled },
                        set: { environment.updateAgentMonitoringEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!environment.hasInstalledAgentProvider || environment.agentIntegrationOperation.isBusy)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(AgentHookInstaller.Provider.allCases, id: \.self) { provider in
                    agentProviderRow(provider, copy: copy)
                }
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        _ = await environment.testAgentBridge()
                    }
                } label: {
                    if environment.agentIntegrationOperation == .testingBridge {
                        HStack(spacing: 7) {
                            ProgressView()
                                .controlSize(.small)
                            Text(text(copy, en: "Testing receiver…", zh: "正在测试接收器…"))
                        }
                    } else {
                        Label(text(copy, en: "Test TodoPilot receiver", zh: "测试 TodoPilot 本地接收器"), systemImage: "checkmark.shield")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(environment.agentIntegrationOperation.isBusy || !settingsStore.settings.agentMonitoringEnabled)

                Button(role: .destructive) {
                    Task {
                        await environment.uninstallAgentMonitoring(providers: Set(AgentHookInstaller.Provider.allCases))
                    }
                } label: {
                    Text(text(copy, en: "Uninstall all TodoPilot hooks", zh: "卸载全部 TodoPilot Hook"))
                }
                .buttonStyle(.borderless)
                .disabled(environment.agentIntegrationOperation.isBusy || !environment.hasInstalledAgentProvider)
            }

            if let message = environment.agentIntegrationMessage {
                Text(agentIntegrationMessage(message, copy: copy))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SettingsTheme.secondaryText)
            }
        }
        .onAppear {
            environment.refreshAgentIntegrationStatus()
        }
    }

    private func agentProviderRow(
        _ provider: AgentHookInstaller.Provider,
        copy: AppCopy
    ) -> some View {
        let health = environment.agentIntegrationHealth(for: provider)
        let installed = environment.agentHookInstaller.hasInstalledHook(for: provider)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: provider == .cursor ? "cursorarrow.rays" : "terminal")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SettingsTheme.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.displayName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(SettingsTheme.primaryText)
                    Text(agentProviderSubtitle(provider, copy: copy))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SettingsTheme.secondaryText)
                }

                Spacer()

                SettingsStatusPill(
                    title: agentHealthTitle(health, copy: copy),
                    style: agentHealthStyle(health)
                )

                Toggle("", isOn: Binding(
                    get: { agentProviderEnabled(provider) },
                    set: { environment.updateAgentProviderMonitoring(provider, enabled: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!installed || environment.agentIntegrationOperation.isBusy)
            }

            Text(agentHealthDetail(health, provider: provider, copy: copy))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(health == .needsRepair ? SettingsTheme.destructive : SettingsTheme.secondaryText)
                .padding(.leading, 42)

            HStack(spacing: 12) {
                switch health {
                case .notInstalled, .pendingAuthorization:
                    Button(text(copy, en: "Authorize & Install", zh: "授权并安装")) {
                        Task {
                            _ = await environment.authorizeAgentMonitoring(providers: [provider])
                        }
                    }
                    .buttonStyle(.borderedProminent)
                case .needsRepair:
                    Button(text(copy, en: "Repair", zh: "修复")) {
                        Task {
                            _ = await environment.authorizeAgentMonitoring(providers: [provider])
                        }
                    }
                    .buttonStyle(.borderedProminent)
                case .waitingCodexTrust:
                    Button(text(copy, en: "I trusted it in Codex", zh: "我已在 Codex 中信任")) {
                        environment.confirmCodexHooksTrusted()
                    }
                    .buttonStyle(.borderedProminent)
                case .needsUpgrade:
                    Text(text(copy, en: "Upgrade this Agent, then refresh detection.", zh: "请先升级该 Agent，再刷新检测。"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SettingsTheme.destructive)
                case .installing, .uninstalling:
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(health == .installing
                            ? text(copy, en: "Installing local hook…", zh: "正在安装本机 Hook…")
                            : text(copy, en: "Removing local hook…", zh: "正在卸载本机 Hook…"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SettingsTheme.secondaryText)
                    }
                case .readyForFirstRun, .connected, .paused:
                    EmptyView()
                }

                if installed, health != .uninstalling {
                    Button(role: .destructive) {
                        Task {
                            await environment.uninstallAgentMonitoring(providers: [provider])
                        }
                    } label: {
                        Text(text(copy, en: "Uninstall", zh: "卸载"))
                    }
                    .buttonStyle(.borderless)
                    .disabled(environment.agentIntegrationOperation.isBusy)
                }
            }
            .padding(.leading, 42)
        }
        .padding(18)
        .background(Color.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(SettingsTheme.rule, lineWidth: 1))
    }

    private func agentProviderEnabled(_ provider: AgentHookInstaller.Provider) -> Bool {
        switch provider {
        case .claudeCode: settingsStore.settings.claudeCodeMonitoringEnabled
        case .codex: settingsStore.settings.codexMonitoringEnabled
        case .cursor: settingsStore.settings.cursorMonitoringEnabled
        }
    }

    private func agentHealthTitle(_ health: AgentIntegrationHealth, copy: AppCopy) -> String {
        switch health {
        case .notInstalled: text(copy, en: "Not installed", zh: "未安装")
        case .pendingAuthorization: text(copy, en: "Authorization needed", zh: "待授权")
        case .installing: text(copy, en: "Installing", zh: "安装中")
        case .uninstalling: text(copy, en: "Uninstalling", zh: "卸载中")
        case .waitingCodexTrust: text(copy, en: "Waiting for Codex trust", zh: "等待 Codex 信任")
        case .readyForFirstRun: text(copy, en: "Ready · awaiting first turn", zh: "已就绪 · 等待首次任务")
        case .connected: text(copy, en: "Connected", zh: "已连接")
        case .paused: text(copy, en: "Paused", zh: "已暂停")
        case .needsUpgrade: text(copy, en: "Upgrade needed", zh: "需升级")
        case .needsRepair: text(copy, en: "Repair needed", zh: "需修复")
        }
    }

    private func agentHealthStyle(_ health: AgentIntegrationHealth) -> SettingsPillStyle {
        switch health {
        case .connected: .success
        case .pendingAuthorization, .installing, .uninstalling, .waitingCodexTrust, .readyForFirstRun, .needsUpgrade: .warning
        case .needsRepair: .warning
        case .notInstalled, .paused: .neutral
        }
    }

    private func agentHealthDetail(
        _ health: AgentIntegrationHealth,
        provider: AgentHookInstaller.Provider,
        copy: AppCopy
    ) -> String {
        switch health {
        case .notInstalled:
            return text(copy, en: "No TodoPilot hook is installed.", zh: "尚未安装 TodoPilot Hook。")
        case .pendingAuthorization:
            return text(copy, en: "Your confirmation is required before TodoPilot edits the user hook file.", zh: "TodoPilot 修改用户级 Hook 配置前需要你的确认。")
        case .installing:
            return text(copy, en: "Backing up and updating the user hook configuration.", zh: "正在备份并更新用户级 Hook 配置。")
        case .uninstalling:
            return text(copy, en: "Only TodoPilot-owned entries are being removed.", zh: "只会移除 TodoPilot 自有条目。")
        case .waitingCodexTrust:
            return text(
                copy,
                en: "Codex app: open Settings > Hooks > User configuration and trust both pending items. Codex CLI: enter /hooks. Then return here.",
                zh: "Codex 桌面版：打开“设置 → 钩子 → 用户配置”，分别信任两项待审核内容；Codex CLI 可输入 /hooks。完成后回到这里。"
            )
        case .readyForFirstRun:
            if provider == .codex {
                return text(
                    copy,
                    en: "The local receiver is ready. Create a new Codex task so hooks reload, then submit one prompt. Connected appears only after TodoPilot receives it.",
                    zh: "本地接收器已就绪。请新建一个 Codex 任务以重新加载 Hook，再提交一句请求；TodoPilot 实际收到后才会变为“已连接”。"
                )
            }
            return text(
                copy,
                en: "The local receiver is ready. Submit a new root turn in \(provider.displayName); this changes to Connected only after TodoPilot receives it.",
                zh: "本地接收器已就绪。请在 \(provider.displayName) 提交一个新的根回合；TodoPilot 实际收到后才会变为“已连接”。"
            )
        case .connected:
            return text(copy, en: "A real hook event has reached TodoPilot on this Mac.", zh: "TodoPilot 已在本机收到真实 Hook 事件。")
        case .paused:
            return text(copy, en: "The hook remains installed, but monitoring is paused by a switch.", zh: "Hook 仍保留，但监控已被开关暂停。")
        case .needsUpgrade:
            return text(copy, en: "The detected Agent version does not expose the required lifecycle events.", zh: "检测到的 Agent 版本不支持所需生命周期事件。")
        case .needsRepair:
            return text(copy, en: "The hook file, helper, or local receiver is unavailable; run Repair.", zh: "Hook 配置、Helper 或本地接收器不可用，请点击修复。")
        }
    }

    private func agentProviderSubtitle(_ provider: AgentHookInstaller.Provider, copy: AppCopy) -> String {
        switch provider {
        case .claudeCode:
            text(copy, en: "UserPromptSubmit / Stop / StopFailure / SessionEnd", zh: "用户级 UserPromptSubmit / Stop / StopFailure / SessionEnd")
        case .codex:
            text(copy, en: "UserPromptSubmit / Stop · requires trust in Codex", zh: "UserPromptSubmit / Stop · 需在 Codex 中信任")
        case .cursor:
            text(copy, en: "beforeSubmitPrompt / stop / sessionEnd", zh: "用户级 beforeSubmitPrompt / stop / sessionEnd")
        }
    }

    private func agentIntegrationMessage(_ code: String, copy: AppCopy) -> String {
        switch code {
        case "installing": text(copy, en: "Installing local hooks…", zh: "正在安装本机 Hook…")
        case "uninstalling": text(copy, en: "Removing TodoPilot-owned hooks…", zh: "正在移除 TodoPilot 自有 Hook…")
        case "installed": text(copy, en: "Hooks installed. Monitoring is local and active.", zh: "Hook 已安装，本机监控已开启。")
        case "codex_trust_required": text(
            copy,
            en: "Installed. In the Codex app, open Settings > Hooks > User configuration and trust both pending items. In Codex CLI, enter /hooks.",
            zh: "已安装。Codex 桌面版请打开“设置 → 钩子 → 用户配置”，分别信任两项待审核内容；Codex CLI 可输入 /hooks。"
        )
        case "codex_trusted_waiting_event": text(copy, en: "Trust confirmation recorded. Create a new Codex task and submit one prompt to verify the real hook path.", zh: "已记录信任确认；请新建一个 Codex 任务并提交一句请求，验证真实 Hook 链路。")
        case "bridge_testing": text(copy, en: "Testing TodoPilot's local receiver…", zh: "正在测试 TodoPilot 本地接收器…")
        case "bridge_test_passed": text(copy, en: "TodoPilot's local receiver is available. This does not verify Codex trust; submit a new Codex turn next.", zh: "TodoPilot 本地接收器可用；这不代表 Codex 已信任，请继续提交一个新的 Codex 回合。")
        case "bridge_test_failed": text(copy, en: "Local bridge is unavailable. Enable monitoring or repair the hooks.", zh: "本地 Bridge 不可用，请启用监控或修复 Hook。")
        case "authorization_required": text(copy, en: "Install at least one provider hook before enabling monitoring.", zh: "启用监控前，请先安装至少一个 Provider Hook。")
        case "uninstalled": text(copy, en: "TodoPilot-owned hooks were removed.", zh: "TodoPilot 自有 Hook 已移除。")
        case "install_failed": text(copy, en: "Installation failed. Existing configuration was not overwritten.", zh: "安装失败，现有配置未被覆盖。")
        case "upgrade_required": text(copy, en: "Upgrade this Agent before installing TodoPilot hooks.", zh: "请先升级 Agent，再安装 TodoPilot Hook。")
        case "uninstall_failed": text(copy, en: "Uninstall failed. Check the provider configuration and retry.", zh: "卸载失败，请检查 Provider 配置后重试。")
        default: code
        }
    }

    private func exportMarkdown(_ copy: AppCopy) {
        let export = environment.dataExporter.exportMarkdown(tasks: environment.taskStore.tasks)
        copyToPasteboard(export)
        exportMessage = copy.copiedTasks(environment.taskStore.tasks.count)
        environment.logger.info("tasks_exported", metadata: [
            "count": .numeric(environment.taskStore.tasks.count),
            "format": .publicText("markdown")
        ])
    }

    private func exportCSV(_ copy: AppCopy) {
        let export = environment.dataExporter.exportCSV(tasks: environment.taskStore.tasks)
        copyToPasteboard(export)
        exportMessage = text(
            copy,
            en: "Copied CSV for \(environment.taskStore.tasks.count) tasks.",
            zh: "已复制 \(environment.taskStore.tasks.count) 个任务的 CSV。"
        )
        environment.logger.info("tasks_exported", metadata: [
            "count": .numeric(environment.taskStore.tasks.count),
            "format": .publicText("csv")
        ])
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func beginCaptureHotKeyEditing(_ copy: AppCopy) {
        environment.suspendCaptureHotKeyForEditing()
        isRecordingCaptureHotKey = true
        shortcutMessage = copy.shortcutPressNew
    }

    private func cancelCaptureHotKeyEditing() {
        isRecordingCaptureHotKey = false
        shortcutMessage = nil
        environment.restoreCaptureHotKeyAfterEditing()
    }

    private func applyCaptureHotKey(_ hotKey: CaptureHotKey, copy: AppCopy) {
        if environment.updateCaptureHotKey(hotKey) {
            isRecordingCaptureHotKey = false
            shortcutMessage = copy.shortcutUpdated
        } else {
            shortcutMessage = environment.hotKeyRegistrationError
                ?? copy.shortcutAlreadyInUse(hotKey.normalizedToPreset.readableShortcutTitle)
        }
    }
}

private struct ShortcutRecorderHost: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (CaptureHotKey) -> Void
    let onInvalid: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        ShortcutRecorderNSView()
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onInvalid = onInvalid
        nsView.onCancel = onCancel
        nsView.setRecording(isRecording)

        guard isRecording else {
            return
        }

        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class ShortcutRecorderNSView: NSView {
    private var isRecording = false
    private var localMonitor: Any?
    var onCapture: ((CaptureHotKey) -> Void)?
    var onInvalid: (() -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    deinit {
        removeLocalMonitor()
    }

    func setRecording(_ recording: Bool) {
        guard isRecording != recording else {
            return
        }

        isRecording = recording
        if recording {
            installLocalMonitor()
        } else {
            removeLocalMonitor()
        }
    }

    override func keyDown(with event: NSEvent) {
        if !handleKeyEvent(event) {
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleKeyEvent(event)
    }

    private func installLocalMonitor() {
        removeLocalMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else {
                return event
            }
            return self.handleKeyEvent(event) ? nil : event
        }
    }

    private func removeLocalMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard isRecording else {
            return false
        }

        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return true
        }

        guard let hotKey = ShortcutRecorderNSView.makeCaptureHotKey(from: event) else {
            NSSound.beep()
            onInvalid?()
            return true
        }

        onCapture?(hotKey)
        return true
    }

    private static func makeCaptureHotKey(from event: NSEvent) -> CaptureHotKey? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let usesPrimaryModifier = flags.contains(.command) || flags.contains(.option) || flags.contains(.control)
        guard usesPrimaryModifier, !modifierOnlyKeyCodes.contains(Int(event.keyCode)) else {
            return nil
        }

        var carbonModifiers: UInt32 = 0
        if flags.contains(.command) {
            carbonModifiers |= UInt32(cmdKey)
        }
        if flags.contains(.control) {
            carbonModifiers |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            carbonModifiers |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            carbonModifiers |= UInt32(shiftKey)
        }

        let label = keyLabel(for: event)
        guard !label.isEmpty else {
            return nil
        }

        return .custom(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: carbonModifiers,
            keyLabel: label
        )
    }

    private static let modifierOnlyKeyCodes: Set<Int> = [
        Int(kVK_Command),
        Int(kVK_RightCommand),
        Int(kVK_Shift),
        Int(kVK_RightShift),
        Int(kVK_Option),
        Int(kVK_RightOption),
        Int(kVK_Control),
        Int(kVK_RightControl),
        Int(kVK_Function)
    ]

    private static func keyLabel(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space:
            return "space"
        case kVK_Return:
            return "return"
        case kVK_Tab:
            return "tab"
        case kVK_Delete:
            return "delete"
        case kVK_ForwardDelete:
            return "forward delete"
        case kVK_Home:
            return "home"
        case kVK_End:
            return "end"
        case kVK_PageUp:
            return "page up"
        case kVK_PageDown:
            return "page down"
        case kVK_LeftArrow:
            return "left"
        case kVK_RightArrow:
            return "right"
        case kVK_UpArrow:
            return "up"
        case kVK_DownArrow:
            return "down"
        default:
            if let functionKey = functionKeyLabel(for: Int(event.keyCode)) {
                return functionKey
            }
            let label = event.charactersIgnoringModifiers?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ?? ""
            return label
        }
    }

    private static func functionKeyLabel(for keyCode: Int) -> String? {
        let functionKeys: [Int: String] = [
            kVK_F1: "F1",
            kVK_F2: "F2",
            kVK_F3: "F3",
            kVK_F4: "F4",
            kVK_F5: "F5",
            kVK_F6: "F6",
            kVK_F7: "F7",
            kVK_F8: "F8",
            kVK_F9: "F9",
            kVK_F10: "F10",
            kVK_F11: "F11",
            kVK_F12: "F12",
            kVK_F13: "F13",
            kVK_F14: "F14",
            kVK_F15: "F15",
            kVK_F16: "F16",
            kVK_F17: "F17",
            kVK_F18: "F18",
            kVK_F19: "F19",
            kVK_F20: "F20"
        ]
        return functionKeys[keyCode]
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case privacy
    case flight
    case agents
    case shortcuts
    case export

    var id: String { rawValue }

    static let visibleCases: [SettingsPane] = [.general, .privacy, .flight, .agents, .shortcuts, .export]

    var systemImage: String {
        switch self {
        case .general:
            "slider.horizontal.3"
        case .privacy:
            "shield"
        case .flight:
            "airplane"
        case .agents:
            "terminal"
        case .shortcuts:
            "keyboard"
        case .export:
            "arrow.down.to.line.compact"
        }
    }

    func title(_ copy: AppCopy) -> String {
        switch self {
        case .general:
            text(copy, en: "General", zh: "通用")
        case .privacy:
            copy.privacy
        case .flight:
            copy.flightReminders
        case .agents:
            text(copy, en: "Agents", zh: "Agents")
        case .shortcuts:
            copy.shortcut
        case .export:
            text(copy, en: "Export", zh: "导出")
        }
    }
}

private enum SettingsTheme {
    static let appBackground = Color(red: 0.98, green: 0.985, blue: 0.985)
    static let paneBackground = Color(red: 0.965, green: 0.975, blue: 0.975)
    static let selectedFill = Color(red: 0.91, green: 0.94, blue: 1.0)
    static let hoverFill = Color.black.opacity(0.035)
    static let divider = Color.black.opacity(0.075)
    static let rule = Color.black.opacity(0.065)
    static let primaryText = Color(red: 0.13, green: 0.14, blue: 0.16)
    static let secondaryText = Color(red: 0.48, green: 0.51, blue: 0.56)
    static let mutedText = Color(red: 0.58, green: 0.61, blue: 0.66)
    static let accent = Color(red: 0.18, green: 0.42, blue: 1)
    static let destructive = Color(red: 1.0, green: 0.30, blue: 0.31)
    static let success = Color(red: 0.13, green: 0.79, blue: 0.59)
}

private struct SettingsPaneSidebar: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Binding var selectedSection: SettingsPane

    var body: some View {
        let copy = environment.copy

        VStack(alignment: .leading, spacing: 10) {
            ForEach(SettingsPane.visibleCases) { section in
                SettingsPaneButton(
                    section: section,
                    title: section.title(copy),
                    isSelected: section == selectedSection
                ) {
                    selectedSection = section
                }
            }

            Spacer()
        }
        .padding(.top, 28)
        .padding(.horizontal, 16)
        .frame(width: 210)
        .background(SettingsTheme.paneBackground)
    }
}

private struct SettingsPaneButton: View {
    let section: SettingsPane
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)

                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? SettingsTheme.accent : SettingsTheme.secondaryText)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
    }

    private var background: Color {
        if isSelected {
            return SettingsTheme.selectedFill
        }
        if isHovering {
            return SettingsTheme.hoverFill
        }
        return .clear
    }
}

private struct SettingsPaneTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 25, weight: .bold))
            .foregroundStyle(SettingsTheme.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsRows<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsRow<Accessory: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(SettingsTheme.primaryText)
                    .lineLimit(2)

                Text(subtitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SettingsTheme.secondaryText)
                    .lineLimit(3)
            }
            .layoutPriority(1)

            Spacer(minLength: 16)

            accessory()
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
    }
}

private struct SettingsRule: View {
    var body: some View {
        Rectangle()
            .fill(SettingsTheme.rule)
            .frame(height: 1)
    }
}

private struct SettingsInfoBanner: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 22)

            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(SettingsTheme.accent)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsTheme.selectedFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private enum SettingsPillStyle {
    case blue
    case success
    case warning
    case neutral

    var foreground: Color {
        switch self {
        case .blue:
            SettingsTheme.accent
        case .success:
            SettingsTheme.success
        case .warning:
            SettingsTheme.destructive
        case .neutral:
            SettingsTheme.secondaryText
        }
    }

    var background: Color {
        switch self {
        case .blue:
            SettingsTheme.accent.opacity(0.11)
        case .success:
            SettingsTheme.success.opacity(0.12)
        case .warning:
            SettingsTheme.destructive.opacity(0.10)
        case .neutral:
            Color.black.opacity(0.055)
        }
    }
}

private struct SettingsStatusPill: View {
    let title: String
    var style: SettingsPillStyle

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(style.foreground)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(style.background, in: Capsule())
    }
}

private struct SettingsMenuOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String

    var id: Value { value }
}

private struct SettingsMenuButton<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [SettingsMenuOption<Value>]

    var body: some View {
        SettingsPopupButton(selection: $selection, options: options)
            .frame(minWidth: 150, minHeight: 34)
        .accessibilityLabel(selectedTitle)
    }

    private var selectedTitle: String {
        options.first { $0.value == selection }?.title ?? ""
    }
}

private struct SettingsPopupButton<Value: Hashable>: NSViewRepresentable {
    @Binding var selection: Value
    let options: [SettingsMenuOption<Value>]

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, options: options)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        button.controlSize = .large
        button.bezelStyle = .rounded
        button.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        context.coordinator.configure(button)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.options = options
        context.coordinator.configure(button)
    }

    final class Coordinator: NSObject {
        var selection: Binding<Value>
        var options: [SettingsMenuOption<Value>]
        weak var button: NSPopUpButton?

        init(selection: Binding<Value>, options: [SettingsMenuOption<Value>]) {
            self.selection = selection
            self.options = options
        }

        func configure(_ button: NSPopUpButton) {
            self.button = button
            let selectedIndex = options.firstIndex { $0.value == selection.wrappedValue } ?? 0
            let titles = options.map(\.title)
            let existingTitles = button.itemArray.map(\.title)
            if existingTitles != titles {
                button.removeAllItems()
                button.addItems(withTitles: titles)
            }
            for (index, item) in button.itemArray.enumerated() {
                item.target = self
                item.action = #selector(menuItemSelected(_:))
                item.tag = index
            }
            if !options.isEmpty, button.indexOfSelectedItem != selectedIndex {
                button.selectItem(at: selectedIndex)
            }
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            selectOption(at: index)
        }

        @objc func menuItemSelected(_ sender: NSMenuItem) {
            selectOption(at: sender.tag)
        }

        private func selectOption(at index: Int) {
            guard options.indices.contains(index) else {
                return
            }
            button?.selectItem(at: index)
            let value = options[index].value
            if selection.wrappedValue != value {
                selection.wrappedValue = value
            }
        }
    }
}

private struct SettingsThemeChip: View {
    let title: String
    let isSelected: Bool
    var isEnabled: Bool = true

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(isEnabled ? (isSelected ? SettingsTheme.accent : Color(red: 0.98, green: 0.65, blue: 0.05)) : SettingsTheme.mutedText)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                isSelected ? SettingsTheme.selectedFill : Color.white.opacity(isEnabled ? 0.84 : 0.50),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? SettingsTheme.accent.opacity(0.24) : SettingsTheme.rule, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.55)
    }
}

private struct SettingsIntegrationRow: View {
    let title: String
    let status: String
    let statusStyle: SettingsPillStyle
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(action == nil ? SettingsTheme.primaryText.opacity(0.92) : SettingsTheme.primaryText)

            Spacer()

            SettingsStatusPill(title: status, style: statusStyle)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderless)
                    .font(.system(size: 14, weight: .bold))
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(SettingsTheme.secondaryText.opacity(0.58))
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .background(Color.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(SettingsTheme.rule, lineWidth: 1)
        )
    }
}

private func text(_ copy: AppCopy, en: String, zh: String) -> String {
    switch copy.language {
    case .english:
        en
    case .chinese:
        zh
    }
}

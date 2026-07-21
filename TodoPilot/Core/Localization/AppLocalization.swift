import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            "English"
        case .chinese:
            "中文"
        }
    }
}

struct AppCopy {
    let language: AppLanguage

    var today: String { text(en: "Today", zh: "今日") }
    var tomorrow: String { text(en: "Tomorrow", zh: "明天") }
    var capture: String { text(en: "Capture", zh: "捕获") }
    var settings: String { text(en: "Settings", zh: "设置") }
    var diagnostics: String { text(en: "Diagnostics", zh: "诊断") }
    var debug: String { text(en: "Debug", zh: "调试") }
    var showTodoPilot: String { text(en: "Show TodoPilot", zh: "显示 TodoPilot") }
    var quit: String { text(en: "Quit", zh: "退出") }
    var openTodayList: String { text(en: "Open Today List", zh: "打开今日列表") }
    var openDiagnostics: String { text(en: "Open Diagnostics", zh: "打开诊断") }
    var taskCaptureTodayFocus: String { text(en: "Task capture · Today focus", zh: "任务捕获 · 今日专注") }
    var todayTodo: String { text(en: "Today Todo", zh: "今日待办") }
    var allTasks: String { text(en: "All", zh: "全部") }
    var manualTasks: String { text(en: "Self-created", zh: "自建") }
    var history: String { text(en: "History", zh: "历史记录") }
    var historyDisplayLimitNote: String { text(en: "(Latest 100 only)", zh: "（仅显示近100条）") }
    var frameCapture: String { text(en: "Frame Capture", zh: "框选捕获") }
    var demoFlight: String { text(en: "Demo Flight", zh: "演示飞行") }
    var byPriority: String { text(en: "By priority", zh: "按优先级") }
    var byDueTime: String { text(en: "By due time", zh: "按截止时间") }
    var byCreatedTime: String { text(en: "By created time", zh: "按创建时间") }
    var viewAll: String { text(en: "View All", zh: "查看全部") }
    var thisWeek: String { text(en: "This week", zh: "本周") }
    var localCalendar: String { text(en: "Local Calendar", zh: "本机日历") }
    var fromCalendar: String { text(en: "From Calendar", zh: "来自日历") }
    var localAutoRefresh: String { text(en: "Local auto refresh", zh: "本地自动刷新") }
    var localCalendarSyncTitle: String { text(en: "Local Calendar Sync", zh: "本机日历同步") }
    var autoImportEnabled: String { text(en: "Auto-import on app open and every 10 minutes", zh: "启动应用和定时自动获取") }
    var fetchTasks: String { text(en: "Fetch Tasks", zh: "获取任务") }
    var fetchFromCalendar: String { text(en: "Fetch from Calendar", zh: "从日历获取") }
    var readsLocalCalendarOnly: String { text(en: "Reads local calendar and reminders only", zh: "只读取本机日历/提醒") }
    var lastAutoRefresh: String { text(en: "Last fetch", zh: "上次获取") }
    var allDay: String { text(en: "All day", zh: "全天") }
    var expand: String { text(en: "Expand", zh: "展开") }
    var collapse: String { text(en: "Collapse", zh: "收起") }
    var ignore: String { text(en: "Ignore", zh: "忽略") }
    var reminderOnly: String { text(en: "Reminder only", zh: "仅提醒") }
    var added: String { text(en: "Added", zh: "已加入") }
    var ignored: String { text(en: "Ignored", zh: "已忽略") }
    var reminderOnlyMarked: String { text(en: "Reminder-only", zh: "仅提醒") }
    var handledCalendarEventsSkipped: String {
        text(
            en: "Repeated fetches skip items already added or ignored.",
            zh: "重复获取会跳过已加入和已忽略的日历/提醒项。"
        )
    }
    var calendarPermissionLabel: String { text(en: "Calendar", zh: "日历") }
    var remindersPermissionLabel: String { text(en: "Reminders", zh: "提醒") }
    var permissionGranted: String { text(en: "Allowed", zh: "已授权") }
    var permissionNeedsGrant: String { text(en: "Needs grant", zh: "待授权") }
    var permissionDeniedShort: String { text(en: "Off", zh: "未开启") }
    var permissionRestrictedShort: String { text(en: "Restricted", zh: "受限") }
    var openCalendarPrivacySettings: String { text(en: "Open Calendar Privacy", zh: "打开日历权限") }
    var openRemindersPrivacySettings: String { text(en: "Open Reminders Privacy", zh: "打开提醒权限") }
    var calendarPrivacySettingsOpened: String {
        text(en: "System Settings opened. Allow TodoPilot under Calendar.", zh: "已打开系统设置，请在日历中允许 TodoPilot。")
    }
    var remindersPrivacySettingsOpened: String {
        text(en: "System Settings opened. Allow TodoPilot under Reminders.", zh: "已打开系统设置，请在提醒事项中允许 TodoPilot。")
    }
    var calendarNeedsPermission: String {
        text(en: "Fetch once to grant Calendar and Reminders access.", zh: "点击获取后授权读取日历和提醒事项。")
    }
    var calendarEventsNeedPermission: String {
        text(en: "Fetch once to grant Calendar access.", zh: "点击获取后授权读取日历。")
    }
    var remindersNeedPermission: String {
        text(en: "Fetch once to grant Reminders access.", zh: "点击获取后授权读取提醒事项。")
    }
    var calendarAccessDenied: String {
        text(en: "Calendar or Reminders access is off. Enable it in System Settings.", zh: "日历或提醒事项访问未开启，可在系统设置中允许。")
    }
    var calendarEventsAccessDenied: String {
        text(en: "Calendar access is off. Enable it in System Settings.", zh: "日历访问未开启，可在系统设置中允许。")
    }
    var remindersAccessDenied: String {
        text(en: "Reminders access is off. Enable it in System Settings.", zh: "提醒事项访问未开启，可在系统设置中允许。")
    }
    var noCalendarCandidatesCalendarOnly: String {
        text(en: "No new calendar candidates for today. Reminders access is not on.", zh: "今天没有新的日历候选；提醒事项访问未开启。")
    }
    var noCalendarCandidatesRemindersOnly: String {
        text(en: "No new reminder candidates for today. Calendar access is not on.", zh: "今天没有新的提醒候选；日历访问未开启。")
    }
    var noCalendarCandidates: String {
        text(en: "No new calendar or reminder candidates for today.", zh: "今天没有新的日历或提醒候选。")
    }
    var calendarFetchFailed: String {
        text(en: "Calendar fetch failed. Please try again.", zh: "日历获取失败，请稍后重试。")
    }
    var add: String { text(en: "Add", zh: "添加") }
    var newTask: String { text(en: "New Task", zh: "新建任务") }
    var cancel: String { text(en: "Cancel", zh: "取消") }
    var copy: String { text(en: "Copy", zh: "复制") }
    var copied: String { text(en: "Copied", zh: "已复制") }
    var clear: String { text(en: "Clear", zh: "清空") }
    var noOpenTasks: String { text(en: "No pending tasks here.", zh: "这里暂无待办任务。") }
    var noManualTasks: String { text(en: "No self-created pending tasks.", zh: "暂无自建待办任务。") }
    var noLocalCalendarTasks: String { text(en: "No local calendar tasks. Fetch once or wait for auto-import.", zh: "暂无本机日历任务，可点击获取任务或等待自动获取。") }
    var undo: String { text(en: "Undo", zh: "撤销") }
    var delete: String { text(en: "Delete", zh: "删除") }
    var edit: String { text(en: "Edit", zh: "编辑") }
    var save: String { text(en: "Save", zh: "保存") }
    var restore: String { text(en: "Restore", zh: "恢复") }
    var close: String { text(en: "Close", zh: "关闭") }
    var source: String { text(en: "Source", zh: "来源") }
    var capturedSource: String { text(en: "Captured", zh: "捕获") }
    var capturedSourceHelp: String { text(en: "Created from OCR or pasted capture text.", zh: "由 OCR 或粘贴捕获文本创建。") }
    var snooze: String { text(en: "Snooze", zh: "稍后提醒") }
    var snooze10Minutes: String { text(en: "10 min later", zh: "10 分钟后") }
    var snoozed: String { text(en: "Snoozed", zh: "已稍后提醒") }

    var nextThing: String { text(en: "Next Thing", zh: "下一件事") }
    var dueSoon: String { text(en: "Due Soon", zh: "即将到期") }
    var overdue: String { text(en: "Overdue", zh: "已逾期") }
    var upcoming: String { text(en: "Upcoming", zh: "稍后") }
    var done: String { text(en: "Done", zh: "已完成") }
    var later: String { text(en: "Later", zh: "稍后") }
    var deleted: String { text(en: "Deleted", zh: "已删除") }
    var reviewNextMilestone: String { text(en: "Review next TodoPilot milestone", zh: "复盘 TodoPilot 下一阶段里程碑") }

    var capturePipeline: String { text(en: "Capture pipeline", zh: "捕获流程") }
    var captureNeedsAttention: String { text(en: "Check the issue below, then retry capture.", zh: "请处理下面的问题后重试捕获。") }
    var ocr: String { text(en: "OCR", zh: "OCR") }
    var confirm: String { text(en: "Confirm", zh: "确认") }
    var startCapture: String { text(en: "Start Capture", zh: "开始框选") }
    var selecting: String { text(en: "Selecting", zh: "框选中") }
    var dragToSelectScreenArea: String { text(en: "Drag to select screen area", zh: "拖拽框选屏幕区域") }
    var escToCancel: String { text(en: "Esc to cancel", zh: "Esc 取消") }
    var cancelWithEscape: String { text(en: "Cancel (Esc)", zh: "取消 (Esc)") }
    var reading: String { text(en: "Reading", zh: "识别中") }
    var pasteText: String { text(en: "Paste Text", zh: "粘贴文本") }
    var openPrivacySettings: String { text(en: "Open Privacy Settings", zh: "打开隐私设置") }
    var reviewText: String { text(en: "Review Text", zh: "检查文本") }
    var reviewOCRText: String { text(en: "Review OCR Text", zh: "检查 OCR 文本") }
    var reviewPastedText: String { text(en: "Review Pasted Text", zh: "检查粘贴文本") }
    var ocrRawText: String { text(en: "OCR text", zh: "OCR 原文") }
    var localOCRBadge: String { text(en: "Local OCR", zh: "本地识别") }
    var localTextBadge: String { text(en: "Local text", zh: "本地文本") }
    var useTextAsTask: String { text(en: "Review Text as Task", zh: "用文本确认任务") }
    var textReviewSummary: String {
        text(
            en: "Text reviewed locally. Confirm before adding it to Today.",
            zh: "文本已在本地检查。加入今日前请确认。"
        )
    }
    var pasteTextHelp: String {
        text(
            en: "Use this fallback when OCR fails. The text stays on this Mac.",
            zh: "OCR 失败时可使用此兜底，文本始终保留在本机。"
        )
    }
    var noTextFound: String {
        text(
            en: "No text was found in the selected region. Use Paste Text to continue.",
            zh: "所选区域未识别到文字。可以使用粘贴文本继续。"
        )
    }
    var ocrTimeout: String {
        text(
            en: "OCR did not finish in time. Use Paste Text to continue without waiting.",
            zh: "OCR 未及时完成。可以使用粘贴文本继续。"
        )
    }

    var confirmTasks: String { text(en: "Confirm Tasks", zh: "确认任务") }
    var noClearTask: String { text(en: "No clear task was recognized", zh: "未识别到明确任务") }
    var noClearTaskHelp: String {
        text(
            en: "You can create one manually or close this result. Nothing is added to Today until you confirm.",
            zh: "你可以手动创建任务或关闭结果。确认前不会加入今日列表。"
        )
    }
    var createManualTask: String { text(en: "Create Manual Task", zh: "手动创建任务") }
    var notATask: String { text(en: "Not a Task", zh: "不是任务") }
    var recognitionError: String { text(en: "Recognition Error", zh: "识别错误") }
    var mergeSimilar: String { text(en: "Merge Similar", zh: "合并相似") }
    var addToToday: String { text(en: "Add to Today", zh: "加入今日") }
    var discardRecognizedTasks: String { text(en: "Discard recognized tasks?", zh: "丢弃识别到的任务？") }
    var discard: String { text(en: "Discard", zh: "丢弃") }
    var keepEditing: String { text(en: "Keep Editing", zh: "继续编辑") }
    var taskConfirmationSummary: String {
        text(en: "Text has been checked locally. Review before adding to Today.", zh: "文本已在本地检查。加入今日前请确认。")
    }
    var manualFallbackSummary: String {
        text(en: "Manual text fallback. Review before adding tasks.", zh: "手动文本兜底。加入任务前请先确认。")
    }
    var lowConfidenceSummary: String {
        text(en: "Some OCR blocks had low confidence. Review highlighted tasks carefully.", zh: "部分 OCR 内容置信度较低，请仔细检查标记任务。")
    }
    var title: String { text(en: "Title", zh: "标题") }
    var editTask: String { text(en: "Edit Task", zh: "编辑任务") }
    var priority: String { text(en: "Priority", zh: "优先级") }
    var description: String { text(en: "Description", zh: "描述") }
    var taskDescriptionPlaceholder: String { text(en: "Add task notes if needed", zh: "可补充任务说明") }
    var due: String { text(en: "Due", zh: "截止") }
    var chooseDueDateTime: String { text(en: "Choose date and time", zh: "选择日期和时间") }
    var taskColumn: String { text(en: "Task", zh: "任务") }
    var priorityColumn: String { text(en: "Priority", zh: "优先级") }
    var dueColumn: String { text(en: "Due", zh: "截止时间") }
    var actionsColumn: String { text(en: "Actions", zh: "操作") }
    var recentTodo: String { text(en: "Recent Todo", zh: "最近待办") }
    var sourceDedupedNote: String {
        text(en: "Deduped by source ID. Repeated fetches will not add duplicates.", zh: "已按来源 ID 去重，重复获取不会重复加入。")
    }
    var noDueDate: String { text(en: "No due date", zh: "无截止时间") }
    var tags: String { text(en: "Tags", zh: "标签") }
    var tagInputPlaceholder: String { text(en: "Choose or enter tags, press Return to add", zh: "选择或输入标签，回车添加") }
    var needsReview: String { text(en: "Needs review", zh: "需要检查") }
    var remove: String { text(en: "Remove", zh: "移除") }
    var editing: String { text(en: "Editing", zh: "编辑中") }
    var candidateCollapsedHelp: String {
        text(en: "Click Edit to adjust title, priority, and due time", zh: "点击编辑可调整标题、优先级和截止时间")
    }
    var candidateEditingHelp: String {
        text(en: "Editing title, description, and due time", zh: "正在编辑，可确认标题、描述和截止时间")
    }

    var languageSection: String { text(en: "Language", zh: "语言") }
    var appLanguage: String { text(en: "App language", zh: "应用语言") }
    var languageSaved: String { text(en: "Language saved.", zh: "语言已保存。") }
    var captureSection: String { text(en: "Capture", zh: "捕获") }
    var shortcut: String { text(en: "Shortcut", zh: "快捷键") }
    var shortcutUpdated: String { text(en: "Shortcut updated.", zh: "快捷键已更新。") }
    var shortcutInUse: String { text(en: "Shortcut is already in use.", zh: "快捷键已被占用。") }
    var shortcutChange: String { text(en: "Change", zh: "修改") }
    var shortcutDefault: String { text(en: "Default", zh: "默认") }
    var shortcutListening: String { text(en: "Listening", zh: "等待按键") }
    var shortcutPressNew: String { text(en: "Press the new shortcut now.", zh: "现在按下新的快捷键。") }
    var shortcutInvalidCombination: String {
        text(
            en: "Use Command, Option, or Control plus one key.",
            zh: "请使用 Command、Option 或 Control 加一个按键。"
        )
    }
    var shortcutHandlerUnavailable: String {
        text(
            en: "Unable to enable global shortcuts. Restart TodoPilot and try again.",
            zh: "无法启用全局快捷键。请重启 TodoPilot 后再试。"
        )
    }
    var screenCaptureEnabled: String { text(en: "Screen capture enabled", zh: "启用屏幕捕获") }
    var reminders: String { text(en: "Reminders", zh: "提醒") }
    var flightReminders: String { text(en: "Flight reminders", zh: "飞行提醒") }
    var muteFlightReminders: String { text(en: "Mute Flight Reminders", zh: "静音飞行提醒") }
    var statusIsland: String { text(en: "Status island", zh: "状态岛") }
    var privacy: String { text(en: "Privacy", zh: "隐私") }
    var screenshotUpload: String { text(en: "Screenshot upload", zh: "截图上传") }
    var off: String { text(en: "Off", zh: "关闭") }
    var ocrLogging: String { text(en: "OCR logging", zh: "OCR 日志") }
    var taskTextLogging: String { text(en: "Task text logging", zh: "任务文本日志") }
    var redacted: String { text(en: "Redacted", zh: "已脱敏") }
    var sensitiveConfig: String { text(en: "Sensitive config", zh: "敏感配置") }
    var keychain: String { text(en: "Keychain", zh: "钥匙串") }
    var data: String { text(en: "Data", zh: "数据") }
    var copyMarkdownExport: String { text(en: "Copy Markdown Export", zh: "复制 Markdown 导出") }
    var clearLocalTasks: String { text(en: "Clear Local Tasks", zh: "清空本地任务") }
    var clearAllLocalTasks: String { text(en: "Clear all local tasks?", zh: "清空所有本地任务？") }
    var clearButton: String { text(en: "Clear", zh: "清空") }
    var clearLocalTasksHelp: String {
        text(en: "This removes the local task list in this build. It does not affect cloud data.", zh: "这会移除此版本中的本地任务列表，不影响云端数据。")
    }

    var diagnosticsSubtitle: String { text(en: "Privacy-safe internal status", zh: "隐私安全的内部状态") }
    var diagnosticsPrivacyNote: String {
        text(
            en: "Diagnostics never include task bodies, OCR raw text, screenshot paths, API keys, tokens, or user identifiers.",
            zh: "诊断信息不会包含任务正文、OCR 原文、截图路径、API Key、token 或用户标识。"
        )
    }
    var openTasks: String { text(en: "Open tasks", zh: "未完成任务") }
    var doneTasks: String { text(en: "Done tasks", zh: "已完成任务") }
    var deletedTasks: String { text(en: "Deleted tasks", zh: "已删除任务") }
    var enabled: String { text(en: "enabled", zh: "已启用") }
    var disabled: String { text(en: "disabled", zh: "已关闭") }
    var privacyLogging: String { text(en: "Privacy logging", zh: "隐私日志") }
    var metadataKeysOnly: String { text(en: "metadata_keys_only", zh: "仅记录元数据键") }
    var localSchema: String { text(en: "Local schema", zh: "本地 schema") }

    func openDoneSummary(open: Int, done: Int) -> String {
        text(en: "\(open) open, \(done) done", zh: "\(open) 个未完成，\(done) 个已完成")
    }

    func doneCount(_ count: Int) -> String {
        text(en: "Done (\(count))", zh: "已完成（\(count)）")
    }

    func completedTask(_ title: String) -> String {
        text(en: "Completed \(title)", zh: "已完成 \(title)")
    }

    func deletedTask(_ title: String) -> String {
        text(en: "Deleted \(title)", zh: "已删除 \(title)")
    }

    func deletedAt(_ relativeDateText: String) -> String {
        text(en: "Deleted \(relativeDateText)", zh: "删除于 \(relativeDateText)")
    }

    func copiedTasks(_ count: Int) -> String {
        text(en: "Copied \(count) tasks.", zh: "已复制 \(count) 个任务。")
    }

    func shortcutAlreadyInUse(_ shortcut: String) -> String {
        text(
            en: "\(shortcut) is already used by another app or system shortcut.",
            zh: "快捷键“\(shortcut)”已被其他应用或系统快捷键占用。"
        )
    }

    func calendarCandidateCount(_ count: Int) -> String {
        text(en: "Candidates \(count)", zh: "候选 \(count)")
    }

    func calendarPendingReviewCount(_ count: Int) -> String {
        text(en: "\(count) pending review", zh: "\(count) 条待确认")
    }

    func calendarFetched(_ count: Int) -> String {
        text(en: "Fetched \(count) new calendar or reminder candidates.", zh: "已获取 \(count) 条新的日历/提醒候选。")
    }

    func calendarImported(_ count: Int) -> String {
        text(en: "Imported \(count) local calendar tasks.", zh: "已导入 \(count) 条本机日历任务。")
    }

    func calendarAddedToToday() -> String {
        text(en: "Added calendar or reminder candidate to Today.", zh: "已将日历/提醒候选加入今日。")
    }

    func calendarIgnored() -> String {
        text(en: "Calendar or reminder candidate ignored.", zh: "已忽略该日历/提醒候选。")
    }




    func textCharacterCount(_ count: Int, max: Int) -> String {
        "\(count) / \(max)"
    }

    func sortedBy(_ title: String) -> String {
        text(en: "Sorted \(title).", zh: "已切换为\(title)。")
    }

    func snoozedTask(_ title: String) -> String {
        text(en: "Snoozed \(title) for 10 minutes.", zh: "已将 \(title) 稍后 10 分钟提醒。")
    }

    func demoFlightSkipped(_ reason: ReminderSkipReason) -> String {
        switch reason {
        case .muted:
            text(en: "Flight reminders are muted.", zh: "飞行提醒已关闭。")
        case .conservativePause:
            text(en: "Flight reminders paused during meetings or mirrored display.", zh: "会议或镜像投屏时会暂停飞行提醒。")
        case .rateLimited:
            text(en: "Flight reminders are rate-limited for now.", zh: "飞行提醒暂时触发过于频繁。")
        case .unsupportedTrigger:
            text(en: "This action does not trigger a flight reminder.", zh: "这个操作不会触发飞行提醒。")
        }
    }

    func confidence(_ value: Int) -> String {
        text(en: "Confidence \(value)%", zh: "置信度 \(value)%")
    }

    func candidateTaskTitle(_ index: Int) -> String {
        text(en: "Task Candidate \(index)", zh: "候选任务 \(index)")
    }

    func quote(_ textValue: String) -> String {
        text(en: "Quote: \(textValue)", zh: "引用：\(textValue)")
    }

    func priorityTitle(_ priority: TodoTaskPriority) -> String {
        switch priority {
        case .high:
            text(en: "High", zh: "高")
        case .medium:
            text(en: "Medium", zh: "中")
        case .low:
            text(en: "Low", zh: "低")
        }
    }

    func taskSourceTitle(_ source: TodoTaskSource) -> String {
        switch source {
        case .manual:
            text(en: "Self-created", zh: "自建")
        case .localCalendar:
            text(en: "Local Calendar", zh: "本机日历")
        case .codeAgent:
            text(en: "Agent", zh: "Agent")
        }
    }

    func taskListTitle(_ sourceTitle: String) -> String {
        text(en: "All Tasks (\(sourceTitle))", zh: "全部任务（\(sourceTitle)）")
    }

    func lastFetchAt(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language == .chinese ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US")
        formatter.dateFormat = "HH:mm"
        return text(en: "Last fetch \(formatter.string(from: date))", zh: "上次获取 \(formatter.string(from: date))")
    }

    func statusIslandModeTitle(_ mode: StatusIslandMode) -> String {
        switch mode {
        case .centered:
            text(en: "Notch island", zh: "刘海区")
        case .menuBarOnly:
            text(en: "Menu bar icon", zh: "菜单栏图标")
        case .hidden:
            text(en: "Hidden", zh: "隐藏")
        }
    }

    private func text(en: String, zh: String) -> String {
        switch language {
        case .english:
            en
        case .chinese:
            zh
        }
    }
}

extension AppEnvironment {
    var appLanguage: AppLanguage {
        settingsStore.settings.language
    }

    var copy: AppCopy {
        AppCopy(language: appLanguage)
    }
}

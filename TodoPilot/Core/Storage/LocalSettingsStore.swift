import Carbon
import Foundation

enum CaptureHotKeyPreset: String, CaseIterable, Codable, Identifiable {
    case optionSpace
    case controlOptionSpace
    case commandShiftSpace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .optionSpace:
            "⌥ Option + Space"
        case .controlOptionSpace:
            "⌃ Control + ⌥ Option + Space"
        case .commandShiftSpace:
            "⌘ Command + ⇧ Shift + Space"
        }
    }
}

struct CaptureHotKey: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var keyLabel: String
    var preset: CaptureHotKeyPreset?

    var isCustom: Bool {
        preset == nil
    }

    var title: String {
        if let preset {
            return preset.title
        }
        return "\(modifierTitle) + \(keyLabel.capitalized)"
    }

    var normalizedToPreset: CaptureHotKey {
        guard let preset = CaptureHotKeyPreset.allCases.first(where: {
            keyCode == $0.keyCode && carbonModifiers == $0.carbonModifiers
        }) else {
            return self
        }
        return .preset(preset)
    }

    func hasSamePhysicalShortcut(as other: CaptureHotKey) -> Bool {
        keyCode == other.keyCode && carbonModifiers == other.carbonModifiers
    }

    static func preset(_ preset: CaptureHotKeyPreset) -> CaptureHotKey {
        CaptureHotKey(
            keyCode: preset.keyCode,
            carbonModifiers: preset.carbonModifiers,
            keyLabel: "space",
            preset: preset
        )
    }

    static func custom(keyCode: UInt32, carbonModifiers: UInt32, keyLabel: String) -> CaptureHotKey {
        let hotKey = CaptureHotKey(
            keyCode: keyCode,
            carbonModifiers: carbonModifiers,
            keyLabel: keyLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            preset: nil
        )
        return hotKey.normalizedToPreset
    }

    private var modifierTitle: String {
        var parts: [String] = []
        if carbonModifiers & UInt32(cmdKey) != 0 {
            parts.append("⌘ Command")
        }
        if carbonModifiers & UInt32(controlKey) != 0 {
            parts.append("⌃ Control")
        }
        if carbonModifiers & UInt32(optionKey) != 0 {
            parts.append("⌥ Option")
        }
        if carbonModifiers & UInt32(shiftKey) != 0 {
            parts.append("⇧ Shift")
        }
        return parts.joined(separator: " + ")
    }
}

extension CaptureHotKeyPreset {
    var hotKey: CaptureHotKey {
        .preset(self)
    }

    var keyCode: UInt32 {
        UInt32(kVK_Space)
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .optionSpace:
            UInt32(optionKey)
        case .controlOptionSpace:
            UInt32(controlKey | optionKey)
        case .commandShiftSpace:
            UInt32(cmdKey | shiftKey)
        }
    }
}

enum StatusIslandMode: String, CaseIterable, Identifiable {
    case centered
    case menuBarOnly
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .centered:
            "Centered"
        case .menuBarOnly:
            "Menu bar"
        case .hidden:
            "Hidden"
        }
    }
}

enum DefaultTodaySortMode: String, CaseIterable, Identifiable {
    case priority
    case due
    case created

    var id: String { rawValue }

    func title(_ copy: AppCopy) -> String {
        switch self {
        case .priority:
            copy.byPriority
        case .due:
            copy.byDueTime
        case .created:
            copy.byCreatedTime
        }
    }
}

enum FlightReminderFrequency: String, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var perTaskLimitPerThirtyMinutes: Int {
        switch self {
        case .low:
            1
        case .medium:
            2
        case .high:
            3
        }
    }

    var globalLimitPerHour: Int {
        switch self {
        case .low:
            1
        case .medium:
            3
        case .high:
            6
        }
    }

    func title(_ copy: AppCopy) -> String {
        switch self {
        case .low:
            copy.language == .chinese ? "低（每小时 1 次）" : "Low (1/hour)"
        case .medium:
            copy.language == .chinese ? "中（每小时 3 次）" : "Medium (3/hour)"
        case .high:
            copy.language == .chinese ? "高（每小时 6 次）" : "High (6/hour)"
        }
    }
}

enum FlightReminderLeadTime: String, CaseIterable, Identifiable {
    case tenMinutes
    case thirtyMinutes
    case oneHour
    case fourHours
    case sixHours

    var id: String { rawValue }

    var interval: TimeInterval {
        switch self {
        case .tenMinutes:
            10 * 60
        case .thirtyMinutes:
            30 * 60
        case .oneHour:
            60 * 60
        case .fourHours:
            4 * 60 * 60
        case .sixHours:
            6 * 60 * 60
        }
    }

    var minutes: Int {
        Int(interval / 60)
    }

    func title(_ copy: AppCopy) -> String {
        switch self {
        case .tenMinutes:
            copy.language == .chinese ? "截止前 10 分钟" : "10 minutes before due"
        case .thirtyMinutes:
            copy.language == .chinese ? "截止前 30 分钟" : "30 minutes before due"
        case .oneHour:
            copy.language == .chinese ? "截止前 1 小时" : "1 hour before due"
        case .fourHours:
            copy.language == .chinese ? "截止前 4 小时" : "4 hours before due"
        case .sixHours:
            copy.language == .chinese ? "截止前 6 小时" : "6 hours before due"
        }
    }
}

struct AppSettings: Equatable {
    var language: AppLanguage
    var onboardingCompleted: Bool
    var captureEnabled: Bool
    var captureHotKey: CaptureHotKey
    var flightRemindersEnabled: Bool
    var flightReminderSoundEnabled: Bool
    var flightReminderFrequency: FlightReminderFrequency
    var flightReminderLeadTime: FlightReminderLeadTime
    var flightReminderAtDeadlineEnabled: Bool
    var conservativeFlightSilenceEnabled: Bool
    var statusIslandMode: StatusIslandMode
    var defaultTodaySortMode: DefaultTodaySortMode
    var agentMonitoringEnabled: Bool = false
    var claudeCodeMonitoringEnabled: Bool = true
    var codexMonitoringEnabled: Bool = true
    var cursorMonitoringEnabled: Bool = true
    var agentOnboardingSkipped: Bool = false
    var codexHooksTrustConfirmed: Bool = false
    var claudeCodeConnectionVerified: Bool = false
    var codexConnectionVerified: Bool = false
    var cursorConnectionVerified: Bool = false
}

@MainActor
final class LocalSettingsStore: ObservableObject {
    @Published private(set) var settings: AppSettings

    private static let currentAgentConnectionStateSchemaVersion = 1
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let shouldResetLegacyAgentConnectionState =
            defaults.integer(forKey: Keys.agentConnectionStateSchemaVersion)
            < Self.currentAgentConnectionStateSchemaVersion
        self.settings = AppSettings(
            language: AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .english,
            onboardingCompleted: defaults.object(forKey: Keys.onboardingCompleted) as? Bool ?? false,
            captureEnabled: defaults.object(forKey: Keys.captureEnabled) as? Bool ?? true,
            captureHotKey: Self.storedCaptureHotKey(defaults),
            flightRemindersEnabled: defaults.object(forKey: Keys.flightRemindersEnabled) as? Bool ?? true,
            flightReminderSoundEnabled: defaults.object(forKey: Keys.flightReminderSoundEnabled) as? Bool ?? true,
            flightReminderFrequency: FlightReminderFrequency(rawValue: defaults.string(forKey: Keys.flightReminderFrequency) ?? "") ?? .medium,
            flightReminderLeadTime: FlightReminderLeadTime(rawValue: defaults.string(forKey: Keys.flightReminderLeadTime) ?? "") ?? .tenMinutes,
            flightReminderAtDeadlineEnabled: defaults.object(forKey: Keys.flightReminderAtDeadlineEnabled) as? Bool ?? true,
            conservativeFlightSilenceEnabled: defaults.object(forKey: Keys.conservativeFlightSilenceEnabled) as? Bool ?? true,
            statusIslandMode: StatusIslandMode(rawValue: defaults.string(forKey: Keys.statusIslandMode) ?? "") ?? .centered,
            defaultTodaySortMode: DefaultTodaySortMode(rawValue: defaults.string(forKey: Keys.defaultTodaySortMode) ?? "") ?? .priority,
            agentMonitoringEnabled: defaults.object(forKey: Keys.agentMonitoringEnabled) as? Bool ?? false,
            claudeCodeMonitoringEnabled: defaults.object(forKey: Keys.claudeCodeMonitoringEnabled) as? Bool ?? true,
            codexMonitoringEnabled: defaults.object(forKey: Keys.codexMonitoringEnabled) as? Bool ?? true,
            cursorMonitoringEnabled: defaults.object(forKey: Keys.cursorMonitoringEnabled) as? Bool ?? true,
            agentOnboardingSkipped: defaults.object(forKey: Keys.agentOnboardingSkipped) as? Bool ?? false,
            codexHooksTrustConfirmed: shouldResetLegacyAgentConnectionState
                ? false
                : defaults.object(forKey: Keys.codexHooksTrustConfirmed) as? Bool ?? false,
            claudeCodeConnectionVerified: shouldResetLegacyAgentConnectionState
                ? false
                : defaults.object(forKey: Keys.claudeCodeConnectionVerified) as? Bool ?? false,
            codexConnectionVerified: shouldResetLegacyAgentConnectionState
                ? false
                : defaults.object(forKey: Keys.codexConnectionVerified) as? Bool ?? false,
            cursorConnectionVerified: shouldResetLegacyAgentConnectionState
                ? false
                : defaults.object(forKey: Keys.cursorConnectionVerified) as? Bool ?? false
        )
        if shouldResetLegacyAgentConnectionState {
            defaults.set(false, forKey: Keys.codexHooksTrustConfirmed)
            defaults.set(false, forKey: Keys.claudeCodeConnectionVerified)
            defaults.set(false, forKey: Keys.codexConnectionVerified)
            defaults.set(false, forKey: Keys.cursorConnectionVerified)
        }
        defaults.set(
            Self.currentAgentConnectionStateSchemaVersion,
            forKey: Keys.agentConnectionStateSchemaVersion
        )
    }

    func updateOnboardingCompleted(_ completed: Bool) {
        var updated = settings
        updated.onboardingCompleted = completed
        settings = updated
        defaults.set(completed, forKey: Keys.onboardingCompleted)
    }

    func updateLanguage(_ language: AppLanguage) {
        var updated = settings
        updated.language = language
        settings = updated
        defaults.set(language.rawValue, forKey: Keys.language)
    }

    func updateCaptureEnabled(_ enabled: Bool) {
        var updated = settings
        updated.captureEnabled = enabled
        settings = updated
        defaults.set(enabled, forKey: Keys.captureEnabled)
    }

    func updateCaptureHotKey(_ hotKey: CaptureHotKey) {
        let hotKey = hotKey.normalizedToPreset
        var updated = settings
        updated.captureHotKey = hotKey
        settings = updated
        persistCaptureHotKey(hotKey)
    }

    func resetCaptureHotKeyToDefault() {
        updateCaptureHotKey(.preset(.optionSpace))
    }

    private static func storedCaptureHotKey(_ defaults: UserDefaults) -> CaptureHotKey {
        if defaults.string(forKey: Keys.captureHotKeyKind) == "custom",
           defaults.object(forKey: Keys.captureHotKeyKeyCode) != nil,
           defaults.object(forKey: Keys.captureHotKeyCarbonModifiers) != nil {
            let keyCode = UInt32(defaults.integer(forKey: Keys.captureHotKeyKeyCode))
            let modifiers = UInt32(defaults.integer(forKey: Keys.captureHotKeyCarbonModifiers))
            let keyLabel = defaults.string(forKey: Keys.captureHotKeyKeyLabel) ?? "key"
            return .custom(keyCode: keyCode, carbonModifiers: modifiers, keyLabel: keyLabel)
        }

        let preset = CaptureHotKeyPreset(rawValue: defaults.string(forKey: Keys.captureHotKeyPreset) ?? "") ?? .optionSpace
        return .preset(preset)
    }

    private func persistCaptureHotKey(_ hotKey: CaptureHotKey) {
        if let preset = hotKey.preset {
            defaults.set("preset", forKey: Keys.captureHotKeyKind)
            defaults.set(preset.rawValue, forKey: Keys.captureHotKeyPreset)
            defaults.removeObject(forKey: Keys.captureHotKeyKeyCode)
            defaults.removeObject(forKey: Keys.captureHotKeyCarbonModifiers)
            defaults.removeObject(forKey: Keys.captureHotKeyKeyLabel)
            return
        }

        defaults.set("custom", forKey: Keys.captureHotKeyKind)
        defaults.set(Int(hotKey.keyCode), forKey: Keys.captureHotKeyKeyCode)
        defaults.set(Int(hotKey.carbonModifiers), forKey: Keys.captureHotKeyCarbonModifiers)
        defaults.set(hotKey.keyLabel, forKey: Keys.captureHotKeyKeyLabel)
    }

    func updateFlightRemindersEnabled(_ enabled: Bool) {
        var updated = settings
        updated.flightRemindersEnabled = enabled
        settings = updated
        defaults.set(enabled, forKey: Keys.flightRemindersEnabled)
    }

    func updateFlightReminderSoundEnabled(_ enabled: Bool) {
        var updated = settings
        updated.flightReminderSoundEnabled = enabled
        settings = updated
        defaults.set(enabled, forKey: Keys.flightReminderSoundEnabled)
    }

    func updateFlightReminderFrequency(_ frequency: FlightReminderFrequency) {
        var updated = settings
        updated.flightReminderFrequency = frequency
        settings = updated
        defaults.set(frequency.rawValue, forKey: Keys.flightReminderFrequency)
    }

    func updateFlightReminderLeadTime(_ leadTime: FlightReminderLeadTime) {
        var updated = settings
        updated.flightReminderLeadTime = leadTime
        settings = updated
        defaults.set(leadTime.rawValue, forKey: Keys.flightReminderLeadTime)
    }

    func updateFlightReminderAtDeadlineEnabled(_ enabled: Bool) {
        var updated = settings
        updated.flightReminderAtDeadlineEnabled = enabled
        settings = updated
        defaults.set(enabled, forKey: Keys.flightReminderAtDeadlineEnabled)
    }

    func updateConservativeFlightSilenceEnabled(_ enabled: Bool) {
        var updated = settings
        updated.conservativeFlightSilenceEnabled = enabled
        settings = updated
        defaults.set(enabled, forKey: Keys.conservativeFlightSilenceEnabled)
    }

    func updateStatusIslandMode(_ mode: StatusIslandMode) {
        var updated = settings
        updated.statusIslandMode = mode
        settings = updated
        defaults.set(mode.rawValue, forKey: Keys.statusIslandMode)
    }

    func updateDefaultTodaySortMode(_ mode: DefaultTodaySortMode) {
        var updated = settings
        updated.defaultTodaySortMode = mode
        settings = updated
        defaults.set(mode.rawValue, forKey: Keys.defaultTodaySortMode)
    }

    func updateAgentMonitoringEnabled(_ enabled: Bool) {
        var updated = settings
        updated.agentMonitoringEnabled = enabled
        settings = updated
        defaults.set(enabled, forKey: Keys.agentMonitoringEnabled)
    }

    func updateClaudeCodeMonitoringEnabled(_ enabled: Bool) {
        var updated = settings
        updated.claudeCodeMonitoringEnabled = enabled
        settings = updated
        defaults.set(enabled, forKey: Keys.claudeCodeMonitoringEnabled)
    }

    func updateCodexMonitoringEnabled(_ enabled: Bool) {
        var updated = settings
        updated.codexMonitoringEnabled = enabled
        settings = updated
        defaults.set(enabled, forKey: Keys.codexMonitoringEnabled)
    }

    func updateCursorMonitoringEnabled(_ enabled: Bool) {
        var updated = settings
        updated.cursorMonitoringEnabled = enabled
        settings = updated
        defaults.set(enabled, forKey: Keys.cursorMonitoringEnabled)
    }

    func updateAgentOnboardingSkipped(_ skipped: Bool) {
        var updated = settings
        updated.agentOnboardingSkipped = skipped
        settings = updated
        defaults.set(skipped, forKey: Keys.agentOnboardingSkipped)
    }

    func updateCodexHooksTrustConfirmed(_ confirmed: Bool) {
        var updated = settings
        updated.codexHooksTrustConfirmed = confirmed
        settings = updated
        defaults.set(confirmed, forKey: Keys.codexHooksTrustConfirmed)
    }

    func isAgentConnectionVerified(_ provider: AgentProvider) -> Bool {
        switch provider {
        case .claudeCode:
            settings.claudeCodeConnectionVerified
        case .codex:
            settings.codexConnectionVerified
        case .cursor:
            settings.cursorConnectionVerified
        }
    }

    func updateAgentConnectionVerified(_ provider: AgentProvider, verified: Bool) {
        var updated = settings
        let key: String
        switch provider {
        case .claudeCode:
            updated.claudeCodeConnectionVerified = verified
            key = Keys.claudeCodeConnectionVerified
        case .codex:
            updated.codexConnectionVerified = verified
            key = Keys.codexConnectionVerified
        case .cursor:
            updated.cursorConnectionVerified = verified
            key = Keys.cursorConnectionVerified
        }
        settings = updated
        defaults.set(verified, forKey: key)
    }
}

private enum Keys {
    static let language = "app.language"
    static let onboardingCompleted = "onboarding.completed"
    static let captureEnabled = "capture.enabled"
    static let captureHotKeyKind = "capture.hotKey.kind"
    static let captureHotKeyPreset = "capture.hotKeyPreset"
    static let captureHotKeyKeyCode = "capture.hotKey.keyCode"
    static let captureHotKeyCarbonModifiers = "capture.hotKey.carbonModifiers"
    static let captureHotKeyKeyLabel = "capture.hotKey.keyLabel"
    static let flightRemindersEnabled = "flightReminders.enabled"
    static let flightReminderSoundEnabled = "flightReminders.sound.enabled"
    static let flightReminderFrequency = "flightReminders.frequency"
    static let flightReminderLeadTime = "flightReminders.leadTime"
    static let flightReminderAtDeadlineEnabled = "flightReminders.deadline.enabled"
    static let conservativeFlightSilenceEnabled = "flightReminders.conservativeSilence.enabled"
    static let statusIslandMode = "statusIsland.mode"
    static let defaultTodaySortMode = "today.defaultSortMode"
    static let agentMonitoringEnabled = "agentMonitoring.enabled"
    static let claudeCodeMonitoringEnabled = "agentMonitoring.claudeCode.enabled"
    static let codexMonitoringEnabled = "agentMonitoring.codex.enabled"
    static let cursorMonitoringEnabled = "agentMonitoring.cursor.enabled"
    static let agentOnboardingSkipped = "agentMonitoring.onboarding.skipped"
    static let agentConnectionStateSchemaVersion = "agentMonitoring.connectionState.schemaVersion"
    static let codexHooksTrustConfirmed = "agentMonitoring.codex.hooksTrustConfirmed"
    static let claudeCodeConnectionVerified = "agentMonitoring.claudeCode.connectionVerified"
    static let codexConnectionVerified = "agentMonitoring.codex.connectionVerified"
    static let cursorConnectionVerified = "agentMonitoring.cursor.connectionVerified"
}

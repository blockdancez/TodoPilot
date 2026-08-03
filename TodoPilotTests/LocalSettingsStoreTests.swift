import Carbon
import XCTest
@testable import TodoPilot

@MainActor
final class LocalSettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "TodoPilot.LocalSettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultLanguageIsEnglish() {
        let store = LocalSettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings.language, .english)
    }

    func testLanguagePersists() {
        let store = LocalSettingsStore(defaults: defaults)

        store.updateLanguage(.chinese)
        let restored = LocalSettingsStore(defaults: defaults)

        XCTAssertEqual(restored.settings.language, .chinese)
    }

    func testMenuBarCopyIsLocalized() {
        let english = AppCopy(language: .english)
        let chinese = AppCopy(language: .chinese)

        XCTAssertEqual(english.showTodoPilot, "Show TodoPilot")
        XCTAssertEqual(english.quit, "Quit")
        XCTAssertEqual(english.historyDisplayLimitNote, "(Latest 100 only)")
        XCTAssertEqual(chinese.showTodoPilot, "显示 TodoPilot")
        XCTAssertEqual(chinese.quit, "退出")
        XCTAssertEqual(chinese.historyDisplayLimitNote, "（仅显示近100条）")
    }

    func testAppVersionPresentationUsesMarketingVersionFromBundleMetadata() {
        XCTAssertEqual(
            AppVersionPresentation.displayVersion(infoDictionary: [
                "CFBundleShortVersionString": "1.0.1"
            ]),
            "v1.0.1"
        )
        XCTAssertEqual(
            AppVersionPresentation.displayVersion(infoDictionary: [:]),
            "—"
        )
    }

    func testDefaultSettingsMatchPhaseTwoDefaults() {
        let store = LocalSettingsStore(defaults: defaults)

        XCTAssertFalse(store.settings.onboardingCompleted)
        XCTAssertEqual(store.settings.defaultTodaySortMode, .priority)
        XCTAssertEqual(store.settings.flightReminderFrequency, .medium)
        XCTAssertEqual(store.settings.flightReminderLeadTime, .tenMinutes)
        XCTAssertTrue(store.settings.flightReminderAtDeadlineEnabled)
        XCTAssertTrue(store.settings.flightReminderSoundEnabled)
        XCTAssertTrue(store.settings.conservativeFlightSilenceEnabled)
        XCTAssertEqual(store.settings.captureHotKey, .preset(.optionSpace))
        XCTAssertFalse(store.settings.agentMonitoringEnabled)
        XCTAssertTrue(store.settings.claudeCodeMonitoringEnabled)
        XCTAssertTrue(store.settings.codexMonitoringEnabled)
        XCTAssertTrue(store.settings.cursorMonitoringEnabled)
        XCTAssertFalse(store.settings.agentOnboardingSkipped)
        XCTAssertFalse(store.settings.codexHooksTrustConfirmed)
        XCTAssertFalse(store.settings.claudeCodeConnectionVerified)
        XCTAssertFalse(store.settings.codexConnectionVerified)
        XCTAssertFalse(store.settings.cursorConnectionVerified)
        XCTAssertFalse(store.isAgentConnectionVerified(.claudeCode))
        XCTAssertFalse(store.isAgentConnectionVerified(.codex))
        XCTAssertFalse(store.isAgentConnectionVerified(.cursor))
    }

    func testAgentConnectionVerificationPersistsPerProvider() {
        let store = LocalSettingsStore(defaults: defaults)

        store.updateAgentConnectionVerified(.claudeCode, verified: true)
        store.updateAgentConnectionVerified(.codex, verified: true)
        store.updateAgentConnectionVerified(.cursor, verified: true)

        let restored = LocalSettingsStore(defaults: defaults)
        XCTAssertTrue(restored.settings.claudeCodeConnectionVerified)
        XCTAssertTrue(restored.settings.codexConnectionVerified)
        XCTAssertTrue(restored.settings.cursorConnectionVerified)
        XCTAssertTrue(restored.isAgentConnectionVerified(.claudeCode))
        XCTAssertTrue(restored.isAgentConnectionVerified(.codex))
        XCTAssertTrue(restored.isAgentConnectionVerified(.cursor))

        restored.updateAgentConnectionVerified(.codex, verified: false)

        let updated = LocalSettingsStore(defaults: defaults)
        XCTAssertTrue(updated.isAgentConnectionVerified(.claudeCode))
        XCTAssertFalse(updated.isAgentConnectionVerified(.codex))
        XCTAssertTrue(updated.isAgentConnectionVerified(.cursor))
    }

    func testLegacyAgentTrustAndConnectionStateAreResetOnce() {
        defaults.set(true, forKey: "agentMonitoring.codex.hooksTrustConfirmed")
        defaults.set(true, forKey: "agentMonitoring.claudeCode.connectionVerified")
        defaults.set(true, forKey: "agentMonitoring.codex.connectionVerified")
        defaults.set(true, forKey: "agentMonitoring.cursor.connectionVerified")

        let migrated = LocalSettingsStore(defaults: defaults)

        XCTAssertFalse(migrated.settings.codexHooksTrustConfirmed)
        XCTAssertFalse(migrated.isAgentConnectionVerified(.claudeCode))
        XCTAssertFalse(migrated.isAgentConnectionVerified(.codex))
        XCTAssertFalse(migrated.isAgentConnectionVerified(.cursor))

        migrated.updateCodexHooksTrustConfirmed(true)
        migrated.updateAgentConnectionVerified(.codex, verified: true)

        let restored = LocalSettingsStore(defaults: defaults)
        XCTAssertTrue(restored.settings.codexHooksTrustConfirmed)
        XCTAssertTrue(restored.isAgentConnectionVerified(.codex))
    }

    func testLegacyCaptureHotKeyPresetMigratesToHotKey() {
        defaults.set(CaptureHotKeyPreset.commandShiftSpace.rawValue, forKey: "capture.hotKeyPreset")

        let store = LocalSettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings.captureHotKey, .preset(.commandShiftSpace))
    }

    func testCustomCaptureHotKeyPersists() {
        let store = LocalSettingsStore(defaults: defaults)
        let hotKey = CaptureHotKey.custom(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(cmdKey | shiftKey),
            keyLabel: "K"
        )

        store.updateCaptureHotKey(hotKey)
        let restored = LocalSettingsStore(defaults: defaults)

        XCTAssertEqual(restored.settings.captureHotKey, hotKey)
        XCTAssertTrue(restored.settings.captureHotKey.isCustom)
    }

    func testCustomDefaultPhysicalShortcutNormalizesToPreset() {
        let hotKey = CaptureHotKey.custom(
            keyCode: UInt32(kVK_Space),
            carbonModifiers: UInt32(optionKey),
            keyLabel: "space"
        )

        XCTAssertEqual(hotKey, .preset(.optionSpace))
        XCTAssertFalse(hotKey.isCustom)
        XCTAssertTrue(hotKey.hasSamePhysicalShortcut(as: .preset(.optionSpace)))
    }

    func testPersistedCustomDefaultPhysicalShortcutMigratesToPreset() {
        defaults.set("custom", forKey: "capture.hotKey.kind")
        defaults.set(Int(kVK_Space), forKey: "capture.hotKey.keyCode")
        defaults.set(Int(optionKey), forKey: "capture.hotKey.carbonModifiers")
        defaults.set("space", forKey: "capture.hotKey.keyLabel")

        let store = LocalSettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings.captureHotKey, .preset(.optionSpace))
        XCTAssertFalse(store.settings.captureHotKey.isCustom)
    }

    func testSavingCustomDefaultPhysicalShortcutClearsCustomStorage() {
        let store = LocalSettingsStore(defaults: defaults)
        store.updateCaptureHotKey(.custom(
            keyCode: UInt32(kVK_Space),
            carbonModifiers: UInt32(optionKey),
            keyLabel: "space"
        ))

        let restored = LocalSettingsStore(defaults: defaults)

        XCTAssertEqual(restored.settings.captureHotKey, .preset(.optionSpace))
        XCTAssertEqual(defaults.string(forKey: "capture.hotKey.kind"), "preset")
        XCTAssertEqual(defaults.string(forKey: "capture.hotKeyPreset"), CaptureHotKeyPreset.optionSpace.rawValue)
        XCTAssertNil(defaults.object(forKey: "capture.hotKey.keyCode"))
        XCTAssertNil(defaults.object(forKey: "capture.hotKey.carbonModifiers"))
        XCTAssertNil(defaults.object(forKey: "capture.hotKey.keyLabel"))
    }

    func testShortcutRegistrationMessagesAreLocalized() {
        let english = AppCopy(language: .english)
        let chinese = AppCopy(language: .chinese)
        let shortcut = CaptureHotKey.preset(.optionSpace).readableShortcutTitle

        XCTAssertEqual(
            english.shortcutAlreadyInUse(shortcut),
            "⌥ Option + Space is already used by another app or system shortcut."
        )
        XCTAssertEqual(
            chinese.shortcutAlreadyInUse(shortcut),
            "快捷键“⌥ Option + Space”已被其他应用或系统快捷键占用。"
        )
        XCTAssertEqual(chinese.shortcutChange, "修改")
        XCTAssertEqual(chinese.shortcutDefault, "默认")
        XCTAssertEqual(chinese.shortcutListening, "等待按键")
        XCTAssertEqual(chinese.shortcutPressNew, "现在按下新的快捷键。")
        XCTAssertEqual(chinese.shortcutInvalidCombination, "请使用 Command、Option 或 Control 加一个按键。")
        XCTAssertEqual(chinese.shortcutHandlerUnavailable, "无法启用全局快捷键。请重启 TodoPilot 后再试。")
    }

    func testResetCaptureHotKeyUsesDefaultPresetAndClearsCustomStorage() {
        let store = LocalSettingsStore(defaults: defaults)
        store.updateCaptureHotKey(.custom(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(cmdKey | shiftKey),
            keyLabel: "K"
        ))

        store.resetCaptureHotKeyToDefault()
        let restored = LocalSettingsStore(defaults: defaults)

        XCTAssertEqual(restored.settings.captureHotKey, .preset(.optionSpace))
        XCTAssertNil(defaults.object(forKey: "capture.hotKey.keyCode"))
        XCTAssertNil(defaults.object(forKey: "capture.hotKey.carbonModifiers"))
        XCTAssertNil(defaults.object(forKey: "capture.hotKey.keyLabel"))
    }

    func testPhaseTwoSettingsPersist() {
        let store = LocalSettingsStore(defaults: defaults)

        store.updateOnboardingCompleted(true)
        store.updateDefaultTodaySortMode(.due)
        store.updateStatusIslandMode(.menuBarOnly)
        store.updateFlightReminderFrequency(.high)
        store.updateFlightReminderLeadTime(.fourHours)
        store.updateFlightReminderAtDeadlineEnabled(false)
        store.updateFlightReminderSoundEnabled(false)
        store.updateConservativeFlightSilenceEnabled(false)
        store.updateAgentMonitoringEnabled(true)
        store.updateClaudeCodeMonitoringEnabled(false)
        store.updateCodexMonitoringEnabled(false)
        store.updateCursorMonitoringEnabled(false)
        store.updateAgentOnboardingSkipped(true)
        store.updateCodexHooksTrustConfirmed(true)

        let restored = LocalSettingsStore(defaults: defaults)

        XCTAssertTrue(restored.settings.onboardingCompleted)
        XCTAssertEqual(restored.settings.defaultTodaySortMode, .due)
        XCTAssertEqual(restored.settings.statusIslandMode, .menuBarOnly)
        XCTAssertEqual(restored.settings.flightReminderFrequency, .high)
        XCTAssertEqual(restored.settings.flightReminderLeadTime, .fourHours)
        XCTAssertFalse(restored.settings.flightReminderAtDeadlineEnabled)
        XCTAssertFalse(restored.settings.flightReminderSoundEnabled)
        XCTAssertFalse(restored.settings.conservativeFlightSilenceEnabled)
        XCTAssertTrue(restored.settings.agentMonitoringEnabled)
        XCTAssertFalse(restored.settings.claudeCodeMonitoringEnabled)
        XCTAssertFalse(restored.settings.codexMonitoringEnabled)
        XCTAssertFalse(restored.settings.cursorMonitoringEnabled)
        XCTAssertTrue(restored.settings.agentOnboardingSkipped)
        XCTAssertTrue(restored.settings.codexHooksTrustConfirmed)
    }

}

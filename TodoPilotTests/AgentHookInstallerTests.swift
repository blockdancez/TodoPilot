import Foundation
import XCTest
@testable import TodoPilot

final class AgentHookInstallerTests: XCTestCase {
    private var temporaryRoot: URL!
    private var homeDirectory: URL!
    private var applicationSupportDirectory: URL!
    private var helperSourceURL: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "AgentHookInstallerTests-\(UUID().uuidString)",
            isDirectory: true
        )
        homeDirectory = temporaryRoot.appendingPathComponent("Home", isDirectory: true)
        applicationSupportDirectory = temporaryRoot.appendingPathComponent(
            "Application Support",
            isDirectory: true
        )
        helperSourceURL = temporaryRoot.appendingPathComponent("Built Helper", isDirectory: false)
        try FileManager.default.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        try Data("test helper".utf8).write(to: helperSourceURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: helperSourceURL.path
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testInstallPreservesUserHooksCreatesBackupsAndIsIdempotent() throws {
        let claudeURL = homeDirectory.appendingPathComponent(".claude/settings.json")
        let codexURL = homeDirectory.appendingPathComponent(".codex/hooks.json")
        let cursorURL = homeDirectory.appendingPathComponent(".cursor/hooks.json")

        try writeJSON([
            "permissions": ["allow": ["Read"]],
            "hooks": [
                "Stop": [[
                    "matcher": "",
                    "hooks": [["type": "command", "command": "user-stop-hook"]]
                ]]
            ]
        ], to: claudeURL)
        try writeJSON(["hooks": [:]], to: codexURL)
        try writeJSON([
            "version": 1,
            "hooks": ["stop": [["command": "user-cursor-hook"]]]
        ], to: cursorURL)

        let installer = makeInstaller()
        let result = try installer.install()

        XCTAssertEqual(result.providerStates[.claudeCode], .installed)
        XCTAssertEqual(result.providerStates[.codex], .pendingHooksTrust)
        XCTAssertEqual(result.providerStates[.cursor], .installed)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: result.helperURL.path))

        let claude = try readJSON(claudeURL)
        XCTAssertEqual((claude["permissions"] as? [String: Any])?["allow"] as? [String], ["Read"])
        XCTAssertEqual(nestedHookCount(in: claude, event: "UserPromptSubmit"), 1)
        XCTAssertEqual(nestedHookCount(in: claude, event: "Stop"), 2)
        XCTAssertEqual(nestedHookCount(in: claude, event: "StopFailure"), 1)
        XCTAssertEqual(nestedHookCount(in: claude, event: "SessionEnd"), 1)
        XCTAssertEqual(nestedHookCount(in: claude, event: "SubagentStart"), 0)
        XCTAssertEqual(nestedHookCount(in: claude, event: "SubagentStop"), 0)

        let codex = try readJSON(codexURL)
        XCTAssertEqual(nestedHookCount(in: codex, event: "UserPromptSubmit"), 1)
        XCTAssertEqual(nestedHookCount(in: codex, event: "Stop"), 1)
        XCTAssertEqual(nestedHookCount(in: codex, event: "SubagentStart"), 0)
        XCTAssertEqual(nestedHookCount(in: codex, event: "SubagentStop"), 0)
        XCTAssertEqual(firstNestedTimeout(in: codex, event: "Stop"), 2)

        let cursor = try readJSON(cursorURL)
        XCTAssertEqual(cursorHookCount(in: cursor, event: "beforeSubmitPrompt"), 1)
        XCTAssertEqual(cursorHookCount(in: cursor, event: "stop"), 2)
        XCTAssertEqual(cursorHookCount(in: cursor, event: "sessionEnd"), 1)
        XCTAssertEqual(cursorHookCount(in: cursor, event: "subagentStart"), 0)
        XCTAssertEqual(cursorHookCount(in: cursor, event: "subagentStop"), 0)
        XCTAssertTrue(cursorEntries(in: cursor, event: "sessionEnd").contains { entry in
            (entry["timeout"] as? Int) == 2
        })

        XCTAssertEqual(backupCount(nextTo: claudeURL), 1)
        XCTAssertEqual(backupCount(nextTo: codexURL), 1)
        XCTAssertEqual(backupCount(nextTo: cursorURL), 1)

        let firstClaudeData = try Data(contentsOf: claudeURL)
        let firstCodexData = try Data(contentsOf: codexURL)
        let firstCursorData = try Data(contentsOf: cursorURL)
        _ = try installer.install()

        XCTAssertEqual(try Data(contentsOf: claudeURL), firstClaudeData)
        XCTAssertEqual(try Data(contentsOf: codexURL), firstCodexData)
        XCTAssertEqual(try Data(contentsOf: cursorURL), firstCursorData)
        XCTAssertEqual(backupCount(nextTo: claudeURL), 1)
        XCTAssertEqual(backupCount(nextTo: codexURL), 1)
        XCTAssertEqual(backupCount(nextTo: cursorURL), 1)
    }

    func testInstalledHookRequiresHelperToMatchBundledVersion() throws {
        let installer = makeInstaller()
        _ = try installer.install(providers: [.codex])
        XCTAssertTrue(installer.hasInstalledHook(for: .codex))

        try Data("updated test helper".utf8).write(to: helperSourceURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: helperSourceURL.path
        )

        XCTAssertFalse(installer.hasInstalledHook(for: .codex))

        _ = try installer.install(providers: [.codex])
        XCTAssertTrue(installer.hasInstalledHook(for: .codex))
    }

    func testRestorePreviouslyAuthorizedProvidersRefreshesOnlyTheSharedHelper() throws {
        let installer = makeInstaller()
        _ = try installer.install()

        let configurationURLs = AgentHookInstaller.Provider.allCases.map(installer.configurationURL)
        let originalConfigurations = try Dictionary(uniqueKeysWithValues: configurationURLs.map {
            ($0, try Data(contentsOf: $0))
        })

        try Data("updated test helper".utf8).write(to: helperSourceURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: helperSourceURL.path
        )
        XCTAssertTrue(AgentHookInstaller.Provider.allCases.allSatisfy {
            !installer.hasInstalledHook(for: $0)
        })

        let restored = try installer.restorePreviouslyAuthorizedProviders(
            Set(AgentHookInstaller.Provider.allCases)
        )

        XCTAssertEqual(restored, Set(AgentHookInstaller.Provider.allCases))
        XCTAssertTrue(AgentHookInstaller.Provider.allCases.allSatisfy(installer.hasInstalledHook))
        XCTAssertEqual(try Data(contentsOf: installer.installedHelperURL), Data("updated test helper".utf8))
        for url in configurationURLs {
            XCTAssertEqual(try Data(contentsOf: url), originalConfigurations[url])
            XCTAssertEqual(backupCount(nextTo: url), 0)
        }
    }

    func testRestoreDoesNotRewriteIncompleteAuthorizationConfiguration() throws {
        let installer = makeInstaller()
        _ = try installer.install(providers: [.codex])

        let configurationURL = installer.configurationURL(for: .codex)
        var configuration = try readJSON(configurationURL)
        var hooks = try XCTUnwrap(configuration["hooks"] as? [String: Any])
        hooks.removeValue(forKey: "Stop")
        configuration["hooks"] = hooks
        try writeJSON(configuration, to: configurationURL)
        let incompleteConfiguration = try Data(contentsOf: configurationURL)
        let installedHelper = try Data(contentsOf: installer.installedHelperURL)

        try Data("updated test helper".utf8).write(to: helperSourceURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: helperSourceURL.path
        )

        let restored = try installer.restorePreviouslyAuthorizedProviders([.codex])

        XCTAssertTrue(restored.isEmpty)
        XCTAssertEqual(try Data(contentsOf: configurationURL), incompleteConfiguration)
        XCTAssertEqual(try Data(contentsOf: installer.installedHelperURL), installedHelper)
        XCTAssertFalse(installer.hasInstalledHook(for: .codex))
    }

    func testCorruptJSONRejectsInstallBeforeAnyMutation() throws {
        let claudeURL = homeDirectory.appendingPathComponent(".claude/settings.json")
        let codexURL = homeDirectory.appendingPathComponent(".codex/hooks.json")
        try writeJSON(["userSetting": true], to: claudeURL)
        try FileManager.default.createDirectory(
            at: codexURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let corruptData = Data("{ definitely not JSON".utf8)
        try corruptData.write(to: codexURL)
        let originalClaudeData = try Data(contentsOf: claudeURL)

        let installer = makeInstaller()
        XCTAssertThrowsError(try installer.install()) { error in
            XCTAssertEqual(
                error as? AgentHookInstaller.InstallerError,
                .malformedConfiguration(codexURL)
            )
        }

        XCTAssertEqual(try Data(contentsOf: claudeURL), originalClaudeData)
        XCTAssertEqual(try Data(contentsOf: codexURL), corruptData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.installedHelperURL.path))
        XCTAssertEqual(backupCount(nextTo: claudeURL), 0)
    }

    func testUninstallRemovesOnlyExactTodoPilotEntriesAndHelper() throws {
        let installer = makeInstaller()
        _ = try installer.install()

        let claudeURL = installer.configurationURL(for: .claudeCode)
        var claude = try readJSON(claudeURL)
        var hooks = try XCTUnwrap(claude["hooks"] as? [String: Any])
        var stopEntries = try XCTUnwrap(hooks["Stop"] as? [Any])
        stopEntries.append([
            "matcher": "",
            "hooks": [[
                "type": "command",
                "command": "'different/helper' --provider CLAUDE_CODE",
                "timeout": 2
            ]]
        ])
        hooks["Stop"] = stopEntries
        claude["hooks"] = hooks
        try writeJSON(claude, to: claudeURL)

        try installer.uninstall()

        let uninstalledClaude = try readJSON(claudeURL)
        XCTAssertEqual(nestedHookCount(in: uninstalledClaude, event: "Stop"), 1)
        XCTAssertEqual(nestedHookCount(in: uninstalledClaude, event: "UserPromptSubmit"), 0)
        XCTAssertEqual(nestedHookCount(in: uninstalledClaude, event: "StopFailure"), 0)
        XCTAssertEqual(nestedHookCount(in: uninstalledClaude, event: "SessionEnd"), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.installedHelperURL.path))
    }

    func testSelectedProviderInstallDoesNotReadOrMutateOtherProviders() throws {
        let claudeURL = homeDirectory.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(
            at: claudeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let corruptClaude = Data("{ not valid".utf8)
        try corruptClaude.write(to: claudeURL)

        let installer = makeInstaller()
        let result = try installer.install(providers: [.cursor])

        XCTAssertEqual(result.providerStates, [.cursor: .installed])
        XCTAssertEqual(try Data(contentsOf: claudeURL), corruptClaude)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: installer.configurationURL(for: .codex).path
        ))
        XCTAssertEqual(
            cursorHookCount(in: try readJSON(installer.configurationURL(for: .cursor)), event: "stop"),
            1
        )
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installer.installedHelperURL.path))
    }

    func testPartialUninstallRetainsHelperUntilLastOwnedProviderIsRemoved() throws {
        let installer = makeInstaller()
        _ = try installer.install(providers: [.claudeCode, .codex])

        try installer.uninstall(providers: [.claudeCode])

        XCTAssertTrue(FileManager.default.fileExists(atPath: installer.installedHelperURL.path))
        XCTAssertEqual(
            nestedHookCount(in: try readJSON(installer.configurationURL(for: .claudeCode)), event: "Stop"),
            0
        )
        XCTAssertEqual(
            nestedHookCount(in: try readJSON(installer.configurationURL(for: .codex)), event: "Stop"),
            1
        )

        try installer.uninstall(providers: [.codex])

        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.installedHelperURL.path))
        XCTAssertEqual(
            nestedHookCount(in: try readJSON(installer.configurationURL(for: .codex)), event: "Stop"),
            0
        )
    }

    func testProviderDetectorHandlesSupportedOldAndUnparseableVersions() throws {
        let executable = temporaryRoot.appendingPathComponent("provider")
        try Data().write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let claude = makeDetector(executable: executable, version: "claude 2.1.77").detect(.claudeCode)
        let codex = makeDetector(executable: executable, version: "codex-cli 0.116.0").detect(.codex)
        let cursor = makeDetector(executable: executable, version: "Cursor future-build").detect(.cursor)

        XCTAssertEqual(claude.compatibility, .needsUpgrade)
        XCTAssertEqual(codex.compatibility, .supported)
        XCTAssertEqual(cursor.compatibility, .unknown)
        XCTAssertEqual(AgentProviderDetector.parseVersion("Cursor 2.3")?.patch, 0)
    }

    func testProviderDetectorTreatsUnreliableConfigurationConservatively() throws {
        let executable = temporaryRoot.appendingPathComponent("codex")
        try Data().write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let codexConfiguration = homeDirectory.appendingPathComponent(".codex/hooks.json")
        try FileManager.default.createDirectory(
            at: codexConfiguration.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{ invalid".utf8).write(to: codexConfiguration)

        let detection = makeDetector(executable: executable, version: "codex-cli 0.116.0")
            .detect(.codex)

        XCTAssertEqual(detection.configurationStatus, .invalid)
        XCTAssertEqual(detection.compatibility, .unknown)
    }

    private func makeInstaller() -> AgentHookInstaller {
        AgentHookInstaller(
            homeDirectory: homeDirectory,
            applicationSupportDirectory: applicationSupportDirectory,
            helperSourceURL: helperSourceURL,
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            uniqueSuffix: { UUID().uuidString }
        )
    }

    private func makeDetector(executable: URL, version: String) -> AgentProviderDetector {
        AgentProviderDetector(
            homeDirectory: homeDirectory,
            executableResolver: { _ in executable },
            versionReader: { _ in version }
        )
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private func readJSON(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func nestedHookCount(in root: [String: Any], event: String) -> Int {
        let hooks = root["hooks"] as? [String: Any]
        return (hooks?[event] as? [Any])?.count ?? 0
    }

    private func cursorHookCount(in root: [String: Any], event: String) -> Int {
        nestedHookCount(in: root, event: event)
    }

    private func firstNestedTimeout(in root: [String: Any], event: String) -> Int? {
        let hooks = root["hooks"] as? [String: Any]
        let entries = hooks?[event] as? [[String: Any]]
        let handlers = entries?.first?["hooks"] as? [[String: Any]]
        return handlers?.first?["timeout"] as? Int
    }

    private func cursorEntries(in root: [String: Any], event: String) -> [[String: Any]] {
        let hooks = root["hooks"] as? [String: Any]
        return hooks?[event] as? [[String: Any]] ?? []
    }

    private func backupCount(nextTo url: URL) -> Int {
        let prefix = "\(url.lastPathComponent).todopilot-backup-"
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )) ?? []
        return contents.filter { $0.lastPathComponent.hasPrefix(prefix) }.count
    }
}

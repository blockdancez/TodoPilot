import Darwin
import Foundation

struct AgentHookInstaller {
    enum Provider: String, CaseIterable, Hashable {
        case claudeCode
        case codex
        case cursor
        case antigravity

        // Antigravity 以组名区分各个集成，另外三款工具使用固定的 hooks 键。
        var hookGroupKey: String { self == .antigravity ? "todopilot" : "hooks" }

        func configurationURL(in homeDirectory: URL) -> URL {
            let relativePath: String
            switch self {
            case .claudeCode: relativePath = ".claude/settings.json"
            case .codex: relativePath = ".codex/hooks.json"
            case .cursor: relativePath = ".cursor/hooks.json"
            case .antigravity: relativePath = ".gemini/config/hooks.json"
            }
            return homeDirectory.appendingPathComponent(relativePath, isDirectory: false)
        }
    }

    enum ProviderState: Equatable {
        case installed
        case pendingHooksTrust
    }

    struct InstallationResult: Equatable {
        let providerStates: [Provider: ProviderState]
        let helperURL: URL
    }

    enum InstallerError: Error, Equatable, LocalizedError {
        case helperMissing(URL)
        case malformedConfiguration(URL)
        case incompatibleConfiguration(URL, key: String)
        case cannotCreateBackup(URL)
        case cannotWriteAtomically(URL)

        var errorDescription: String? {
            switch self {
            case let .helperMissing(url):
                return "TodoPilot Agent Hook helper is missing at \(url.path)."
            case let .malformedConfiguration(url):
                return "The hook configuration at \(url.path) is not valid JSON."
            case let .incompatibleConfiguration(url, key):
                return "The hook configuration at \(url.path) has an incompatible \(key) value."
            case let .cannotCreateBackup(url):
                return "Could not back up the hook configuration at \(url.path)."
            case let .cannotWriteAtomically(url):
                return "Could not atomically update the hook configuration at \(url.path)."
            }
        }
    }

    private struct PlannedConfigurationChange {
        let url: URL
        let originalData: Data?
        let replacementData: Data?
    }

    private let homeDirectory: URL
    private let applicationSupportDirectory: URL
    private let helperSourceURL: URL
    private let fileManager: FileManager
    private let now: () -> Date
    private let uniqueSuffix: () -> String

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationSupportDirectory: URL? = nil,
        helperSourceURL: URL? = nil,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init,
        uniqueSuffix: @escaping () -> String = { UUID().uuidString }
    ) {
        self.homeDirectory = homeDirectory
        self.applicationSupportDirectory = applicationSupportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.helperSourceURL = helperSourceURL
            ?? Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent("TodoPilotAgentHook", isDirectory: false)
        self.fileManager = fileManager
        self.now = now
        self.uniqueSuffix = uniqueSuffix
    }

    var installedHelperURL: URL {
        applicationSupportDirectory
            .appendingPathComponent("TodoPilot", isDirectory: true)
            .appendingPathComponent("AgentIntegration", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("TodoPilotAgentHook", isDirectory: false)
    }

    func configurationURL(for provider: Provider) -> URL {
        provider.configurationURL(in: homeDirectory)
    }

    func hasInstalledHook(for provider: Provider) -> Bool {
        guard installedHelperMatchesBundledVersion() else {
            return false
        }
        return hasCompleteOwnedConfiguration(for: provider)
    }

    func restorePreviouslyAuthorizedProviders(_ providers: Set<Provider>) throws -> Set<Provider> {
        let authorizedProviders = Set(providers.filter(hasCompleteOwnedConfiguration))
        guard !authorizedProviders.isEmpty else { return [] }
        guard fileManager.isExecutableFile(atPath: helperSourceURL.path) else {
            throw InstallerError.helperMissing(helperSourceURL)
        }
        if !installedHelperMatchesBundledVersion() {
            try installHelperAtomically()
        }
        return authorizedProviders
    }

    private func hasCompleteOwnedConfiguration(for provider: Provider) -> Bool {
        let url = configurationURL(for: provider)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let hooks = root[provider.hookGroupKey] as? [String: Any] else {
            return false
        }
        if provider == .antigravity, let enabled = hooks["enabled"], !Self.isJSONBoolean(enabled, equalTo: true) {
            return false
        }
        return Self.events(for: provider).allSatisfy { event in
            guard let entries = hooks[event] as? [Any] else { return false }
            let entry = ownedEntry(provider: provider, event: event)
            return entries.contains { Self.jsonObjectsEqual($0, entry) }
        }
    }

    private func installedHelperMatchesBundledVersion() -> Bool {
        guard fileManager.isExecutableFile(atPath: helperSourceURL.path),
              fileManager.isExecutableFile(atPath: installedHelperURL.path),
              let bundledData = try? Data(contentsOf: helperSourceURL, options: .mappedIfSafe),
              let installedData = try? Data(contentsOf: installedHelperURL, options: .mappedIfSafe) else {
            return false
        }
        return bundledData == installedData
    }

    func install() throws -> InstallationResult {
        try install(providers: Set(Provider.allCases))
    }

    func install(providers: Set<Provider>) throws -> InstallationResult {
        guard !providers.isEmpty else {
            return InstallationResult(providerStates: [:], helperURL: installedHelperURL)
        }
        guard fileManager.isExecutableFile(atPath: helperSourceURL.path) else {
            throw InstallerError.helperMissing(helperSourceURL)
        }

        // Parse every provider file before mutating anything. One corrupt file
        // therefore cannot leave a partially installed integration.
        let changes = try Provider.allCases.filter(providers.contains).map { provider in
            try plannedChange(for: provider, installing: true)
        }

        try installHelperAtomically()
        try apply(changes)

        let providerStates: [Provider: ProviderState] = Dictionary(uniqueKeysWithValues: providers.map { provider in
            let state: ProviderState = provider == .codex ? .pendingHooksTrust : .installed
            return (provider, state)
        })
        return InstallationResult(providerStates: providerStates, helperURL: installedHelperURL)
    }

    func uninstall() throws {
        try uninstall(providers: Set(Provider.allCases), forceHelperRemoval: true)
    }

    func uninstall(providers: Set<Provider>) throws {
        try uninstall(providers: providers, forceHelperRemoval: false)
    }

    private func uninstall(
        providers: Set<Provider>,
        forceHelperRemoval: Bool
    ) throws {
        guard !providers.isEmpty else { return }
        // As for install, validate all existing files before the first write.
        let changes = try Provider.allCases.filter(providers.contains).map { provider in
            try plannedChange(for: provider, installing: false)
        }
        try apply(changes)

        let shouldRemoveHelper = forceHelperRemoval || !Provider.allCases.contains { hasOwnedEntry(for: $0) != false }
        if shouldRemoveHelper, fileManager.fileExists(atPath: installedHelperURL.path) {
            try fileManager.removeItem(at: installedHelperURL)
        }
    }

    private func plannedChange(
        for provider: Provider,
        installing: Bool
    ) throws -> PlannedConfigurationChange {
        let url = configurationURL(for: provider)
        let originalData: Data?
        let root: [String: Any]

        if fileManager.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                guard
                    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    throw InstallerError.malformedConfiguration(url)
                }
                originalData = data
                root = object
            } catch let error as InstallerError {
                throw error
            } catch {
                throw InstallerError.malformedConfiguration(url)
            }
        } else {
            originalData = nil
            root = [:]
        }

        let replacement = try mergeHooks(
            root: root,
            provider: provider,
            installing: installing,
            configurationURL: url
        )

        guard !Self.jsonObjectsEqual(root, replacement) else {
            return PlannedConfigurationChange(url: url, originalData: originalData, replacementData: nil)
        }

        let replacementData = try JSONSerialization.data(
            withJSONObject: replacement,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) + Data([0x0A])
        return PlannedConfigurationChange(
            url: url,
            originalData: originalData,
            replacementData: replacementData
        )
    }

    private func mergeHooks(
        root: [String: Any],
        provider: Provider,
        installing: Bool,
        configurationURL: URL
    ) throws -> [String: Any] {
        var result = root
        let groupKey = provider.hookGroupKey
        var hooks: [String: Any]
        if let existing = root[groupKey] {
            guard let dictionary = existing as? [String: Any] else {
                throw InstallerError.incompatibleConfiguration(configurationURL, key: groupKey)
            }
            hooks = dictionary
        } else {
            hooks = [:]
        }

        // 暂时移出自己的处理器，避免重复安装，也保留同组中用户添加的命令。
        let events = Self.events(for: provider)
        var removedOwnedEntry = false
        for event in events {
            guard let existing = hooks[event] else { continue }
            guard var entries = existing as? [Any] else {
                throw InstallerError.incompatibleConfiguration(configurationURL, key: "\(groupKey).\(event)")
            }
            let entry = ownedEntry(provider: provider, event: event)
            let count = entries.count
            entries.removeAll { Self.jsonObjectsEqual($0, entry) }
            if entries.count != count {
                removedOwnedEntry = true
                hooks[event] = entries.isEmpty ? nil : entries
            }
        }
        if !installing, !removedOwnedEntry { return root }

        if installing {
            if provider == .antigravity, let enabled = hooks["enabled"], !Self.isJSONBoolean(enabled, equalTo: true) {
                // 显式授权可重新启用自己的组，避免同时启用用户已停用的其他命令。
                guard Self.isJSONBoolean(enabled, equalTo: false), hooks.count == 1 else {
                    throw InstallerError.incompatibleConfiguration(configurationURL, key: "\(groupKey).enabled")
                }
                hooks["enabled"] = true
            }
            for event in events {
                var entries = hooks[event] as? [Any] ?? []
                entries.append(ownedEntry(provider: provider, event: event))
                hooks[event] = entries
            }
            if provider == .cursor, result["version"] == nil {
                result["version"] = 1
            }
        }

        if provider == .antigravity, hooks.isEmpty {
            result.removeValue(forKey: groupKey)
        } else {
            result[groupKey] = hooks
        }
        return result
    }

    private func ownedEntry(provider: Provider, event: String) -> [String: Any] {
        let command = helperCommand(provider: provider)
        switch provider {
        case .claudeCode, .codex:
            return [
                "matcher": "",
                "hooks": [["type": "command", "command": command, "timeout": 2]]
            ]
        case .cursor:
            return ["command": command, "timeout": 2]
        case .antigravity:
            // 部分 Antigravity 版本的 stdin 不含事件名，每个直接处理器通过参数传入自己的事件。
            return ["type": "command", "command": "\(command) --event \(event)", "timeout": 2]
        }
    }

    private func helperCommand(provider: Provider) -> String {
        "\(Self.shellQuote(installedHelperURL.path)) --provider \(Self.wireProviderValue(provider))"
    }

    private func apply(_ changes: [PlannedConfigurationChange]) throws {
        for change in changes {
            guard let replacementData = change.replacementData else { continue }
            try fileManager.createDirectory(
                at: change.url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if change.originalData != nil {
                let backupURL = change.url.appendingPathExtension(
                    "todopilot-backup-\(Int(now().timeIntervalSince1970 * 1_000))-\(uniqueSuffix())"
                )
                do {
                    try fileManager.copyItem(at: change.url, to: backupURL)
                } catch {
                    throw InstallerError.cannotCreateBackup(change.url)
                }
            }

            try writeAtomically(replacementData, to: change.url)
        }
    }

    private func installHelperAtomically() throws {
        let destinationDirectory = installedHelperURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let temporaryURL = destinationDirectory.appendingPathComponent(
            ".TodoPilotAgentHook-tmp-\(uniqueSuffix())",
            isDirectory: false
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }

        do {
            try fileManager.copyItem(at: helperSourceURL, to: temporaryURL)
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: temporaryURL.path
            )
            try atomicRename(from: temporaryURL, to: installedHelperURL)
        } catch let error as InstallerError {
            throw error
        } catch {
            throw InstallerError.cannotWriteAtomically(installedHelperURL)
        }
    }

    private func writeAtomically(_ data: Data, to destinationURL: URL) throws {
        let temporaryURL = destinationURL.deletingLastPathComponent().appendingPathComponent(
            ".\(destinationURL.lastPathComponent)-tmp-\(uniqueSuffix())",
            isDirectory: false
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }

        do {
            try data.write(to: temporaryURL, options: .withoutOverwriting)
            if let permissions = try? fileManager.attributesOfItem(atPath: destinationURL.path)[.posixPermissions] {
                try fileManager.setAttributes(
                    [.posixPermissions: permissions],
                    ofItemAtPath: temporaryURL.path
                )
            }
            try atomicRename(from: temporaryURL, to: destinationURL)
        } catch let error as InstallerError {
            throw error
        } catch {
            throw InstallerError.cannotWriteAtomically(destinationURL)
        }
    }

    private func atomicRename(from sourceURL: URL, to destinationURL: URL) throws {
        let result = sourceURL.path.withCString { sourcePath in
            destinationURL.path.withCString { destinationPath in
                Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard result == 0 else {
            throw InstallerError.cannotWriteAtomically(destinationURL)
        }
    }

    private static func events(for provider: Provider) -> [String] {
        switch provider {
        case .claudeCode:
            return ["UserPromptSubmit", "Stop", "StopFailure", "SessionEnd"]
        case .codex:
            return ["UserPromptSubmit", "Stop", "Interrupt", "SessionEnd"]
        case .cursor:
            return ["beforeSubmitPrompt", "stop", "sessionEnd"]
        case .antigravity:
            return ["PreInvocation", "Stop"]
        }
    }

    // 无法解析时保留共享 Helper；设置页只为确实找到的条目提供卸载。
    func hasOwnedEntry(for provider: Provider) -> Bool? {
        let url = configurationURL(for: provider)
        guard fileManager.fileExists(atPath: url.path) else { return false }
        guard
            let data = try? Data(contentsOf: url),
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return nil
        }

        guard let group = root[provider.hookGroupKey] else { return false }
        guard let hooks = group as? [String: Any] else { return nil }
        return Self.events(for: provider).contains { event in
            guard let entries = hooks[event] as? [Any] else { return false }
            let entry = ownedEntry(provider: provider, event: event)
            return entries.contains { Self.jsonObjectsEqual($0, entry) }
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func wireProviderValue(_ provider: Provider) -> String {
        switch provider {
        case .claudeCode: return "CLAUDE_CODE"
        case .codex: return "CODEX"
        case .cursor: return "CURSOR"
        case .antigravity: return "ANTIGRAVITY"
        }
    }

    private static func isJSONBoolean(_ value: Any, equalTo expected: Bool) -> Bool {
        // NSNumber 的相等比较会把 JSON 的 0/1 当成布尔值。
        CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() && (value as? Bool) == expected
    }

    private static func jsonObjectsEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        (lhs as AnyObject).isEqual(rhs)
    }
}

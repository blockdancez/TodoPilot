import Darwin
import Foundation

struct AgentHookInstaller {
    enum Provider: String, CaseIterable, Hashable {
        case claudeCode
        case codex
        case cursor
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
        switch provider {
        case .claudeCode:
            return homeDirectory
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("settings.json", isDirectory: false)
        case .codex:
            return homeDirectory
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("hooks.json", isDirectory: false)
        case .cursor:
            return homeDirectory
                .appendingPathComponent(".cursor", isDirectory: true)
                .appendingPathComponent("hooks.json", isDirectory: false)
        }
    }

    func hasInstalledHook(for provider: Provider) -> Bool {
        guard installedHelperMatchesBundledVersion() else {
            return false
        }
        let url = configurationURL(for: provider)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else {
            return false
        }
        let ownedEntry: [String: Any] = provider == .cursor
            ? cursorEntry()
            : nestedEntry(provider: provider)
        return Self.events(for: provider).allSatisfy { event in
            guard let entries = hooks[event] as? [Any] else { return false }
            return entries.contains { Self.jsonObjectsEqual($0, ownedEntry) }
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

        let shouldRemoveHelper = forceHelperRemoval || !Provider.allCases.contains(where: hasOwnedEntry)
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

        let replacement: [String: Any]
        switch provider {
        case .claudeCode, .codex:
            replacement = try mergeNestedHooks(
                root: root,
                provider: provider,
                installing: installing,
                configurationURL: url
            )
        case .cursor:
            replacement = try mergeCursorHooks(
                root: root,
                installing: installing,
                configurationURL: url
            )
        }

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

    private func mergeNestedHooks(
        root: [String: Any],
        provider: Provider,
        installing: Bool,
        configurationURL: URL
    ) throws -> [String: Any] {
        var result = root
        var hooks: [String: Any]
        if let existing = root["hooks"] {
            guard let dictionary = existing as? [String: Any] else {
                throw InstallerError.incompatibleConfiguration(configurationURL, key: "hooks")
            }
            hooks = dictionary
        } else {
            hooks = [:]
        }

        for event in Self.events(for: provider) {
            var entries: [Any]
            if let existing = hooks[event] {
                guard let array = existing as? [Any] else {
                    throw InstallerError.incompatibleConfiguration(configurationURL, key: "hooks.\(event)")
                }
                entries = array
            } else {
                entries = []
            }

            let ownedEntry = nestedEntry(provider: provider)
            entries.removeAll { Self.jsonObjectsEqual($0, ownedEntry) }
            if installing {
                entries.append(ownedEntry)
            }

            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
        }

        if hooks.isEmpty, root["hooks"] == nil, !installing {
            result.removeValue(forKey: "hooks")
        } else {
            result["hooks"] = hooks
        }
        return result
    }

    private func mergeCursorHooks(
        root: [String: Any],
        installing: Bool,
        configurationURL: URL
    ) throws -> [String: Any] {
        var result = root
        var hooks: [String: Any]
        if let existing = root["hooks"] {
            guard let dictionary = existing as? [String: Any] else {
                throw InstallerError.incompatibleConfiguration(configurationURL, key: "hooks")
            }
            hooks = dictionary
        } else {
            hooks = [:]
        }

        let ownedEntry = cursorEntry()
        for event in Self.events(for: .cursor) {
            var entries: [Any]
            if let existing = hooks[event] {
                guard let array = existing as? [Any] else {
                    throw InstallerError.incompatibleConfiguration(configurationURL, key: "hooks.\(event)")
                }
                entries = array
            } else {
                entries = []
            }

            entries.removeAll { Self.jsonObjectsEqual($0, ownedEntry) }
            if installing {
                entries.append(ownedEntry)
            }

            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
        }

        if installing, result["version"] == nil {
            result["version"] = 1
        }
        if hooks.isEmpty, root["hooks"] == nil, !installing {
            result.removeValue(forKey: "hooks")
        } else {
            result["hooks"] = hooks
        }
        return result
    }

    private func nestedEntry(provider: Provider) -> [String: Any] {
        [
            "matcher": "",
            "hooks": [[
                "type": "command",
                "command": helperCommand(provider: provider),
                "timeout": 2
            ]]
        ]
    }

    private func cursorEntry() -> [String: Any] {
        [
            "command": helperCommand(provider: .cursor),
            "timeout": 2
        ]
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
            return ["UserPromptSubmit", "Stop"]
        case .cursor:
            return ["beforeSubmitPrompt", "stop", "sessionEnd"]
        }
    }

    private func hasOwnedEntry(for provider: Provider) -> Bool {
        let url = configurationURL(for: provider)
        guard fileManager.fileExists(atPath: url.path) else { return false }
        guard
            let data = try? Data(contentsOf: url),
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let hooks = root["hooks"] as? [String: Any]
        else {
            // An unselected configuration that cannot be inspected must never
            // cause the shared helper to be removed.
            return true
        }

        let ownedEntry: [String: Any] = provider == .cursor
            ? cursorEntry()
            : nestedEntry(provider: provider)
        return Self.events(for: provider).contains { event in
            guard let entries = hooks[event] as? [Any] else { return false }
            return entries.contains { Self.jsonObjectsEqual($0, ownedEntry) }
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
        }
    }

    private static func jsonObjectsEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        (lhs as AnyObject).isEqual(rhs)
    }
}

import AppKit
import Foundation

struct AgentProviderDetector {
    enum ConfigurationStatus: Equatable {
        case missing
        case valid
        case invalid
    }

    enum Compatibility: Equatable {
        case notInstalled
        case supported
        case needsUpgrade
        case unknown
    }

    struct Detection: Equatable {
        let provider: AgentHookInstaller.Provider
        let executableURL: URL?
        let configurationURL: URL
        let configurationPresent: Bool
        let configurationStatus: ConfigurationStatus
        let version: String?
        let compatibility: Compatibility
    }

    struct SemanticVersion: Comparable, Equatable {
        let major: Int
        let minor: Int
        let patch: Int

        static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
            (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }
    }

    typealias ExecutableResolver = (_ provider: AgentHookInstaller.Provider) -> [URL]
    typealias VersionReader = (_ executableURL: URL) -> String?

    private let homeDirectory: URL
    private let fileManager: FileManager
    private let executableResolver: ExecutableResolver
    private let versionReader: VersionReader

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        executableResolver: ExecutableResolver? = nil,
        versionReader: VersionReader? = nil
    ) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        self.executableResolver = executableResolver
            ?? Self.defaultExecutableResolver(homeDirectory: homeDirectory, fileManager: fileManager)
        self.versionReader = versionReader ?? Self.readVersion
    }

    func detect(_ provider: AgentHookInstaller.Provider) -> Detection {
        let configurationURL = provider.configurationURL(in: homeDirectory)
        let configurationPresent = fileManager.fileExists(atPath: configurationURL.path)
        let configurationStatus = inspectConfiguration(at: configurationURL, provider: provider)

        // App、独立 IDE 与 CLI 可以同时安装，并共用一份 Hook 配置。优先选择可用的一端。
        var selected: (url: URL, version: String?, compatibility: Compatibility)?
        for executableURL in executableResolver(provider) {
            let version = versionReader(executableURL)
            let compatibility: Compatibility
            if let parsed = version.flatMap(Self.parseVersion),
               let minimum = Self.minimumVersion(for: provider, executableURL: executableURL) {
                if parsed < minimum {
                    compatibility = .needsUpgrade
                } else {
                    compatibility = configurationStatus == .invalid ? .unknown : .supported
                }
            } else {
                compatibility = .unknown
            }
            if selected == nil || selected?.compatibility == .needsUpgrade || compatibility == .supported {
                selected = (executableURL, version, compatibility)
            }
            if compatibility == .supported { break }
        }

        return Detection(
            provider: provider,
            executableURL: selected?.url,
            configurationURL: configurationURL,
            configurationPresent: configurationPresent,
            configurationStatus: configurationStatus,
            version: selected?.version,
            compatibility: selected?.compatibility ?? (configurationPresent ? .unknown : .notInstalled)
        )
    }

    func detectAll() -> [Detection] {
        AgentHookInstaller.Provider.allCases.map(detect)
    }

    private func inspectConfiguration(
        at url: URL,
        provider: AgentHookInstaller.Provider
    ) -> ConfigurationStatus {
        guard fileManager.fileExists(atPath: url.path) else { return .missing }
        guard
            let data = try? Data(contentsOf: url),
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return .invalid
        }
        if let hooks = root[provider.hookGroupKey], !(hooks is [String: Any]) {
            return .invalid
        }
        return .valid
    }

    static func parseVersion(_ value: String) -> SemanticVersion? {
        let pattern = #"(?<![0-9])([0-9]+)\.([0-9]+)(?:\.([0-9]+))?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = expression.firstMatch(in: value, range: range) else { return nil }

        func component(at index: Int, default defaultValue: Int? = nil) -> Int? {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: value) else {
                return defaultValue
            }
            return Int(value[swiftRange])
        }

        guard let major = component(at: 1), let minor = component(at: 2) else { return nil }
        return SemanticVersion(
            major: major,
            minor: minor,
            patch: component(at: 3, default: 0) ?? 0
        )
    }

    private static func minimumVersion(
        for provider: AgentHookInstaller.Provider,
        executableURL: URL
    ) -> SemanticVersion? {
        switch provider {
        case .claudeCode:
            // StopFailure was introduced in Claude Code 2.1.78.
            return SemanticVersion(major: 2, minor: 1, patch: 78)
        case .codex:
            // Claude-style lifecycle hooks are observable in Codex CLI 0.116.
            return SemanticVersion(major: 0, minor: 116, patch: 0)
        case .cursor:
            // The selected lifecycle hook payload shape is present in Cursor 2.3.
            return SemanticVersion(major: 2, minor: 3, patch: 0)
        case .antigravity:
            // Google 的发行记录分别在 CLI 1.1.10、App 2.6.0 修复了 Stop 被跳过的问题。
            if executableURL.lastPathComponent == "agy" {
                return SemanticVersion(major: 1, minor: 1, patch: 10)
            }
            if applicationBundle(for: executableURL)?.bundleIdentifier == "com.google.antigravity" {
                return SemanticVersion(major: 2, minor: 6, patch: 0)
            }
            // 独立 IDE 使用自己的版本线，未公布相同修复的版本，等待真实事件确认。
            return nil
        }
    }

    private static func defaultExecutableResolver(
        homeDirectory: URL,
        fileManager: FileManager
    ) -> ExecutableResolver {
        let environmentPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true) }
        let commonPaths = [
            homeDirectory.appendingPathComponent(".local/bin", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/bin", isDirectory: true)
        ]

        return { provider in
            let executableNames: [String]
            var absoluteCandidates: [URL] = []
            switch provider {
            case .claudeCode:
                executableNames = ["claude"]
            case .codex:
                executableNames = ["codex"]
                absoluteCandidates = [
                    URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
                    URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"),
                    homeDirectory.appendingPathComponent("Applications/ChatGPT.app/Contents/Resources/codex"),
                    homeDirectory.appendingPathComponent("Applications/Codex.app/Contents/Resources/codex")
                ]
            case .cursor:
                executableNames = ["cursor", "cursor-agent", "agent"]
                absoluteCandidates = [
                    URL(fileURLWithPath: "/Applications/Cursor.app/Contents/MacOS/Cursor"),
                    homeDirectory.appendingPathComponent("Applications/Cursor.app/Contents/MacOS/Cursor")
                ]
            case .antigravity:
                executableNames = ["agy"]
                // 用系统登记的 bundle 定位 App 和 IDE，也支持改名或移出 Applications 的安装。
                let descriptor = AgentProviderIconDescriptor.descriptor(for: .antigravity)
                absoluteCandidates = descriptor.bundleIdentifiers.compactMap { identifier in
                    NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
                        .flatMap { Bundle(url: $0)?.executableURL }
                }
            }

            let pathCandidates = (environmentPaths + commonPaths).flatMap { directory in
                executableNames.map { directory.appendingPathComponent($0, isDirectory: false) }
            }
            if provider == .antigravity {
                let cli = pathCandidates.first { fileManager.isExecutableFile(atPath: $0.path) }
                return absoluteCandidates + [cli].compactMap { $0 }
            }
            let executable = (absoluteCandidates + pathCandidates).first {
                fileManager.isExecutableFile(atPath: $0.path)
            }
            return [executable].compactMap { $0 }
        }
    }

    private static func applicationBundle(for executableURL: URL) -> Bundle? {
        let directory = executableURL.deletingLastPathComponent()
        guard directory.lastPathComponent == "MacOS" else { return nil }
        return Bundle(url: directory.deletingLastPathComponent().deletingLastPathComponent())
    }

    private static func readVersion(executableURL: URL) -> String? {
        if let bundle = applicationBundle(for: executableURL),
           let identifier = bundle.bundleIdentifier,
           AgentProviderIconDescriptor.descriptor(for: .antigravity).bundleIdentifiers.contains(identifier) {
            // 避免执行 Electron 桌面程序的 --version 时意外打开窗口或改变焦点。
            return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        }
        let process = Process()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = ["--version"]
        process.standardOutput = output
        process.standardError = output

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }

        guard semaphore.wait(timeout: .now() + 1) == .success else {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }
}

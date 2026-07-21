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

    typealias ExecutableResolver = (_ provider: AgentHookInstaller.Provider) -> URL?
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
        let configurationURL = Self.configurationURL(for: provider, homeDirectory: homeDirectory)
        let configurationPresent = fileManager.fileExists(atPath: configurationURL.path)
        let configurationStatus = inspectConfiguration(at: configurationURL)
        let executableURL = executableResolver(provider)
        let rawVersion = executableURL.flatMap(versionReader)
        let parsedVersion = rawVersion.flatMap(Self.parseVersion)

        let compatibility: Compatibility
        if executableURL == nil {
            compatibility = configurationPresent ? .unknown : .notInstalled
        } else if let parsedVersion {
            if parsedVersion < Self.minimumVersion(for: provider) {
                compatibility = .needsUpgrade
            } else {
                compatibility = configurationStatus == .invalid ? .unknown : .supported
            }
        } else {
            // Wrapper scripts and vendor-specific version strings are common.
            // Do not claim compatibility when parsing is not dependable.
            compatibility = .unknown
        }

        return Detection(
            provider: provider,
            executableURL: executableURL,
            configurationURL: configurationURL,
            configurationPresent: configurationPresent,
            configurationStatus: configurationStatus,
            version: rawVersion,
            compatibility: compatibility
        )
    }

    func detectAll() -> [Detection] {
        AgentHookInstaller.Provider.allCases.map(detect)
    }

    private func inspectConfiguration(at url: URL) -> ConfigurationStatus {
        guard fileManager.fileExists(atPath: url.path) else { return .missing }
        guard
            let data = try? Data(contentsOf: url),
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return .invalid
        }
        if let hooks = root["hooks"], !(hooks is [String: Any]) {
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
        for provider: AgentHookInstaller.Provider
    ) -> SemanticVersion {
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
        }
    }

    private static func configurationURL(
        for provider: AgentHookInstaller.Provider,
        homeDirectory: URL
    ) -> URL {
        switch provider {
        case .claudeCode:
            return homeDirectory.appendingPathComponent(".claude/settings.json")
        case .codex:
            return homeDirectory.appendingPathComponent(".codex/hooks.json")
        case .cursor:
            return homeDirectory.appendingPathComponent(".cursor/hooks.json")
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
            }

            let pathCandidates = (environmentPaths + commonPaths).flatMap { directory in
                executableNames.map { directory.appendingPathComponent($0, isDirectory: false) }
            }
            return (absoluteCandidates + pathCandidates).first {
                fileManager.isExecutableFile(atPath: $0.path)
            }
        }
    }

    private static func readVersion(executableURL: URL) -> String? {
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

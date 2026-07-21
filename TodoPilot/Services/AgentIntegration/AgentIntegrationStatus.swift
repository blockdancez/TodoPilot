import Foundation

enum AgentIntegrationHealth: Equatable {
    case notInstalled
    case pendingAuthorization
    case installing
    case uninstalling
    case waitingCodexTrust
    case readyForFirstRun
    case connected
    case paused
    case needsUpgrade
    case needsRepair
}

enum AgentIntegrationOperation: Equatable {
    typealias Provider = AgentHookInstaller.Provider

    case idle
    case detecting
    case installing(Set<Provider>)
    case uninstalling(Set<Provider>)
    case testingBridge

    var isBusy: Bool {
        self != .idle
    }

    var isInstalling: Bool {
        if case .installing = self {
            return true
        }
        return false
    }

    var isUninstalling: Bool {
        if case .uninstalling = self {
            return true
        }
        return false
    }

    var providers: Set<Provider> {
        switch self {
        case let .installing(providers), let .uninstalling(providers):
            providers
        case .idle, .detecting, .testingBridge:
            []
        }
    }

    func affects(_ provider: Provider) -> Bool {
        providers.contains(provider)
    }

    func isInstalling(provider: Provider) -> Bool {
        isInstalling && affects(provider)
    }

    func isUninstalling(provider: Provider) -> Bool {
        isUninstalling && affects(provider)
    }
}

enum AgentIntegrationHealthResolver {
    typealias Provider = AgentHookInstaller.Provider

    struct Context: Equatable {
        let provider: Provider
        let operation: AgentIntegrationOperation
        let configurationStatus: AgentProviderDetector.ConfigurationStatus
        let compatibility: AgentProviderDetector.Compatibility
        let hookInstalled: Bool
        let executablePresent: Bool
        let configurationPresent: Bool
        let agentMonitoringEnabled: Bool
        let providerMonitoringEnabled: Bool
        let listenerIsAvailable: Bool
        let codexHooksTrustConfirmed: Bool
        let hasVerifiedEvent: Bool

        init(
            provider: Provider,
            operation: AgentIntegrationOperation = .idle,
            configurationStatus: AgentProviderDetector.ConfigurationStatus,
            compatibility: AgentProviderDetector.Compatibility,
            hookInstalled: Bool,
            executablePresent: Bool,
            configurationPresent: Bool,
            agentMonitoringEnabled: Bool,
            providerMonitoringEnabled: Bool,
            listenerIsAvailable: Bool,
            codexHooksTrustConfirmed: Bool = false,
            hasVerifiedEvent: Bool = false
        ) {
            self.provider = provider
            self.operation = operation
            self.configurationStatus = configurationStatus
            self.compatibility = compatibility
            self.hookInstalled = hookInstalled
            self.executablePresent = executablePresent
            self.configurationPresent = configurationPresent
            self.agentMonitoringEnabled = agentMonitoringEnabled
            self.providerMonitoringEnabled = providerMonitoringEnabled
            self.listenerIsAvailable = listenerIsAvailable
            self.codexHooksTrustConfirmed = codexHooksTrustConfirmed
            self.hasVerifiedEvent = hasVerifiedEvent
        }
    }

    static func resolve(_ context: Context) -> AgentIntegrationHealth {
        if context.operation.isInstalling(provider: context.provider) {
            return .installing
        }
        if context.operation.isUninstalling(provider: context.provider) {
            return .uninstalling
        }

        if context.configurationStatus == .invalid {
            return .needsRepair
        }
        if context.compatibility == .needsUpgrade {
            return .needsUpgrade
        }

        guard context.hookInstalled else {
            if context.executablePresent {
                return .pendingAuthorization
            }
            return context.configurationPresent ? .needsRepair : .notInstalled
        }

        guard context.agentMonitoringEnabled, context.providerMonitoringEnabled else {
            return .paused
        }
        guard context.listenerIsAvailable else {
            return .needsRepair
        }
        if context.provider == .codex, !context.codexHooksTrustConfirmed {
            return .waitingCodexTrust
        }
        return context.hasVerifiedEvent ? .connected : .readyForFirstRun
    }
}

struct AgentIntegrationSnapshot: Equatable {
    let provider: AgentHookInstaller.Provider
    let detection: AgentProviderDetector.Detection
    let health: AgentIntegrationHealth
}

extension AgentHookInstaller.Provider {
    var agentProvider: AgentProvider {
        switch self {
        case .claudeCode: .claudeCode
        case .codex: .codex
        case .cursor: .cursor
        }
    }

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }
}

extension AgentProvider {
    var installerProvider: AgentHookInstaller.Provider {
        switch self {
        case .claudeCode: .claudeCode
        case .codex: .codex
        case .cursor: .cursor
        }
    }
}

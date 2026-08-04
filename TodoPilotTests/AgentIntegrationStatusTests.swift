import XCTest
@testable import TodoPilot

final class AgentIntegrationStatusTests: XCTestCase {
    typealias Provider = AgentHookInstaller.Provider
    typealias Context = AgentIntegrationHealthResolver.Context

    func testOperationHelpersDescribeGlobalAndProviderScopedWork() {
        XCTAssertFalse(AgentIntegrationOperation.idle.isBusy)
        XCTAssertFalse(AgentIntegrationOperation.idle.isInstalling)
        XCTAssertTrue(AgentIntegrationOperation.detecting.isBusy)
        XCTAssertTrue(AgentIntegrationOperation.testingBridge.isBusy)

        let restoring = AgentIntegrationOperation.restoring([.claudeCode, .cursor])
        XCTAssertTrue(restoring.isBusy)
        XCTAssertTrue(restoring.isRestoring)
        XCTAssertEqual(restoring.providers, [.claudeCode, .cursor])
        XCTAssertTrue(restoring.isRestoring(provider: .cursor))
        XCTAssertFalse(restoring.isRestoring(provider: .codex))

        let installing = AgentIntegrationOperation.installing([.claudeCode, .codex])
        XCTAssertTrue(installing.isBusy)
        XCTAssertTrue(installing.isInstalling)
        XCTAssertFalse(installing.isUninstalling)
        XCTAssertEqual(installing.providers, [.claudeCode, .codex])
        XCTAssertTrue(installing.affects(.claudeCode))
        XCTAssertTrue(installing.isInstalling(provider: .codex))
        XCTAssertFalse(installing.isInstalling(provider: .cursor))

        let uninstalling = AgentIntegrationOperation.uninstalling([.cursor])
        XCTAssertTrue(uninstalling.isBusy)
        XCTAssertFalse(uninstalling.isInstalling)
        XCTAssertTrue(uninstalling.isUninstalling)
        XCTAssertTrue(uninstalling.isUninstalling(provider: .cursor))
        XCTAssertFalse(uninstalling.isUninstalling(provider: .codex))
    }

    func testProviderScopedOperationTakesPriorityOnlyForAffectedProvider() {
        let restoring = context(
            provider: .claudeCode,
            operation: .restoring([.claudeCode]),
            configurationStatus: .invalid,
            hookInstalled: false
        )
        XCTAssertEqual(AgentIntegrationHealthResolver.resolve(restoring), .installing)

        let broken = context(
            provider: .codex,
            operation: .installing([.codex]),
            configurationStatus: .invalid,
            compatibility: .needsUpgrade,
            hookInstalled: false
        )
        XCTAssertEqual(AgentIntegrationHealthResolver.resolve(broken), .installing)

        let unaffected = context(
            provider: .claudeCode,
            operation: .installing([.codex]),
            configurationStatus: .invalid,
            compatibility: .needsUpgrade,
            hookInstalled: false
        )
        XCTAssertEqual(AgentIntegrationHealthResolver.resolve(unaffected), .needsRepair)

        let uninstalling = context(
            provider: .cursor,
            operation: .uninstalling([.cursor]),
            agentMonitoringEnabled: false,
            providerMonitoringEnabled: false
        )
        XCTAssertEqual(AgentIntegrationHealthResolver.resolve(uninstalling), .uninstalling)
    }

    func testConfigurationDamagePrecedesCompatibilityAndUpgradePrecedesInstallationState() {
        let damagedAndOld = context(
            configurationStatus: .invalid,
            compatibility: .needsUpgrade,
            hookInstalled: false
        )
        XCTAssertEqual(AgentIntegrationHealthResolver.resolve(damagedAndOld), .needsRepair)

        let old = context(
            compatibility: .needsUpgrade,
            hookInstalled: false,
            executablePresent: true
        )
        XCTAssertEqual(AgentIntegrationHealthResolver.resolve(old), .needsUpgrade)
    }

    func testNotInstalledHealthUsesExecutableAndConfigurationPresence() {
        let cases: [(executable: Bool, configuration: Bool, expected: AgentIntegrationHealth)] = [
            (false, false, .notInstalled),
            (true, false, .pendingAuthorization),
            (true, true, .pendingAuthorization),
            (false, true, .needsRepair)
        ]

        for item in cases {
            let value = context(
                hookInstalled: false,
                executablePresent: item.executable,
                configurationPresent: item.configuration
            )
            XCTAssertEqual(
                AgentIntegrationHealthResolver.resolve(value),
                item.expected,
                "executable=\(item.executable), configuration=\(item.configuration)"
            )
        }
    }

    func testEitherMonitoringSwitchPausesAnInstalledProvider() {
        let globalDisabled = context(
            provider: .codex,
            agentMonitoringEnabled: false,
            providerMonitoringEnabled: true,
            listenerIsAvailable: false,
            codexHooksTrustConfirmed: false
        )
        XCTAssertEqual(AgentIntegrationHealthResolver.resolve(globalDisabled), .paused)

        let providerDisabled = context(
            provider: .codex,
            agentMonitoringEnabled: true,
            providerMonitoringEnabled: false,
            listenerIsAvailable: false,
            codexHooksTrustConfirmed: false
        )
        XCTAssertEqual(AgentIntegrationHealthResolver.resolve(providerDisabled), .paused)
    }

    func testUnavailableListenerRequiresRepairBeforeCodexTrustIsConsidered() {
        let value = context(
            provider: .codex,
            listenerIsAvailable: false,
            codexHooksTrustConfirmed: false
        )

        XCTAssertEqual(AgentIntegrationHealthResolver.resolve(value), .needsRepair)
    }

    func testCodexTrustIsProviderSpecificAndDoesNotImplyConnection() {
        let waiting = context(provider: .codex, codexHooksTrustConfirmed: false)
        XCTAssertEqual(AgentIntegrationHealthResolver.resolve(waiting), .waitingCodexTrust)

        let trusted = context(provider: .codex, codexHooksTrustConfirmed: true)
        XCTAssertEqual(AgentIntegrationHealthResolver.resolve(trusted), .readyForFirstRun)

        let claude = context(provider: .claudeCode, codexHooksTrustConfirmed: false)
        XCTAssertEqual(AgentIntegrationHealthResolver.resolve(claude), .readyForFirstRun)
    }

    func testRealProviderEventIsRequiredForConnectedHealth() {
        let unverified = context(provider: .cursor, hasVerifiedEvent: false)
        XCTAssertEqual(AgentIntegrationHealthResolver.resolve(unverified), .readyForFirstRun)

        let verified = context(provider: .cursor, hasVerifiedEvent: true)
        XCTAssertEqual(AgentIntegrationHealthResolver.resolve(verified), .connected)

        let verifiedCodex = context(
            provider: .codex,
            codexHooksTrustConfirmed: true,
            hasVerifiedEvent: true
        )
        XCTAssertEqual(AgentIntegrationHealthResolver.resolve(verifiedCodex), .connected)
    }

    func testGlobalOperationsDoNotHideUnderlyingProviderHealth() {
        let detecting = context(
            operation: .detecting,
            hookInstalled: false,
            executablePresent: false,
            configurationPresent: false
        )
        XCTAssertEqual(AgentIntegrationHealthResolver.resolve(detecting), .notInstalled)

        let testing = context(operation: .testingBridge, hasVerifiedEvent: false)
        XCTAssertEqual(AgentIntegrationHealthResolver.resolve(testing), .readyForFirstRun)
    }

    private func context(
        provider: Provider = .claudeCode,
        operation: AgentIntegrationOperation = .idle,
        configurationStatus: AgentProviderDetector.ConfigurationStatus = .valid,
        compatibility: AgentProviderDetector.Compatibility = .supported,
        hookInstalled: Bool = true,
        executablePresent: Bool = true,
        configurationPresent: Bool = true,
        agentMonitoringEnabled: Bool = true,
        providerMonitoringEnabled: Bool = true,
        listenerIsAvailable: Bool = true,
        codexHooksTrustConfirmed: Bool = false,
        hasVerifiedEvent: Bool = false
    ) -> Context {
        Context(
            provider: provider,
            operation: operation,
            configurationStatus: configurationStatus,
            compatibility: compatibility,
            hookInstalled: hookInstalled,
            executablePresent: executablePresent,
            configurationPresent: configurationPresent,
            agentMonitoringEnabled: agentMonitoringEnabled,
            providerMonitoringEnabled: providerMonitoringEnabled,
            listenerIsAvailable: listenerIsAvailable,
            codexHooksTrustConfirmed: codexHooksTrustConfirmed,
            hasVerifiedEvent: hasVerifiedEvent
        )
    }
}

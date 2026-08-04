import XCTest
@testable import TodoPilot

final class AgentOnboardingPresentationPolicyTests: XCTestCase {
    func testDetectedAgentAppendsAgentMonitoringAsFinalStep() {
        XCTAssertEqual(
            AgentOnboardingPresentationPolicy.firstLaunchSteps(
                hasDetectedAgentProviders: true
            ),
            [.permission, .capture, .reminders, .agents]
        )
    }

    func testNoDetectedAgentEndsFirstLaunchAtPrivacyStep() {
        XCTAssertEqual(
            AgentOnboardingPresentationPolicy.firstLaunchSteps(
                hasDetectedAgentProviders: false
            ),
            [.permission, .capture, .reminders]
        )
    }

    func testPrivacyStepWaitsWhileAgentDetectionIsStillRunning() {
        XCTAssertEqual(
            AgentOnboardingPresentationPolicy.privacyContinuation(
                hasCompletedDetection: false,
                hasDetectedAgentProviders: false
            ),
            .waitForDetection
        )
    }

    func testPrivacyStepFinishesWithoutProviderAndContinuesWithProvider() {
        XCTAssertEqual(
            AgentOnboardingPresentationPolicy.privacyContinuation(
                hasCompletedDetection: true,
                hasDetectedAgentProviders: false
            ),
            .finish
        )
        XCTAssertEqual(
            AgentOnboardingPresentationPolicy.privacyContinuation(
                hasCompletedDetection: false,
                hasDetectedAgentProviders: true
            ),
            .showAgentStep
        )
    }

    func testAgentStepTracksDetectionInstallationAndEnabledStates() {
        XCTAssertEqual(
            AgentOnboardingPresentationPolicy.agentStepState(
                monitoringEnabled: false,
                hasCompletedDetection: false,
                hasDetectedProviders: false
            ),
            .detecting
        )
        XCTAssertEqual(
            AgentOnboardingPresentationPolicy.agentStepState(
                monitoringEnabled: false,
                hasCompletedDetection: true,
                hasDetectedProviders: true
            ),
            .readyToInstall
        )
        XCTAssertEqual(
            AgentOnboardingPresentationPolicy.agentStepState(
                monitoringEnabled: true,
                hasCompletedDetection: false,
                hasDetectedProviders: false
            ),
            .enabled
        )
    }

    func testAgentStepOffersReauthorizationWhenMonitoringWasEnabledButHooksNeedRepair() {
        XCTAssertEqual(
            AgentOnboardingPresentationPolicy.agentStepState(
                monitoringEnabled: true,
                hasCompletedDetection: true,
                hasDetectedProviders: true,
                hasProvidersRequiringAuthorization: true
            ),
            .readyToInstall
        )
    }

    func testOnlyNewUsersReceiveAutomaticFirstLaunchGuide() {
        XCTAssertEqual(
            AgentOnboardingPresentationPolicy.presentation(
                onboardingCompleted: false
            ),
            .firstLaunch
        )
        XCTAssertNil(
            AgentOnboardingPresentationPolicy.presentation(
                onboardingCompleted: true
            )
        )
    }

    func testCompletedUserReceivesOneActiveAuthorizationPromptAfterAnUpgradeBreaksMonitoring() {
        XCTAssertEqual(
            AgentOnboardingPresentationPolicy.presentation(
                onboardingCompleted: true,
                agentMonitoringEnabled: true,
                hasCompletedDetection: true,
                hasProvidersRequiringAuthorization: true,
                hasPresentedAgentRecoveryThisSession: false
            ),
            .agentAuthorization
        )
        XCTAssertNil(
            AgentOnboardingPresentationPolicy.presentation(
                onboardingCompleted: true,
                agentMonitoringEnabled: true,
                hasCompletedDetection: true,
                hasProvidersRequiringAuthorization: true,
                hasPresentedAgentRecoveryThisSession: true
            )
        )
    }

    func testCompletedUserIsNotPromptedUntilDetectionFinishesOrWhenMonitoringIsDisabled() {
        XCTAssertNil(
            AgentOnboardingPresentationPolicy.presentation(
                onboardingCompleted: true,
                agentMonitoringEnabled: true,
                hasCompletedDetection: false,
                hasProvidersRequiringAuthorization: true
            )
        )
        XCTAssertNil(
            AgentOnboardingPresentationPolicy.presentation(
                onboardingCompleted: true,
                agentMonitoringEnabled: false,
                hasCompletedDetection: true,
                hasProvidersRequiringAuthorization: true
            )
        )
    }

    func testAgentFinalStepUsesAuthorizationChromeAndOpensSettingsAfterInstall() {
        XCTAssertEqual(
            AgentOnboardingPresentationPolicy.chrome(for: .agents),
            .agentAuthorization
        )
        XCTAssertEqual(
            AgentOnboardingPresentationPolicy.agentInstallationSuccessAction,
            .openAgentSettings
        )
    }

    func testClosingGuideOnlyMarksAgentSkippedOnAgentStep() {
        XCTAssertFalse(AgentOnboardingPresentationPolicy.shouldMarkAgentOnboardingSkippedWhenClosing(
            isShowingAgentStep: false
        ))
        XCTAssertTrue(AgentOnboardingPresentationPolicy.shouldMarkAgentOnboardingSkippedWhenClosing(
            isShowingAgentStep: true
        ))
    }
}

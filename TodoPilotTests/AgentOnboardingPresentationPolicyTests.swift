import XCTest
@testable import TodoPilot

final class AgentOnboardingPresentationPolicyTests: XCTestCase {
    func testIncompleteFirstLaunchAlwaysPresentsFullGuide() {
        XCTAssertEqual(
            AgentOnboardingPresentationPolicy.presentation(
                onboardingCompleted: false,
                hasInstalledAgentProvider: false,
                agentOnboardingSkipped: false,
                hasCompletedAgentDetection: false,
                hasDetectedAgentProviders: false
            ),
            .firstLaunch
        )
    }

    func testExistingUserWaitsForAgentDetectionToFinish() {
        XCTAssertNil(AgentOnboardingPresentationPolicy.presentation(
            onboardingCompleted: true,
            hasInstalledAgentProvider: false,
            agentOnboardingSkipped: false,
            hasCompletedAgentDetection: false,
            hasDetectedAgentProviders: true
        ))
    }

    func testExistingUserWithDetectedAgentPresentsAuthorizationOnly() {
        XCTAssertEqual(
            AgentOnboardingPresentationPolicy.presentation(
                onboardingCompleted: true,
                hasInstalledAgentProvider: false,
                agentOnboardingSkipped: false,
                hasCompletedAgentDetection: true,
                hasDetectedAgentProviders: true
            ),
            .agentAuthorization
        )
    }

    func testDetectionCompletingAfterFirstLaunchCanPresentAgentAuthorization() {
        XCTAssertEqual(
            AgentOnboardingPresentationPolicy.presentation(
                onboardingCompleted: false,
                hasInstalledAgentProvider: false,
                agentOnboardingSkipped: false,
                hasCompletedAgentDetection: false,
                hasDetectedAgentProviders: false
            ),
            .firstLaunch
        )
        XCTAssertEqual(
            AgentOnboardingPresentationPolicy.presentation(
                onboardingCompleted: true,
                hasInstalledAgentProvider: false,
                agentOnboardingSkipped: false,
                hasCompletedAgentDetection: true,
                hasDetectedAgentProviders: true
            ),
            .agentAuthorization
        )
    }

    func testNoAgentDoesNotPresentAuthorization() {
        XCTAssertNil(AgentOnboardingPresentationPolicy.presentation(
            onboardingCompleted: true,
            hasInstalledAgentProvider: false,
            agentOnboardingSkipped: false,
            hasCompletedAgentDetection: true,
            hasDetectedAgentProviders: false
        ))
    }

    func testInstalledProviderDoesNotPresentAuthorizationEvenWhenMonitoringIsPaused() {
        XCTAssertNil(AgentOnboardingPresentationPolicy.presentation(
            onboardingCompleted: true,
            hasInstalledAgentProvider: true,
            agentOnboardingSkipped: false,
            hasCompletedAgentDetection: true,
            hasDetectedAgentProviders: true
        ))
    }

    func testSkippedAgentOnboardingDoesNotPresentAgain() {
        XCTAssertNil(AgentOnboardingPresentationPolicy.presentation(
            onboardingCompleted: true,
            hasInstalledAgentProvider: false,
            agentOnboardingSkipped: true,
            hasCompletedAgentDetection: true,
            hasDetectedAgentProviders: true
        ))
    }

    func testClosingAgentAuthorizationMarksItSkipped() {
        XCTAssertTrue(AgentOnboardingPresentationPolicy.shouldMarkAgentOnboardingSkippedWhenClosing(
            presentation: .agentAuthorization,
            isShowingAgentStep: true
        ))
    }

    func testClosingFullGuideOnlyMarksSkippedWhileShowingAgentStep() {
        XCTAssertFalse(AgentOnboardingPresentationPolicy.shouldMarkAgentOnboardingSkippedWhenClosing(
            presentation: .firstLaunch,
            isShowingAgentStep: false
        ))
        XCTAssertTrue(AgentOnboardingPresentationPolicy.shouldMarkAgentOnboardingSkippedWhenClosing(
            presentation: .firstLaunch,
            isShowingAgentStep: true
        ))
    }

    func testIndependentAgentAuthorizationOpensAgentSettingsAfterInstallation() {
        XCTAssertEqual(
            AgentOnboardingPresentationPolicy.authorizationSuccessAction(for: .agentAuthorization),
            .openAgentSettings
        )
    }

    func testFullGuideContinuesAfterAgentInstallation() {
        XCTAssertEqual(
            AgentOnboardingPresentationPolicy.authorizationSuccessAction(for: .firstLaunch),
            .continueGuide
        )
    }
}

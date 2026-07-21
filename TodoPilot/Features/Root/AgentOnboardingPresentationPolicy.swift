import Foundation

enum AgentOnboardingPresentation: String, Identifiable, Equatable {
    case firstLaunch
    case agentAuthorization

    var id: String { rawValue }
}

enum AgentAuthorizationSuccessAction: Equatable {
    case continueGuide
    case openAgentSettings
}

struct AgentOnboardingPresentationPolicy {
    static func presentation(
        onboardingCompleted: Bool,
        hasInstalledAgentProvider: Bool,
        agentOnboardingSkipped: Bool,
        hasCompletedAgentDetection: Bool,
        hasDetectedAgentProviders: Bool
    ) -> AgentOnboardingPresentation? {
        guard onboardingCompleted else {
            return .firstLaunch
        }
        guard hasCompletedAgentDetection,
              hasDetectedAgentProviders,
              !hasInstalledAgentProvider,
              !agentOnboardingSkipped else {
            return nil
        }
        return .agentAuthorization
    }

    static func shouldMarkAgentOnboardingSkippedWhenClosing(
        presentation: AgentOnboardingPresentation,
        isShowingAgentStep: Bool
    ) -> Bool {
        presentation == .agentAuthorization || isShowingAgentStep
    }

    static func authorizationSuccessAction(
        for presentation: AgentOnboardingPresentation
    ) -> AgentAuthorizationSuccessAction {
        presentation == .agentAuthorization ? .openAgentSettings : .continueGuide
    }
}

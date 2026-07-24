import Foundation

enum AgentOnboardingPresentation: String, Identifiable, Equatable {
    case firstLaunch

    var id: String { rawValue }
}

enum AgentInstallationSuccessAction: Equatable {
    case openAgentSettings
}

enum AgentOnboardingChrome: Equatable {
    case welcome
    case agentAuthorization
}

enum OnboardingStep: Int, CaseIterable, Identifiable, Equatable {
    case permission
    case capture
    case agents
    case reminders

    var id: Int { rawValue }
}

enum AgentOnboardingStepState: Equatable {
    case detecting
    case readyToInstall
    case unavailable
    case enabled
}

enum AgentOnboardingPrivacyContinuation: Equatable {
    case waitForDetection
    case finish
    case showAgentStep
}

struct AgentOnboardingPresentationPolicy {
    static func firstLaunchSteps(
        hasDetectedAgentProviders: Bool
    ) -> [OnboardingStep] {
        var steps: [OnboardingStep] = [.permission, .capture, .reminders]
        if hasDetectedAgentProviders {
            steps.append(.agents)
        }
        return steps
    }

    static func privacyContinuation(
        hasCompletedDetection: Bool,
        hasDetectedAgentProviders: Bool
    ) -> AgentOnboardingPrivacyContinuation {
        if hasDetectedAgentProviders {
            return .showAgentStep
        }
        return hasCompletedDetection ? .finish : .waitForDetection
    }

    static func agentStepState(
        monitoringEnabled: Bool,
        hasCompletedDetection: Bool,
        hasDetectedProviders: Bool
    ) -> AgentOnboardingStepState {
        if monitoringEnabled {
            return .enabled
        }
        guard hasCompletedDetection else {
            return .detecting
        }
        return hasDetectedProviders ? .readyToInstall : .unavailable
    }

    static func presentation(onboardingCompleted: Bool) -> AgentOnboardingPresentation? {
        onboardingCompleted ? nil : .firstLaunch
    }

    static func shouldMarkAgentOnboardingSkippedWhenClosing(
        isShowingAgentStep: Bool
    ) -> Bool {
        isShowingAgentStep
    }

    static func chrome(for step: OnboardingStep) -> AgentOnboardingChrome {
        step == .agents ? .agentAuthorization : .welcome
    }

    static let agentInstallationSuccessAction: AgentInstallationSuccessAction = .openAgentSettings
}

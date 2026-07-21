import AppKit
import Foundation

@MainActor
enum AgentApplicationActivator {
    @discardableResult
    static func activate(
        provider: AgentProvider,
        originBundleID: String?,
        originProcessID: Int32?
    ) -> Bool {
        if let originProcessID,
           let application = NSRunningApplication(processIdentifier: pid_t(originProcessID)),
           originBundleID == nil || application.bundleIdentifier == originBundleID,
           application.activate() {
            return true
        }

        let bundleIDs = ([originBundleID].compactMap { $0 } + fallbackBundleIDs(for: provider))
            .filter(isSafeBundleID)
        for bundleID in bundleIDs {
            if let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
               application.activate() {
                return true
            }
        }
        return false
    }

    private static func fallbackBundleIDs(for provider: AgentProvider) -> [String] {
        switch provider {
        case .claudeCode:
            ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty"]
        case .codex:
            ["com.openai.codex", "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty"]
        case .cursor:
            ["com.todesktop.230313mzl4w4u92"]
        }
    }

    private static func isSafeBundleID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 160 && value.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
                && !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && scalar.value != 47
        }
    }
}

import AppKit
import SwiftUI

struct TodoPilotCommands: Commands {
    @AppStorage("app.language") private var languageRawValue = AppLanguage.english.rawValue

    private var copy: AppCopy {
        AppCopy(language: AppLanguage(rawValue: languageRawValue) ?? .english)
    }

    var body: some Commands {
        CommandGroup(replacing: .appTermination) {
            Button("\(copy.quit) TodoPilot") {
                AppTerminationCoordinator.prepareForTermination(application: NSApp)
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }

        CommandMenu("TodoPilot") {
            Button(copy.openTodayList) {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .openTodayList, object: nil)
            }
            .keyboardShortcut("t", modifiers: [.command])

            Button(copy.muteFlightReminders) {
                NotificationCenter.default.post(name: .muteFlightReminders, object: nil)
            }
            .keyboardShortcut("m", modifiers: [.command, .option])
        }

        CommandMenu(copy.debug) {
            Button(copy.openDiagnostics) {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .openDiagnostics, object: nil)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }
    }
}

extension Notification.Name {
    static let openDiagnostics = Notification.Name("TodoPilot.openDiagnostics")
    static let openTodayList = Notification.Name("TodoPilot.openTodayList")
    static let startCapturePipeline = Notification.Name("TodoPilot.startCapturePipeline")
    static let muteFlightReminders = Notification.Name("TodoPilot.muteFlightReminders")
    static let showOnboardingGuide = Notification.Name("TodoPilot.showOnboardingGuide")
    static let openAgentTasks = Notification.Name("TodoPilot.openAgentTasks")
    static let requestOpenAgentTasks = Notification.Name("TodoPilot.requestOpenAgentTasks")
    static let applicationTerminationRequested = Notification.Name("TodoPilot.applicationTerminationRequested")
}

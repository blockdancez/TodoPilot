import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        installQuitAppleEventHandler()
        recoverMainWindowVisibility(application: application)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !AppTerminationState.isTerminating else {
            return .terminateNow
        }

        AppTerminationCoordinator.prepareForTermination(application: sender)
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        recoverMainWindowVisibility(application: sender)
        return true
    }

    private func recoverMainWindowVisibility(application: NSApplication) {
        for delay in AppLaunchPresentationPolicy.recoveryDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Self.ensureMainWindowVisible(application: application)
            }
        }
    }

    private static func ensureMainWindowVisible(application: NSApplication) {
        let mainWindows = application.windows.filter { window in
            AppLaunchPresentationPolicy.isMainWindowCandidate(
                title: window.title,
                identifier: window.identifier?.rawValue,
                isPanel: window is NSPanel
            )
        }
        let hasVisibleMainWindow = mainWindows.contains { window in
            window.isVisible && !window.isMiniaturized
        }

        guard AppLaunchPresentationPolicy.shouldRecoverMainWindow(
            hasMainWindow: !mainWindows.isEmpty,
            hasVisibleMainWindow: hasVisibleMainWindow
        ) else {
            return
        }

        application.unhide(nil)
        application.activate(ignoringOtherApps: true)
        for window in mainWindows {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func installQuitAppleEventHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleQuitAppleEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEQuitApplication)
        )
    }

    @objc private func handleQuitAppleEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        AppTerminationCoordinator.prepareForTermination(application: .shared)
        NSApp.terminate(nil)
    }
}

enum AppTerminationState {
    private(set) static var isTerminating = false

    static func beginTermination() {
        isTerminating = true
    }

    #if DEBUG
    static func resetForTests() {
        isTerminating = false
    }
    #endif
}

enum AppTerminationCoordinator {
    static func prepareForTermination(application: NSApplication) {
        beginTerminationRequest()
        prepareModalSurfacesForTermination(application: application)
    }

    static func beginTerminationRequest() {
        AppTerminationState.beginTermination()
        NotificationCenter.default.post(name: .applicationTerminationRequested, object: nil)
    }

    static func prepareModalSurfacesForTermination(application: NSApplication) {
        if application.modalWindow != nil {
            application.abortModal()
        }
        dismissAttachedSheets(windows: application.windows)
    }

    static func dismissAttachedSheets(windows: [NSWindow]) {
        var dismissedSheetIDs: Set<ObjectIdentifier> = []

        func dismiss(_ sheet: NSWindow, from parent: NSWindow) {
            let sheetID = ObjectIdentifier(sheet)
            guard !dismissedSheetIDs.contains(sheetID) else {
                return
            }

            dismissedSheetIDs.insert(sheetID)
            parent.endSheet(sheet, returnCode: .cancel)
            sheet.orderOut(nil)
        }

        for window in windows {
            while let sheet = window.attachedSheet {
                guard !dismissedSheetIDs.contains(ObjectIdentifier(sheet)) else {
                    break
                }
                dismiss(sheet, from: window)
            }
        }

        for window in windows {
            if let sheetParent = window.sheetParent {
                dismiss(window, from: sheetParent)
            }
        }
    }
}

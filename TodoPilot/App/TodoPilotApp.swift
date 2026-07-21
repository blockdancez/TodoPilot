import AppKit
import SwiftUI

@main
struct TodoPilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment: AppEnvironment
    @StateObject private var statusIslandController: StatusIslandWindowController

    @MainActor
    init() {
        let environment = AppEnvironment.bootstrap()
        let statusIslandController = StatusIslandWindowController()
        _environment = StateObject(wrappedValue: environment)
        _statusIslandController = StateObject(wrappedValue: statusIslandController)
        AppLaunchStatusIslandBootstrap.configure(
            statusIslandController: statusIslandController,
            environment: environment
        )
    }

    var body: some Scene {
        mainApplicationScenes
    }

    @SceneBuilder
    private var mainApplicationScenes: some Scene {
        Window("TodoPilot", id: "main") {
            RootView()
                .environmentObject(environment)
                .environmentObject(environment.settingsStore)
                .background(MainWindowOpenerBridge().environmentObject(environment))
                .background(MainWindowConfigurator())
                .frame(minWidth: 980, minHeight: 660)
                .onAppear {
                    statusIslandController.configure(environment: environment)
                }
        }
        .defaultSize(width: 1180, height: 904)
        .windowStyle(.hiddenTitleBar)
        .commands {
            TodoPilotCommands()
        }

        MenuBarExtra("TodoPilot", image: "MenuBarIcon") {
            TodoPilotMenuBarCommands()
                .environmentObject(environment)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(environment)
                .environmentObject(environment.settingsStore)
                .frame(width: 980, height: 660)
        }
    }
}
private struct TodoPilotMenuBarCommands: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Button(environment.copy.showTodoPilot) {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
            environment.openMainWindowFromStatusIsland()
        }

        Button(environment.copy.quit) {
            AppTerminationCoordinator.prepareForTermination(application: NSApp)
            NSApp.terminate(nil)
        }
    }
}

private struct MainWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> MainWindowConfigurationView {
        MainWindowConfigurationView()
    }

    func updateNSView(_ nsView: MainWindowConfigurationView, context: Context) {
        nsView.configureWindow()
    }
}

private final class MainWindowConfigurationView: NSView {
    private weak var configuredWindow: NSWindow?
    private var closeHider: MainWindowCloseHider?
    private var didRepairWindowFrame = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    func configureWindow() {
        guard let window else {
            return
        }
        window.identifier = .todoPilotMainWindow
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(red: 0.97, green: 0.98, blue: 0.98, alpha: 1)
        window.isRestorable = false

        if configuredWindow !== window {
            configuredWindow = window
            closeHider = MainWindowCloseHider()
            didRepairWindowFrame = false
        }
        window.isReleasedWhenClosed = false
        window.delegate = closeHider
        repairWindowFrameIfNeeded(window)
    }

    private func repairWindowFrameIfNeeded(_ window: NSWindow) {
        guard !didRepairWindowFrame else {
            return
        }
        didRepairWindowFrame = true

        guard let visibleFrame = (window.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else {
            return
        }

        let maxWidth = max(760, visibleFrame.width - 48)
        let maxHeight = max(560, visibleFrame.height - 48)
        let minWidth = min(CGFloat(980), maxWidth)
        let minHeight = min(CGFloat(660), maxHeight)
        window.minSize = NSSize(width: minWidth, height: minHeight)

        var frame = window.frame
        let targetSize = NSSize(
            width: min(CGFloat(1180), maxWidth),
            height: min(CGFloat(904), maxHeight)
        )
        let needsResize = abs(frame.width - targetSize.width) > 1 || abs(frame.height - targetSize.height) > 1
        frame.size = targetSize

        let margin: CGFloat = 12
        let isOutsideVisibleFrame =
            frame.minX < visibleFrame.minX + margin ||
            frame.maxX > visibleFrame.maxX - margin ||
            frame.minY < visibleFrame.minY + margin ||
            frame.maxY > visibleFrame.maxY - margin

        guard needsResize || isOutsideVisibleFrame else {
            return
        }

        frame.origin = CGPoint(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.midY - frame.height / 2
        )
        window.setFrame(frame, display: true)
    }
}

final class MainWindowCloseHider: NSObject, NSWindowDelegate {
    private let isApplicationTerminating: () -> Bool

    init(isApplicationTerminating: @escaping () -> Bool = { AppTerminationState.isTerminating }) {
        self.isApplicationTerminating = isApplicationTerminating
        super.init()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !isApplicationTerminating() else {
            return true
        }

        sender.orderOut(nil)
        return false
    }
}

enum AppLaunchStatusIslandBootstrap {
    @MainActor
    static func configure(
        statusIslandController: StatusIslandWindowController,
        environment: AppEnvironment
    ) {
        guard AppLaunchPresentationPolicy.configuresStatusIslandBeforeMainWindowAppears else {
            return
        }

        DispatchQueue.main.async {
            statusIslandController.configure(environment: environment)
        }
    }
}

struct AppLaunchPresentationPolicy: Equatable {
    static let configuresStatusIslandBeforeMainWindowAppears = true
    static let recoveryDelays: [TimeInterval] = [0, 0.2, 0.8]

    static func shouldRecoverMainWindow(
        hasMainWindow: Bool,
        hasVisibleMainWindow: Bool
    ) -> Bool {
        hasMainWindow && !hasVisibleMainWindow
    }

    static func isMainWindowCandidate(
        title: String,
        identifier: String?,
        isPanel: Bool
    ) -> Bool {
        guard !isPanel else {
            return false
        }
        return identifier == "TodoPilotMainWindow" || title == "TodoPilot"
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let todoPilotMainWindow = NSUserInterfaceItemIdentifier("TodoPilotMainWindow")
}

private struct MainWindowOpenerBridge: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                environment.setMainWindowOpener {
                    openWindow(id: "main")
                }
            }
    }
}

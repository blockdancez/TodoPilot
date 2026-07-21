import AppKit
import Carbon
import Foundation

enum GlobalHotKeyRegistrationError: Error, Equatable {
    case shortcutInUse(CaptureHotKey)
    case handlerUnavailable
}

@MainActor
final class GlobalHotKeyMonitor {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var currentHotKey: CaptureHotKey?
    private var nextHotKeyID: UInt32 = 1
    private var action: (() -> Void)?

    func startCaptureHotKey(_ hotKey: CaptureHotKey, action: @escaping () -> Void) throws {
        let hotKey = hotKey.normalizedToPreset
        if let currentHotKey, currentHotKey.hasSamePhysicalShortcut(as: hotKey), hotKeyRef != nil {
            self.action = action
            self.currentHotKey = hotKey
            return
        }

        self.action = action
        GlobalHotKeyMonitorRegistry.shared.monitor = self
        try ensureEventHandlerInstalled()

        var newHotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x54445054), id: makeNextHotKeyID())
        let registerStatus = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newHotKeyRef
        )

        guard registerStatus == noErr, let newHotKeyRef else {
            throw GlobalHotKeyRegistrationError.shortcutInUse(hotKey)
        }

        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = newHotKeyRef
        currentHotKey = hotKey
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        currentHotKey = nil
    }

    func handleHotKeyPressed() {
        action?()
    }

    private func ensureEventHandlerInstalled() throws {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            GlobalHotKeyMonitorRegistry.handler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            throw GlobalHotKeyRegistrationError.handlerUnavailable
        }
    }

    private func makeNextHotKeyID() -> UInt32 {
        defer {
            nextHotKeyID = nextHotKeyID == UInt32.max ? 1 : nextHotKeyID + 1
        }
        return nextHotKeyID
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
}

private final class GlobalHotKeyMonitorRegistry {
    static let shared = GlobalHotKeyMonitorRegistry()

    @MainActor weak var monitor: GlobalHotKeyMonitor?

    static let handler: EventHandlerUPP = { _, _, _ in
        Task { @MainActor in
            GlobalHotKeyMonitorRegistry.shared.monitor?.handleHotKeyPressed()
        }
        return noErr
    }
}

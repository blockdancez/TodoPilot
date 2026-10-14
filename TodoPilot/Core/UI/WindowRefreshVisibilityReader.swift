import AppKit
import SwiftUI

/// 只监听窗口状态变化，避免用轮询判断界面是否需要刷新。
struct WindowRefreshVisibilityReader: NSViewRepresentable {
    let onVisibilityChanged: (Bool) -> Void

    func makeNSView(context: Context) -> WindowRefreshVisibilityView {
        let view = WindowRefreshVisibilityView()
        view.onVisibilityChanged = onVisibilityChanged
        return view
    }

    func updateNSView(_ nsView: WindowRefreshVisibilityView, context: Context) {
        nsView.onVisibilityChanged = onVisibilityChanged
        nsView.updateVisibility()
    }

    static func dismantleNSView(_ nsView: WindowRefreshVisibilityView, coordinator: Void) {
        nsView.stopObserving()
    }
}

@MainActor
final class WindowRefreshVisibilityView: NSView {
    var onVisibilityChanged: ((Bool) -> Void)?
    private var visibilityObservation: NSKeyValueObservation?
    private var observerTokens: [NSObjectProtocol] = []
    private var reportedVisibility: Bool?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObserving()
        guard let window else {
            reportVisibility(false)
            return
        }

        visibilityObservation = window.observe(\.isVisible, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateVisibility() }
        }
        // 部分显示路径不发送可见性 KVO；窗口更新/曝光/获得焦点也重新核对真实状态。
        for name in [NSWindow.didUpdateNotification, NSWindow.didExposeNotification,
                     NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification,
                     NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
            observerTokens.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.updateVisibility() }
            })
        }
        for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            observerTokens.append(NotificationCenter.default.addObserver(
                forName: name, object: NSApp, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.updateVisibility() }
            })
        }
        updateVisibility()
    }

    deinit {
        observerTokens.forEach(NotificationCenter.default.removeObserver)
    }

    func stopObserving() {
        visibilityObservation = nil
        observerTokens.forEach(NotificationCenter.default.removeObserver)
        observerTokens.removeAll()
    }

    func updateVisibility() {
        let visible = window.map {
            $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible)
        } ?? false
        reportVisibility(visible)
    }

    private func reportVisibility(_ visible: Bool) {
        guard reportedVisibility != visible else { return }
        reportedVisibility = visible
        // 延后一轮发布，避免在 SwiftUI 挂载视图期间修改其状态。
        DispatchQueue.main.async { [weak self] in self?.onVisibilityChanged?(visible) }
    }
}

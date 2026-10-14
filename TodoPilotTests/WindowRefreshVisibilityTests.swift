import AppKit
import XCTest
@testable import TodoPilot

@MainActor
final class WindowRefreshVisibilityTests: XCTestCase {
    func testHiddenWindowStopsVisualRefreshAndShowingItRestoresRefresh() async {
        NSApp.activate(ignoringOtherApps: true)
        let window = makeWindow()
        defer { window.orderOut(nil); window.contentView = nil }
        let probe = WindowRefreshVisibilityView()
        // 空白无像素的窗口可能被系统判为完全遮挡；提供真实可见内容再检验遮挡通知。
        probe.wantsLayer = true
        probe.layer?.backgroundColor = NSColor.white.cgColor
        var visible = false
        probe.onVisibilityChanged = { visible = $0 }
        window.contentView = probe

        window.makeKeyAndOrderFront(nil)
        // 测试宿主可能未获前台焦点；显式展示真实窗口，仍验证系统遮挡和隐藏状态。
        window.orderFrontRegardless()
        // XCTest 不执行完整 NSApp 的逐事件 updateWindows 阶段，主动推进真实窗口更新。
        window.update()
        await waitUntil { visible }
        XCTAssertTrue(visible, "visible=\(window.isVisible) occlusion=\(window.occlusionState.rawValue) mini=\(window.isMiniaturized) attached=\(probe.window === window) appHidden=\(NSApp.isHidden) active=\(NSApp.isActive)")

        window.orderOut(nil)
        window.update()
        await waitUntil { !visible }
        XCTAssertFalse(visible)

        window.makeKeyAndOrderFront(nil)
        // 测试宿主可能未获前台焦点；显式展示真实窗口，仍验证系统遮挡和隐藏状态。
        window.orderFrontRegardless()
        // XCTest 不执行完整 NSApp 的逐事件 updateWindows 阶段，主动推进真实窗口更新。
        window.update()
        await waitUntil { visible }
        XCTAssertTrue(visible, "visible=\(window.isVisible) occlusion=\(window.occlusionState.rawValue) mini=\(window.isMiniaturized) attached=\(probe.window === window) appHidden=\(NSApp.isHidden) active=\(NSApp.isActive)")
    }

    func testDetachedReaderDoesNotKeepObservingItsFormerWindow() async {
        NSApp.activate(ignoringOtherApps: true)
        let window = makeWindow()
        defer { window.orderOut(nil) }
        let probe = WindowRefreshVisibilityView()
        // 空白无像素的窗口可能被系统判为完全遮挡；提供真实可见内容再检验遮挡通知。
        probe.wantsLayer = true
        probe.layer?.backgroundColor = NSColor.white.cgColor
        var events: [Bool] = []
        probe.onVisibilityChanged = { events.append($0) }
        window.contentView = probe
        window.makeKeyAndOrderFront(nil)
        // 测试宿主可能未获前台焦点；显式展示真实窗口，仍验证系统遮挡和隐藏状态。
        window.orderFrontRegardless()
        // XCTest 不执行完整 NSApp 的逐事件 updateWindows 阶段，主动推进真实窗口更新。
        window.update()
        await waitUntil { events.last == true }
        XCTAssertEqual(events.last, true, "visible=\(window.isVisible) occlusion=\(window.occlusionState.rawValue) attached=\(probe.window === window) appHidden=\(NSApp.isHidden)")

        window.contentView = nil
        await waitUntil { events.last == false }
        XCTAssertEqual(events.last, false)
        let detachedEvents = events
        window.orderOut(nil)
        window.makeKeyAndOrderFront(nil)
        // 测试宿主可能未获前台焦点；显式展示真实窗口，仍验证系统遮挡和隐藏状态。
        window.orderFrontRegardless()
        // XCTest 不执行完整 NSApp 的逐事件 updateWindows 阶段，主动推进真实窗口更新。
        window.update()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(events, detachedEvents)
    }

    private func makeWindow() -> NSWindow {
        // 非激活面板在测试宿主无法获得前台焦点时也能显示；仍使用真实 NSWindow 状态。
        let window = NSPanel(
            contentRect: NSRect(x: 120, y: 120, width: 100, height: 100),
            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false
        )
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        // 测试窗口不使用系统出入场变换，被测刷新监听仍覆盖真实显示和隐藏。
        window.animationBehavior = .none
        // 测试在用户切换 Space 或全屏应用时仍能展示窗口，继续验证真实遮挡状态。
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = .statusBar
        return window
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

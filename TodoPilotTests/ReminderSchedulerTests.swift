import AppKit
import SwiftUI
import XCTest
@testable import TodoPilot

final class ReminderSchedulerTests: XCTestCase {
    override func tearDown() {
        AppTerminationState.resetForTests()
        super.tearDown()
    }

    func testEngineSoundDataSpansRequestedFlightDuration() {
        let duration = FlightReminderTiming.engineAudioDuration
        let data = FlightSoundWaveform.makeEngineSoundData(duration: duration)
        let sampleCount = Int(Double(FlightSoundWaveform.sampleRate) * duration)

        XCTAssertGreaterThan(FlightReminderTiming.engineAudioDuration, FlightReminderTiming.flightDuration)
        XCTAssertEqual(data.prefix(4), Data("RIFF".utf8))
        XCTAssertEqual(wavUInt16(data, at: 22), 2)
        XCTAssertEqual(wavUInt32(data, at: 24), UInt32(FlightSoundWaveform.sampleRate))
        XCTAssertEqual(data.count, 44 + sampleCount * 2 * 2)

        let tailStart = Int(Double(FlightSoundWaveform.sampleRate) * (duration - 0.85))
        let tailEnd = Int(Double(FlightSoundWaveform.sampleRate) * (duration - 0.65))
        XCTAssertGreaterThan(stereoPcmEnergy(data, sampleRange: tailStart..<tailEnd), 10_000)
    }

    func testHornSoundDataUsesCarHornDoubleTap() {
        let data = FlightSoundWaveform.makeHornSoundData()
        let firstTapStart = Int(Double(FlightSoundWaveform.sampleRate) * 0.065)
        let firstTapEnd = Int(Double(FlightSoundWaveform.sampleRate) * 0.135)
        let gapStartSample = Int(Double(FlightSoundWaveform.sampleRate) * FlightSoundWaveform.carHornGapStart)
        let gapEndSample = Int(Double(FlightSoundWaveform.sampleRate) * FlightSoundWaveform.carHornGapEnd)
        let secondTapStart = Int(Double(FlightSoundWaveform.sampleRate) * 0.325)
        let secondTapEnd = Int(Double(FlightSoundWaveform.sampleRate) * 0.405)
        let sampleCount = Int(Double(FlightSoundWaveform.sampleRate) * FlightSoundWaveform.hornDuration)

        XCTAssertLessThan(FlightSoundWaveform.hornDuration, 0.6)
        XCTAssertGreaterThan(FlightSoundWaveform.carHornLowFrequency, 620)
        XCTAssertLessThan(FlightSoundWaveform.carHornLowFrequency, 720)
        XCTAssertGreaterThan(FlightSoundWaveform.carHornHighFrequency, 800)
        XCTAssertLessThan(FlightSoundWaveform.carHornHighFrequency, 900)
        XCTAssertGreaterThan(FlightSoundWaveform.carHornGapEnd, FlightSoundWaveform.carHornGapStart)
        XCTAssertEqual(data.prefix(4), Data("RIFF".utf8))
        XCTAssertEqual(wavUInt16(data, at: 22), 1)
        XCTAssertEqual(data.count, 44 + sampleCount * 2)
        XCTAssertGreaterThan(pcmEnergy(data, sampleRange: firstTapStart..<firstTapEnd), 50_000)
        XCTAssertLessThan(pcmEnergy(data, sampleRange: gapStartSample..<gapEndSample), 100)
        XCTAssertGreaterThan(pcmEnergy(data, sampleRange: secondTapStart..<secondTapEnd), 50_000)
    }

    func testFlightReminderBannerStyleUsesBlueForNormalAndRedForDeadline() {
        let normal = FlightReminderBannerStyle.normal.ribbonPalette
        let deadline = FlightReminderBannerStyle.deadline.ribbonPalette

        XCTAssertGreaterThan(normal.blue, normal.red)
        XCTAssertGreaterThan(normal.green, normal.red)
        XCTAssertGreaterThan(deadline.red, deadline.green)
        XCTAssertGreaterThan(deadline.red, deadline.blue)
        let success = FlightReminderBannerStyle.agentSuccess.ribbonPalette
        let warning = FlightReminderBannerStyle.agentWarning.ribbonPalette
        XCTAssertGreaterThan(success.green, success.red)
        XCTAssertGreaterThan(warning.red, warning.blue)
    }

    func testAgentFlagThemesUseReadableProviderSpecificPalettes() {
        let themes: [FlightReminderFlagTheme] = [
            .claudeCode,
            .codex,
            .cursor,
            .mixedAgents
        ]

        for theme in themes {
            let background = theme.backgroundPalette(fallback: .agentSuccess)
            let foreground = theme.foregroundPalette
            XCTAssertGreaterThanOrEqual(
                contrastRatio(background, foreground),
                4.5,
                "\(theme) flag text must remain readable"
            )
        }

        XCTAssertNotEqual(
            FlightReminderFlagTheme.claudeCode.backgroundPalette(fallback: .normal),
            FlightReminderFlagTheme.codex.backgroundPalette(fallback: .normal)
        )
        XCTAssertNotEqual(
            FlightReminderFlagTheme.codex.backgroundPalette(fallback: .normal),
            FlightReminderFlagTheme.cursor.backgroundPalette(fallback: .normal)
        )
    }

    func testStandardFlagThemePreservesExistingReminderPalette() {
        XCTAssertEqual(
            FlightReminderFlagTheme.standard.backgroundPalette(fallback: .normal),
            FlightReminderBannerStyle.normal.ribbonPalette
        )
        XCTAssertEqual(
            FlightReminderFlagTheme.standard.backgroundPalette(fallback: .deadline),
            FlightReminderBannerStyle.deadline.ribbonPalette
        )
        XCTAssertEqual(
            FlightReminderFlagTheme.standard.foregroundPalette,
            FlightReminderBannerPalette(red: 1, green: 1, blue: 1)
        )
    }

    func testAgentProviderIconDescriptorsUseOfficialApplicationsAndFallbackAssets() {
        let claude = AgentProviderIconDescriptor.descriptor(for: .claudeCode)
        let codex = AgentProviderIconDescriptor.descriptor(for: .codex)
        let cursor = AgentProviderIconDescriptor.descriptor(for: .cursor)

        XCTAssertEqual(claude.bundleIdentifiers.first, "com.anthropic.claudefordesktop")
        XCTAssertEqual(claude.applicationNames.first, "Claude")
        XCTAssertEqual(claude.fallbackAssetName, "AgentIconClaudeCode")
        XCTAssertEqual(codex.bundleIdentifiers.first, "com.openai.codex")
        XCTAssertTrue(codex.applicationNames.contains("ChatGPT"))
        XCTAssertEqual(codex.fallbackAssetName, "AgentIconCodex")
        XCTAssertEqual(cursor.bundleIdentifiers.first, "com.todesktop.230313mzl4w4u92")
        XCTAssertEqual(cursor.applicationNames.first, "Cursor")
        XCTAssertEqual(cursor.fallbackAssetName, "AgentIconCursor")
    }

    func testAgentProviderIconResolverPrefersInstalledApplicationThenFallsBackToAsset() throws {
        let installed = NSImage(size: NSSize(width: 64, height: 64))
        let fallback = NSImage(size: NSSize(width: 32, height: 32))
        let appURL = URL(fileURLWithPath: "/Applications/Claude.app")
        var requestedBundleIdentifiers: [String] = []
        var requestedAssetNames: [String] = []
        let installedResolver = AgentProviderIconResolver(
            applicationURL: { identifier in
                requestedBundleIdentifiers.append(identifier)
                return identifier == "com.anthropic.claudefordesktop" ? appURL : nil
            },
            fileIcon: { url in url == appURL ? installed : nil },
            assetImage: { name in
                requestedAssetNames.append(name)
                return fallback
            }
        )

        XCTAssertTrue(try XCTUnwrap(installedResolver.image(for: .claudeCode)) === installed)
        XCTAssertEqual(requestedBundleIdentifiers, ["com.anthropic.claudefordesktop"])
        XCTAssertTrue(requestedAssetNames.isEmpty)

        let fallbackResolver = AgentProviderIconResolver(
            applicationURL: { _ in nil },
            fileIcon: { _ in nil },
            assetImage: { name in
                requestedAssetNames.append(name)
                return name == "AgentIconCodex" ? fallback : nil
            }
        )
        XCTAssertTrue(try XCTUnwrap(fallbackResolver.image(for: .codex)) === fallback)
        XCTAssertEqual(requestedAssetNames.last, "AgentIconCodex")
    }

    func testBundledAgentIconFallbackAssetsAreAvailable() {
        for provider in AgentProvider.allCases {
            let assetName = AgentProviderIconDescriptor.descriptor(for: provider).fallbackAssetName
            XCTAssertNotNil(NSImage(named: NSImage.Name(assetName)), "Missing bundled icon: \(assetName)")
        }
    }

    func testStatusIslandAgentIconPolicyResolvesProviderOnlyForLinkedAgentTask() {
        let taskID = UUID()
        let agentTask = TodoTask(id: taskID, title: "检查实现", source: .codeAgent)
        let manualTask = TodoTask(id: taskID, title: "手动任务", source: .manual)
        let run = AgentRun(
            taskID: taskID,
            provider: .codex,
            sessionIdentityHash: "session",
            startedAt: Date(timeIntervalSince1970: 1),
            lastEventAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(StatusIslandAgentIconPolicy.provider(for: agentTask, run: run), .codex)
        XCTAssertNil(StatusIslandAgentIconPolicy.provider(for: manualTask, run: run))
        XCTAssertNil(StatusIslandAgentIconPolicy.provider(for: agentTask, run: nil))
    }

    func testStatusIslandAgentIconPolicyUsesCompactAndExpandedSizes() {
        XCTAssertEqual(StatusIslandAgentIconPolicy.expandedTaskIconSize, 16)
        XCTAssertEqual(StatusIslandAgentIconPolicy.compactIconSize(isNotchedScreen: true), 11)
        XCTAssertEqual(StatusIslandAgentIconPolicy.compactIconSize(isNotchedScreen: false), 14)
    }

    func testAgentPresentationNormalizesIconProvidersWithoutChangingStandardReminder() {
        let presentation = FlightReminderPresentation(
            primaryTitle: "打开 Agent",
            kind: .agentSuccess,
            flagTheme: .mixedAgents,
            agentProviders: [.cursor, .claudeCode, .cursor]
        )

        XCTAssertEqual(presentation.agentProviders, [.claudeCode, .cursor])
        XCTAssertTrue(FlightReminderPresentation.task(primaryTitle: "完成").agentProviders.isEmpty)
    }

    func testAgentPresentationMapsOutcomeToIconBadgeWithoutChangingStandardReminder() {
        let success = FlightReminderPresentation(
            primaryTitle: "打开 Agent",
            kind: .agentSuccess,
            flagTheme: .codex,
            agentProviders: [.codex]
        )
        let warning = FlightReminderPresentation(
            primaryTitle: "打开 Agent",
            kind: .agentWarning,
            flagTheme: .cursor,
            agentProviders: [.cursor]
        )
        let task = FlightReminderPresentation.task(primaryTitle: "完成")

        XCTAssertEqual(success.agentOutcomeBadge, .success)
        XCTAssertEqual(warning.agentOutcomeBadge, .warning)
        XCTAssertNil(task.agentOutcomeBadge)
    }

    func testFlightReminderActionsKeepTaskPresentationCompatibility() {
        let actions = FlightReminderActions(
            completeTitle: "Done",
            snoozeTitle: "Later",
            complete: { _ in },
            snooze10Minutes: { _ in },
            openDetails: { _ in },
            muteAll: {},
            dismiss: { _ in }
        )

        XCTAssertEqual(actions.presentation, .task(primaryTitle: "Done"))
        XCTAssertEqual(actions.presentation.flagTheme, .standard)
    }

    func testFlightReminderOptionsKeepDemoAndStandardBannerNormal() {
        XCTAssertEqual(ReminderScheduleOptions.standard.bannerStyle, .normal)
        XCTAssertEqual(ReminderScheduleOptions.demo.bannerStyle, .normal)
    }

    func testLimiterAllowsTwoRemindersPerTaskWithinThirtyMinutes() {
        var limiter = FlightReminderLimiter()
        let taskID = UUID()
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(limiter.reserveSlot(for: taskID, at: now))
        XCTAssertTrue(limiter.reserveSlot(for: taskID, at: now.addingTimeInterval(60)))
        XCTAssertFalse(limiter.reserveSlot(for: taskID, at: now.addingTimeInterval(120)))
        XCTAssertTrue(limiter.reserveSlot(for: taskID, at: now.addingTimeInterval(31 * 60)))
    }

    func testLimiterCapsGlobalRemindersAtThreePerHour() {
        var limiter = FlightReminderLimiter()
        let now = Date(timeIntervalSince1970: 2_000)

        XCTAssertTrue(limiter.reserveSlot(for: UUID(), at: now))
        XCTAssertTrue(limiter.reserveSlot(for: UUID(), at: now.addingTimeInterval(60)))
        XCTAssertTrue(limiter.reserveSlot(for: UUID(), at: now.addingTimeInterval(120)))
        XCTAssertFalse(limiter.reserveSlot(for: UUID(), at: now.addingTimeInterval(180)))
        XCTAssertTrue(limiter.reserveSlot(for: UUID(), at: now.addingTimeInterval(61 * 60)))
    }

    func testLimiterUsesConfiguredFrequency() {
        var lowLimiter = FlightReminderLimiter()
        var highLimiter = FlightReminderLimiter()
        let taskID = UUID()
        let now = Date(timeIntervalSince1970: 3_000)

        XCTAssertTrue(lowLimiter.reserveSlot(for: taskID, at: now, frequency: .low))
        XCTAssertFalse(lowLimiter.reserveSlot(for: taskID, at: now.addingTimeInterval(60), frequency: .low))

        XCTAssertTrue(highLimiter.reserveSlot(for: taskID, at: now, frequency: .high))
        XCTAssertTrue(highLimiter.reserveSlot(for: taskID, at: now.addingTimeInterval(60), frequency: .high))
        XCTAssertTrue(highLimiter.reserveSlot(for: taskID, at: now.addingTimeInterval(120), frequency: .high))
        XCTAssertFalse(highLimiter.reserveSlot(for: taskID, at: now.addingTimeInterval(180), frequency: .high))
    }

    func testFlightPlanePropellerAnchorsNearNose() throws {
        let layout = PixelPlaneMarkLayout(
            containerSize: CGSize(width: 190, height: 120),
            variant: .flight,
            animated: true
        )

        let propellerFrame = try XCTUnwrap(layout.propellerFrame)
        XCTAssertEqual(propellerFrame.midX, layout.imageFrame.minX + layout.imageFrame.width * 0.961, accuracy: 0.5)
        XCTAssertEqual(propellerFrame.midY, layout.imageFrame.minY + layout.imageFrame.height * 0.630, accuracy: 0.5)
        XCTAssertLessThan(propellerFrame.height, layout.imageFrame.height * 0.7)
        XCTAssertEqual(layout.planeBodyFrame, layout.imageFrame)
    }

    func testStatusIslandPlaneShowsCompactAnimatedPropeller() throws {
        let layout = PixelPlaneMarkLayout(
            containerSize: CGSize(width: 44, height: 28),
            variant: .statusIsland,
            animated: true
        )

        let propellerFrame = try XCTUnwrap(layout.propellerFrame)
        XCTAssertGreaterThan(propellerFrame.midX, layout.imageFrame.midX)
        XCTAssertLessThanOrEqual(propellerFrame.height, layout.imageFrame.height)
        XCTAssertLessThanOrEqual(propellerFrame.width, 4)
        XCTAssertEqual(propellerFrame.midY, layout.imageFrame.minY + layout.imageFrame.height * 0.630, accuracy: 0.5)
        XCTAssertEqual(layout.planeBodyFrame, layout.imageFrame)
    }

    func testCompactPlaneDoesNotAddPropellerOverlayByDefault() {
        let layout = PixelPlaneMarkLayout(
            containerSize: CGSize(width: 38, height: 24),
            variant: .compact,
            animated: false
        )

        XCTAssertNil(layout.propellerFrame)
    }

    func testCapturePipelineEntryPolicyDoesNotOpenMainWindowBeforeSelection() {
        let policy = CapturePipelineEntryPolicy.floatingReview

        XCTAssertFalse(policy.opensMainWindowBeforeSelection)
        XCTAssertTrue(policy.presentsReviewAfterOCR)
    }

    func testRootSidebarLayoutConstrainsLocalizedContentInsideFixedWidth() {
        XCTAssertEqual(RootSidebarLayout.width, 270)
        XCTAssertEqual(
            RootSidebarLayout.headerContentWidth,
            RootSidebarLayout.width
                - RootSidebarLayout.headerLeadingPadding
                - RootSidebarLayout.headerTrailingPadding
        )
        XCTAssertEqual(
            RootSidebarLayout.sectionContentWidth,
            RootSidebarLayout.width - RootSidebarLayout.sectionHorizontalPadding * 2
        )
        XCTAssertGreaterThan(RootSidebarLayout.headerContentWidth, 0)
        XCTAssertGreaterThan(RootSidebarLayout.sectionContentWidth, 0)
    }

    func testTodayListLayoutDoesNotRequestWiderThanDefaultMainWindowContentArea() {
        let defaultMainWindowWidth: CGFloat = 1180
        let rootDividerWidth: CGFloat = 1
        let availableContentWidth = defaultMainWindowWidth - RootSidebarLayout.width - rootDividerWidth
        let todayContentWidth = TodayListLayout.contentWidth(for: availableContentWidth)
        let requestedWidth = todayContentWidth
            + TodayListLayout.leadingPadding
            + TodayListLayout.trailingPadding

        XCTAssertLessThanOrEqual(requestedWidth, availableContentWidth)
        XCTAssertEqual(todayContentWidth, 847)
        XCTAssertEqual(TodayListLayout.contentWidth(for: 1_400), TodayListLayout.maxContentWidth)
    }

    func testAppLaunchConfiguresStatusIslandBeforeMainWindowAppears() {
        XCTAssertTrue(AppLaunchPresentationPolicy.configuresStatusIslandBeforeMainWindowAppears)
    }

    func testAppLaunchRecoversHiddenMainWindowOnlyWhenNeeded() {
        XCTAssertTrue(AppLaunchPresentationPolicy.shouldRecoverMainWindow(
            hasMainWindow: true,
            hasVisibleMainWindow: false
        ))
        XCTAssertFalse(AppLaunchPresentationPolicy.shouldRecoverMainWindow(
            hasMainWindow: true,
            hasVisibleMainWindow: true
        ))
        XCTAssertFalse(AppLaunchPresentationPolicy.shouldRecoverMainWindow(
            hasMainWindow: false,
            hasVisibleMainWindow: false
        ))
    }

    func testAppLaunchMainWindowCandidateExcludesPanels() {
        XCTAssertTrue(AppLaunchPresentationPolicy.isMainWindowCandidate(
            title: "TodoPilot",
            identifier: nil,
            isPanel: false
        ))
        XCTAssertTrue(AppLaunchPresentationPolicy.isMainWindowCandidate(
            title: "",
            identifier: "TodoPilotMainWindow",
            isPanel: false
        ))
        XCTAssertFalse(AppLaunchPresentationPolicy.isMainWindowCandidate(
            title: "TodoPilot",
            identifier: nil,
            isPanel: true
        ))
    }

    func testCaptureOverlayLayoutKeepsPromptCenteredAndCancelBottomTrailing() {
        let bounds = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let layout = CaptureOverlayLayout(bounds: bounds)

        XCTAssertEqual(layout.promptCardRect.midX, bounds.midX, accuracy: 1)
        XCTAssertEqual(layout.promptCardRect.midY, bounds.midY, accuracy: 1)
        XCTAssertGreaterThan(layout.cancelButtonRect.minX, bounds.maxX - 180)
        XCTAssertGreaterThan(layout.cancelButtonRect.minY, bounds.maxY - 90)
        XCTAssertLessThanOrEqual(layout.cancelButtonRect.maxX, bounds.maxX - 20)
        XCTAssertLessThanOrEqual(layout.cancelButtonRect.maxY, bounds.maxY - 20)
        XCTAssertGreaterThanOrEqual(CaptureOverlayLayout.minimumSelectionSide, 8)
    }

    func testCaptureOverlayFocusPolicyPrefersScreenContainingMouse() {
        let primary = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let secondary = CGRect(x: -1440, y: -180, width: 1440, height: 900)
        let tertiary = CGRect(x: 1512, y: -120, width: 1920, height: 1080)

        XCTAssertEqual(
            CaptureOverlayFocusPolicy.preferredScreenIndex(
                screenFrames: [primary, secondary, tertiary],
                mouseLocation: CGPoint(x: -200, y: 120),
                mainScreenIndex: 0
            ),
            1
        )
        XCTAssertEqual(
            CaptureOverlayFocusPolicy.preferredScreenIndex(
                screenFrames: [primary, secondary, tertiary],
                mouseLocation: CGPoint(x: 2_000, y: 240),
                mainScreenIndex: 0
            ),
            2
        )
        XCTAssertEqual(
            CaptureOverlayFocusPolicy.preferredScreenIndex(
                screenFrames: [primary, secondary, tertiary],
                mouseLocation: CGPoint(x: 3_000, y: 3_000),
                mainScreenIndex: 0
            ),
            0
        )
    }

    func testCaptureOverlayStartupOrderShowsPreferredScreenFirst() {
        XCTAssertEqual(
            CaptureOverlayStartupOrderPolicy.orderedIndices(
                displayCount: 4,
                preferredScreenIndex: 2
            ),
            [2, 0, 1, 3]
        )
    }

    func testCaptureOverlayStartupOrderFallsBackToFirstScreen() {
        XCTAssertEqual(
            CaptureOverlayStartupOrderPolicy.orderedIndices(
                displayCount: 3,
                preferredScreenIndex: nil
            ),
            [0, 1, 2]
        )
        XCTAssertEqual(
            CaptureOverlayStartupOrderPolicy.orderedIndices(
                displayCount: 3,
                preferredScreenIndex: 9
            ),
            [0, 1, 2]
        )
    }

    func testCaptureOverlayWindowPolicyJoinsAllDisplaysAndFullscreenSpaces() {
        let behavior = CaptureOverlayWindowPolicy.collectionBehavior

        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.canJoinAllApplications))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(behavior.contains(.stationary))
        XCTAssertTrue(behavior.contains(.ignoresCycle))
        XCTAssertEqual(CaptureOverlayWindowPolicy.level, .screenSaver)
    }

    func testCaptureOverlayDisplayKeepsEachExternalScreenFrame() {
        let primary = CaptureOverlayDisplay(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            backingScaleFactor: 2,
            isMain: true
        )
        let topExternal = CaptureOverlayDisplay(
            id: 2,
            frame: CGRect(x: -91, y: 1117, width: 1920, height: 1080),
            backingScaleFactor: 2,
            isMain: false
        )
        let sidePortraitExternal = CaptureOverlayDisplay(
            id: 3,
            frame: CGRect(x: -1171, y: -21, width: 1080, height: 1920),
            backingScaleFactor: 2,
            isMain: false
        )

        XCTAssertEqual(primary.contentBounds, CGRect(x: 0, y: 0, width: 1728, height: 1117))
        XCTAssertEqual(topExternal.contentBounds, CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(sidePortraitExternal.contentBounds, CGRect(x: 0, y: 0, width: 1080, height: 1920))
        XCTAssertEqual(
            CaptureOverlayScreenPlacement(screenFrame: topExternal.frame)
                .globalSelection(from: CGRect(x: 12, y: 20, width: 100, height: 50)),
            CGRect(x: -79, y: 2127, width: 100, height: 50)
        )
        XCTAssertEqual(
            CaptureOverlayScreenPlacement(screenFrame: sidePortraitExternal.frame)
                .globalSelection(from: CGRect(x: 30, y: 80, width: 160, height: 120)),
            CGRect(x: -1141, y: 1699, width: 160, height: 120)
        )
    }

    func testCaptureOverlayScreenPlacementHandlesOffsetSecondaryScreen() {
        let placement = CaptureOverlayScreenPlacement(
            screenFrame: CGRect(x: -1440, y: -180, width: 1440, height: 900)
        )
        let selection = CGRect(x: 100, y: 120, width: 320, height: 180)

        XCTAssertEqual(
            placement.contentBounds,
            CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
        XCTAssertEqual(
            placement.globalSelection(from: selection),
            CGRect(x: -1340, y: 420, width: 320, height: 180)
        )
        XCTAssertEqual(
            placement.pixelCropRect(
                from: selection,
                imageSize: CGSize(width: 2880, height: 1800)
            ),
            CGRect(x: 200, y: 240, width: 640, height: 360)
        )
    }

    func testFloatingOCRReviewKeepsPanelOpenForConfirmation() {
        XCTAssertTrue(OCRReviewPresentationContext.sheet.dismissesHostAfterAction)
        XCTAssertFalse(OCRReviewPresentationContext.floatingPanel.dismissesHostAfterAction)
    }

    func testFloatingCapturePanelChromeDoesNotExposeDuplicateWindowControls() {
        let chrome = FloatingCapturePanelChromePolicy.modal

        XCTAssertTrue(chrome.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(chrome.styleMask.contains(.titled))
        XCTAssertFalse(chrome.styleMask.contains(.closable))
        XCTAssertFalse(chrome.exposesSystemWindowControls)
        XCTAssertFalse(chrome.isOpaque)
        XCTAssertFalse(chrome.hasSystemShadow)
        XCTAssertTrue(chrome.isMovableByWindowBackground)
    }

    func testFloatingCapturePanelPresentationSupportsFullscreenSpaces() {
        let behavior = FloatingCapturePanelPresentationPolicy.collectionBehavior

        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.canJoinAllApplications))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(behavior.contains(.stationary))
        XCTAssertTrue(behavior.contains(.ignoresCycle))
        XCTAssertFalse(behavior.contains(.transient))
        XCTAssertGreaterThan(
            FloatingCapturePanelPresentationPolicy.level.rawValue,
            NSWindow.Level.statusBar.rawValue
        )
    }

    func testFloatingCapturePanelCentersOnSelectedDisplayFrame() {
        let panelSize = CGSize(width: 1100, height: 700)
        let frame = FloatingCapturePanelPresentationPolicy.centeredFrame(
            size: panelSize,
            in: CGRect(x: -1440, y: -180, width: 1440, height: 900)
        )

        XCTAssertEqual(frame, CGRect(x: -1270, y: -80, width: 1100, height: 700))
    }

    func testTodoPilotModalShellUsesFooterActionsInsteadOfDuplicateHeaderCloseByDefault() {
        XCTAssertFalse(TodoPilotModalShellChromePolicy.contentDialog.showsHeaderCloseButton)
    }

    func testContentFocusedModalLayoutKeepsShadowInsideHostFrame() {
        let layout = TodoPilotModalShellLayout.contentFocusedFloating

        XCTAssertEqual(layout.outerRenderInset, 24)
        XCTAssertEqual(
            layout.outerFrameSize(for: CGSize(width: 820, height: 680)),
            CGSize(width: 868, height: 728)
        )
    }

    func testSheetEmbeddedModalLayoutDoesNotAddASecondOuterContainer() {
        let layout = TodoPilotModalShellLayout.designReferenceFloating

        XCTAssertEqual(layout.outerRenderInset, 0)
        XCTAssertEqual(
            layout.outerFrameSize(for: CGSize(width: 900, height: 620)),
            CGSize(width: 900, height: 620)
        )
    }

    func testFlightReminderTriggerPolicyAllowsProductTriggers() {
        XCTAssertTrue(FlightReminderTriggerPolicy.allows(reason: FlightReminderTriggerPolicy.dueTaskReminder))
        XCTAssertTrue(FlightReminderTriggerPolicy.allows(reason: FlightReminderTriggerPolicy.demoFlight))
        XCTAssertTrue(FlightReminderTriggerPolicy.allows(reason: FlightReminderTriggerPolicy.manualTaskCreated))
        XCTAssertTrue(FlightReminderTriggerPolicy.allows(reason: FlightReminderTriggerPolicy.taskEdited))
        XCTAssertTrue(FlightReminderTriggerPolicy.allows(reason: FlightReminderTriggerPolicy.nextActionChanged))
        XCTAssertTrue(FlightReminderTriggerPolicy.allows(reason: FlightReminderTriggerPolicy.taskConfirmed))

        XCTAssertFalse(FlightReminderTriggerPolicy.allows(reason: "unsupported_trigger"))
    }

    func testFlightReminderTriggerPolicyDedupesOnlyProductTriggers() {
        XCTAssertTrue(FlightReminderTriggerPolicy.dedupesRecentProductTrigger(reason: FlightReminderTriggerPolicy.manualTaskCreated))
        XCTAssertTrue(FlightReminderTriggerPolicy.dedupesRecentProductTrigger(reason: FlightReminderTriggerPolicy.taskEdited))
        XCTAssertTrue(FlightReminderTriggerPolicy.dedupesRecentProductTrigger(reason: FlightReminderTriggerPolicy.nextActionChanged))
        XCTAssertTrue(FlightReminderTriggerPolicy.dedupesRecentProductTrigger(reason: FlightReminderTriggerPolicy.taskConfirmed))

        XCTAssertFalse(FlightReminderTriggerPolicy.dedupesRecentProductTrigger(reason: FlightReminderTriggerPolicy.dueTaskReminder))
        XCTAssertFalse(FlightReminderTriggerPolicy.dedupesRecentProductTrigger(reason: FlightReminderTriggerPolicy.demoFlight))
        XCTAssertGreaterThanOrEqual(FlightReminderTriggerPolicy.productTriggerDedupeWindow, 1)
    }

    func testDueTaskReminderPolicyUsesConfiguredLeadTime() {
        let now = Date(timeIntervalSince1970: 10_000)
        let task = TodoTask(
            title: "Due in one hour",
            dueAt: now.addingTimeInterval(60 * 60),
            createdAt: now.addingTimeInterval(-24 * 60 * 60),
            updatedAt: now.addingTimeInterval(-24 * 60 * 60)
        )

        let tenMinuteCandidates = DueTaskReminderPolicy.dueCandidates(
            tasks: [task],
            leadTime: .tenMinutes,
            now: now,
            hasReminded: { _ in false }
        )
        let oneHourCandidates = DueTaskReminderPolicy.dueCandidates(
            tasks: [task],
            leadTime: .oneHour,
            now: now,
            hasReminded: { _ in false }
        )

        XCTAssertTrue(tenMinuteCandidates.isEmpty)
        XCTAssertEqual(oneHourCandidates.first?.task.id, task.id)
        XCTAssertEqual(oneHourCandidates.first?.triggerAt, now)
        XCTAssertEqual(oneHourCandidates.first?.phase, .lead)
    }

    func testDueTaskReminderPolicyExcludesCompletedDeletedAndUndatedTasks() {
        let now = Date(timeIntervalSince1970: 20_000)
        let dueAt = now.addingTimeInterval(5 * 60)
        let createdAt = now.addingTimeInterval(-24 * 60 * 60)
        let openTask = TodoTask(title: "Open", dueAt: dueAt, createdAt: createdAt, updatedAt: createdAt)
        let doneTask = TodoTask(title: "Done", dueAt: dueAt, status: .done, createdAt: createdAt, updatedAt: createdAt)
        let deletedTask = TodoTask(title: "Deleted", dueAt: dueAt, createdAt: createdAt, updatedAt: createdAt, deletedAt: now)
        let noDueTask = TodoTask(title: "No due", createdAt: createdAt, updatedAt: createdAt)

        let candidates = DueTaskReminderPolicy.dueCandidates(
            tasks: [doneTask, deletedTask, noDueTask, openTask],
            leadTime: .tenMinutes,
            now: now,
            hasReminded: { _ in false }
        )

        XCTAssertEqual(candidates.map(\.task.id), [openTask.id])
    }

    func testDueTaskReminderPolicySkipsAlreadyRemindedKey() throws {
        let now = Date(timeIntervalSince1970: 30_000)
        let task = TodoTask(
            title: "Already reminded",
            dueAt: now.addingTimeInterval(8 * 60),
            createdAt: now.addingTimeInterval(-24 * 60 * 60),
            updatedAt: now.addingTimeInterval(-24 * 60 * 60)
        )
        let key = try XCTUnwrap(DueTaskReminderPolicy.reminderKey(for: task, leadTime: .tenMinutes))

        let candidates = DueTaskReminderPolicy.dueCandidates(
            tasks: [task],
            leadTime: .tenMinutes,
            now: now,
            hasReminded: { $0 == key }
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    func testDueTaskReminderPolicyKeyChangesWhenDueTimeOrLeadTimeChanges() throws {
        let now = Date(timeIntervalSince1970: 40_000)
        let original = TodoTask(
            title: "Original",
            dueAt: now,
            createdAt: now.addingTimeInterval(-24 * 60 * 60),
            updatedAt: now.addingTimeInterval(-24 * 60 * 60)
        )
        var edited = original
        edited.dueAt = now.addingTimeInterval(60)

        let originalTenMinuteKey = try XCTUnwrap(DueTaskReminderPolicy.reminderKey(for: original, leadTime: .tenMinutes))
        let editedTenMinuteKey = try XCTUnwrap(DueTaskReminderPolicy.reminderKey(for: edited, leadTime: .tenMinutes))
        let originalThirtyMinuteKey = try XCTUnwrap(DueTaskReminderPolicy.reminderKey(for: original, leadTime: .thirtyMinutes))
        let originalDeadlineKey = try XCTUnwrap(DueTaskReminderPolicy.reminderKey(for: original, leadTime: .tenMinutes, phase: .deadline))
        let originalDeadlineKeyAfterLeadChange = try XCTUnwrap(DueTaskReminderPolicy.reminderKey(for: original, leadTime: .thirtyMinutes, phase: .deadline))

        XCTAssertNotEqual(originalTenMinuteKey, editedTenMinuteKey)
        XCTAssertNotEqual(originalTenMinuteKey, originalThirtyMinuteKey)
        XCTAssertEqual(originalDeadlineKey, originalDeadlineKeyAfterLeadChange)
    }

    func testDueTaskReminderPolicyReturnsNextFutureCheckDate() {
        let now = Date(timeIntervalSince1970: 50_000)
        let createdAt = now.addingTimeInterval(-24 * 60 * 60)
        let first = TodoTask(title: "First", dueAt: now.addingTimeInterval(40 * 60), createdAt: createdAt, updatedAt: createdAt)
        let second = TodoTask(title: "Second", dueAt: now.addingTimeInterval(80 * 60), createdAt: createdAt, updatedAt: createdAt)

        let nextCheck = DueTaskReminderPolicy.nextCheckDate(
            tasks: [second, first],
            leadTime: .thirtyMinutes,
            now: now,
            hasReminded: { _ in false }
        )

        XCTAssertEqual(nextCheck, now.addingTimeInterval(10 * 60))
    }

    func testDueTaskReminderPolicyUsesDueTimeForNewTaskAlreadyInsideLeadWindow() {
        let now = Date(timeIntervalSince1970: 55_000)
        let dueAt = now.addingTimeInterval(5 * 60)
        let task = TodoTask(
            title: "New urgent task",
            dueAt: dueAt,
            createdAt: now,
            updatedAt: now
        )

        XCTAssertEqual(
            DueTaskReminderPolicy.effectiveLeadTriggerDate(
                for: task,
                leadTime: .tenMinutes,
                deadlineReminderEnabled: false
            ),
            dueAt
        )

        let candidatesNow = DueTaskReminderPolicy.dueCandidates(
            tasks: [task],
            leadTime: .tenMinutes,
            now: now,
            hasReminded: { _ in false }
        )
        let candidatesAtDue = DueTaskReminderPolicy.dueCandidates(
            tasks: [task],
            leadTime: .tenMinutes,
            now: dueAt,
            hasReminded: { _ in false }
        )

        XCTAssertTrue(candidatesNow.isEmpty)
        XCTAssertEqual(candidatesAtDue.first?.task.id, task.id)
        XCTAssertEqual(candidatesAtDue.first?.phase, .lead)
    }

    func testDueTaskReminderPolicyCreatesLeadAndDeadlineStagesWhenDeadlineReminderIsEnabled() throws {
        let now = Date(timeIntervalSince1970: 56_000)
        let createdAt = now.addingTimeInterval(-24 * 60 * 60)
        let dueAt = now.addingTimeInterval(60 * 60)
        let task = TodoTask(
            title: "Two stage task",
            dueAt: dueAt,
            createdAt: createdAt,
            updatedAt: createdAt
        )

        let leadCandidates = DueTaskReminderPolicy.dueCandidates(
            tasks: [task],
            leadTime: .oneHour,
            deadlineReminderEnabled: true,
            now: now,
            hasReminded: { _ in false }
        )
        let leadKey = try XCTUnwrap(DueTaskReminderPolicy.reminderKey(for: task, leadTime: .oneHour, phase: .lead))
        let nextCheckAfterLead = DueTaskReminderPolicy.nextCheckDate(
            tasks: [task],
            leadTime: .oneHour,
            deadlineReminderEnabled: true,
            now: now.addingTimeInterval(1),
            hasReminded: { $0 == leadKey }
        )
        let deadlineCandidates = DueTaskReminderPolicy.dueCandidates(
            tasks: [task],
            leadTime: .oneHour,
            deadlineReminderEnabled: true,
            now: dueAt,
            hasReminded: { $0 == leadKey }
        )

        XCTAssertEqual(leadCandidates.map(\.phase), [.lead])
        XCTAssertEqual(nextCheckAfterLead, dueAt)
        XCTAssertEqual(deadlineCandidates.map(\.phase), [.deadline])
    }

    func testDueTaskReminderPolicyNewTaskInsideLeadWindowWaitsForDeadlineWhenDeadlineReminderIsEnabled() {
        let now = Date(timeIntervalSince1970: 57_000)
        let dueAt = now.addingTimeInterval(5 * 60)
        let task = TodoTask(
            title: "New urgent task with deadline reminder",
            dueAt: dueAt,
            createdAt: now,
            updatedAt: now
        )

        let candidatesNow = DueTaskReminderPolicy.dueCandidates(
            tasks: [task],
            leadTime: .tenMinutes,
            deadlineReminderEnabled: true,
            now: now,
            hasReminded: { _ in false }
        )
        let candidatesAtDue = DueTaskReminderPolicy.dueCandidates(
            tasks: [task],
            leadTime: .tenMinutes,
            deadlineReminderEnabled: true,
            now: dueAt,
            hasReminded: { _ in false }
        )

        XCTAssertTrue(candidatesNow.isEmpty)
        XCTAssertEqual(candidatesAtDue.map(\.phase), [.deadline])
    }

    func testDueTaskReminderPolicySkipsStaleLeadReminderAfterDeadline() {
        let now = Date(timeIntervalSince1970: 58_000)
        let createdAt = now.addingTimeInterval(-24 * 60 * 60)
        let dueAt = now.addingTimeInterval(60 * 60)
        let task = TodoTask(
            title: "Missed lead task",
            dueAt: dueAt,
            createdAt: createdAt,
            updatedAt: createdAt
        )

        let candidates = DueTaskReminderPolicy.dueCandidates(
            tasks: [task],
            leadTime: .oneHour,
            deadlineReminderEnabled: true,
            now: dueAt.addingTimeInterval(1),
            hasReminded: { _ in false }
        )

        XCTAssertEqual(candidates.map(\.phase), [.deadline])
    }

    func testDueTaskReminderHistoryPersistsAndPrunesByTaskID() throws {
        let suiteName = "TodoPilot.DueTaskReminderHistoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let now = Date(timeIntervalSince1970: 60_000)
        let task = TodoTask(title: "Persisted", dueAt: now)
        let removedTask = TodoTask(title: "Removed", dueAt: now)
        let taskKey = try XCTUnwrap(DueTaskReminderPolicy.reminderKey(for: task, leadTime: .tenMinutes))
        let removedTaskKey = try XCTUnwrap(DueTaskReminderPolicy.reminderKey(for: removedTask, leadTime: .tenMinutes))

        var history = DueTaskReminderHistory(defaults: defaults)
        history.record(taskKey, at: now)
        history.record(removedTaskKey, at: now)

        var restored = DueTaskReminderHistory(defaults: defaults)
        XCTAssertTrue(restored.hasReminded(taskKey))
        XCTAssertTrue(restored.hasReminded(removedTaskKey))

        restored.prune(activeTaskIDs: [task.id], now: now)
        let pruned = DueTaskReminderHistory(defaults: defaults)

        XCTAssertTrue(pruned.hasReminded(taskKey))
        XCTAssertFalse(pruned.hasReminded(removedTaskKey))
    }

    func testStatusIslandHoverPolicyExpandsAndCollapsesDeliberately() {
        let policy = StatusIslandHoverPolicy.default

        XCTAssertTrue(policy.expandsOnMouseEnter)
        XCTAssertTrue(policy.collapsesAfterMouseExit)
        XCTAssertGreaterThan(policy.collapseDelay, 0)
        XCTAssertEqual(policy.hitTestSlop, 0)
        XCTAssertEqual(policy.inputMode, .trackingArea)
    }

    func testStatusIslandHoverCollapseDoesNotRescheduleWhilePending() {
        let policy = StatusIslandHoverPolicy.default

        XCTAssertTrue(StatusIslandHoverCollapsePolicy.shouldScheduleCollapse(
            hasPendingCollapse: false,
            policy: policy
        ))
        XCTAssertFalse(StatusIslandHoverCollapsePolicy.shouldScheduleCollapse(
            hasPendingCollapse: true,
            policy: policy
        ))
    }

    func testStatusIslandCompactCarouselRotatesActiveTasks() throws {
        let first = TodoTask(title: "First")
        let second = TodoTask(title: "Second")
        let policy = StatusIslandCompactCarouselPolicy(interval: 3)
        let start = Date(timeIntervalSinceReferenceDate: 0)

        XCTAssertEqual(policy.task(from: [first, second], at: start)?.id, first.id)
        XCTAssertEqual(policy.task(from: [first, second], at: start.addingTimeInterval(3))?.id, second.id)
        XCTAssertEqual(policy.task(from: [first, second], at: start.addingTimeInterval(6))?.id, first.id)
        XCTAssertNil(policy.task(from: [], at: start))
    }

    func testStatusIslandTaskSnapshotPrioritizesRunningAgentsAndCachesRunAssociations() {
        let manualTask = TodoTask(title: "Manual")
        let laterAgentTask = TodoTask(title: "Later agent", source: .codeAgent)
        let earlierAgentTask = TodoTask(title: "Earlier agent", source: .codeAgent)
        let terminalAgentTask = TodoTask(title: "Terminal agent", source: .codeAgent)
        let startedAt = Date(timeIntervalSince1970: 10_000)
        let runs = [
            AgentRun(
                taskID: laterAgentTask.id,
                provider: .codex,
                sessionIdentityHash: "later",
                startedAt: startedAt.addingTimeInterval(2),
                lastEventAt: startedAt.addingTimeInterval(2)
            ),
            AgentRun(
                taskID: earlierAgentTask.id,
                provider: .claudeCode,
                sessionIdentityHash: "earlier",
                startedAt: startedAt,
                lastEventAt: startedAt
            ),
            AgentRun(
                taskID: terminalAgentTask.id,
                provider: .cursor,
                sessionIdentityHash: "terminal",
                state: .terminal,
                outcome: .completed,
                startedAt: startedAt.addingTimeInterval(-1),
                endedAt: startedAt,
                lastEventAt: startedAt
            )
        ]

        let snapshot = StatusIslandTaskSnapshot(
            activeTasks: [manualTask, laterAgentTask, earlierAgentTask, terminalAgentTask],
            runs: runs
        )

        XCTAssertEqual(snapshot.runningAgentTasks.map(\.id), [earlierAgentTask.id, laterAgentTask.id])
        XCTAssertEqual(
            snapshot.orderedActiveTasks.map(\.id),
            [earlierAgentTask.id, laterAgentTask.id, manualTask.id, terminalAgentTask.id]
        )
        XCTAssertEqual(snapshot.carouselTasks.map(\.id), [earlierAgentTask.id, laterAgentTask.id])
        XCTAssertEqual(snapshot.run(for: terminalAgentTask.id)?.provider, .cursor)
    }

    @MainActor
    func testStatusIslandTaskSnapshotCacheOnlyRefreshesForDataOrDueStateChanges() {
        let now = Date(timeIntervalSince1970: 20_000)
        let dueAt = now.addingTimeInterval(60)
        let task = TodoTask(title: "Cached", dueAt: dueAt)
        let taskStore = TaskStore(seed: [task])
        let cache = StatusIslandTaskSnapshotCache()

        _ = cache.snapshot(taskStore: taskStore, runs: [], now: now)
        _ = cache.snapshot(taskStore: taskStore, runs: [], now: now.addingTimeInterval(30))
        XCTAssertEqual(cache.recomputationCount, 1)

        _ = cache.snapshot(taskStore: taskStore, runs: [], now: dueAt.addingTimeInterval(1))
        XCTAssertEqual(cache.recomputationCount, 2)

        let run = AgentRun(
            taskID: task.id,
            provider: .codex,
            sessionIdentityHash: "new-run",
            startedAt: now,
            lastEventAt: now
        )
        _ = cache.snapshot(taskStore: taskStore, runs: [run], now: dueAt.addingTimeInterval(2))
        XCTAssertEqual(cache.recomputationCount, 3)
    }

    func testPixelPropellerAnimationUsesCompositorFramesAndHonorsReduceMotion() {
        let policy = PixelPropellerAnimationPolicy.default

        XCTAssertEqual(policy.frameRate, 18)
        XCTAssertEqual(policy.frameCount, 3)
        XCTAssertEqual(policy.renderingMode, .coreAnimationKeyframes)
        XCTAssertTrue(policy.shouldAnimate(requested: true, reduceMotion: false))
        XCTAssertFalse(policy.shouldAnimate(requested: false, reduceMotion: false))
        XCTAssertFalse(policy.shouldAnimate(requested: true, reduceMotion: true))
    }

    func testStatusIslandHeaderOnlyShowsCarouselTitleWhenCollapsed() {
        XCTAssertTrue(StatusIslandHeaderTitlePolicy.showsCarouselTitle(isExpanded: false))
        XCTAssertFalse(StatusIslandHeaderTitlePolicy.showsCarouselTitle(isExpanded: true))
        XCTAssertEqual(StatusIslandHeaderTitlePolicy.carouselTitleOpacity(isExpanded: false), 1)
        XCTAssertEqual(StatusIslandHeaderTitlePolicy.carouselTitleOpacity(isExpanded: true), 0)
        XCTAssertFalse(StatusIslandHeaderTitlePolicy.hidesCarouselTitleFromAccessibility(isExpanded: false))
        XCTAssertTrue(StatusIslandHeaderTitlePolicy.hidesCarouselTitleFromAccessibility(isExpanded: true))
    }

    func testStatusIslandHeaderRestoresCarouselTitleAfterExpandCollapse() {
        let expandedStates = [false, true, false]
        let visibleStates = expandedStates.map(StatusIslandHeaderTitlePolicy.showsCarouselTitle)
        let opacityStates = expandedStates.map(StatusIslandHeaderTitlePolicy.carouselTitleOpacity)

        XCTAssertEqual(visibleStates, [true, false, true])
        XCTAssertEqual(opacityStates, [1, 0, 1])
    }

    @MainActor
    func testStatusIslandHitTestFrameUsesHostingViewFlippedCoordinates() {
        let hostingView = NSHostingView(rootView: EmptyView())

        XCTAssertTrue(hostingView.isFlipped)
    }

    func testStatusIslandCompactPanelOnlyWrapsVisibleIsland() {
        let metrics = StatusIslandMetrics(screen: nil, isExpanded: false)
        let expandedMetrics = StatusIslandMetrics(screen: nil, isExpanded: true)

        XCTAssertEqual(metrics.panelSize, metrics.islandSize)
        XCTAssertEqual(metrics.hitTestFrame.size, metrics.islandSize)
        XCTAssertEqual(metrics.hitTestFrame.origin, .zero)
        XCTAssertEqual(metrics.hitTestFrame.minY, 0)
        XCTAssertEqual(metrics.hitTestFrame.maxY, metrics.compactHeight)
        XCTAssertLessThan(metrics.panelSize.width, expandedMetrics.panelSize.width)
        XCTAssertLessThan(metrics.panelSize.height, expandedMetrics.panelSize.height)
        XCTAssertLessThan(metrics.hitTestFrame.height, expandedMetrics.hitTestFrame.height)
    }

    func testStatusIslandCollapseKeepsTopCenterAnchorInsteadOfDriftingFromLeftEdge() {
        let geometry = StatusIslandScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
            safeAreaTopInset: 0,
            isBuiltInDisplay: false
        )
        let expandedMetrics = StatusIslandMetrics(screenGeometry: geometry, isExpanded: true)
        let compactMetrics = StatusIslandMetrics(screenGeometry: geometry, isExpanded: false)
        let collapsingMetrics = StatusIslandMetrics(
            screenGeometry: geometry,
            isExpanded: false,
            keepsExpandedPanelFrame: true
        )
        let expandedFrame = StatusIslandPlacement(screenGeometry: geometry, metrics: expandedMetrics).frame
        let compactFrame = StatusIslandPlacement(screenGeometry: geometry, metrics: compactMetrics).frame
        let collapsingFrame = StatusIslandPlacement(screenGeometry: geometry, metrics: collapsingMetrics).frame
        let contentSizeFirstFrame = CGRect(origin: expandedFrame.origin, size: compactMetrics.panelSize)
        let collapsingVisibleFrame = screenFrame(
            ofFlippedLocalRect: collapsingMetrics.hitTestFrame,
            in: collapsingFrame
        )

        XCTAssertEqual(expandedFrame.midX, geometry.frame.midX)
        XCTAssertEqual(compactFrame.midX, geometry.frame.midX)
        XCTAssertEqual(collapsingFrame, expandedFrame)
        XCTAssertEqual(collapsingMetrics.panelSize, expandedMetrics.panelSize)
        XCTAssertEqual(collapsingMetrics.islandSize, compactMetrics.islandSize)
        XCTAssertEqual(collapsingMetrics.hitTestFrame.midX, collapsingMetrics.panelSize.width / 2)
        XCTAssertEqual(collapsingVisibleFrame, compactFrame)
        XCTAssertLessThan(contentSizeFirstFrame.midX, compactFrame.midX)
    }

    func testStatusIslandExpandPrewarmsExpandedPanelBeforeContentGrows() {
        let geometry = StatusIslandScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
            safeAreaTopInset: 0,
            isBuiltInDisplay: false
        )
        let compactMetrics = StatusIslandMetrics(screenGeometry: geometry, isExpanded: false)
        let expandingMetrics = StatusIslandMetrics(
            screenGeometry: geometry,
            isExpanded: false,
            keepsExpandedPanelFrame: true
        )
        let expandedMetrics = StatusIslandMetrics(screenGeometry: geometry, isExpanded: true)
        let compactFrame = StatusIslandPlacement(screenGeometry: geometry, metrics: compactMetrics).frame
        let expandingFrame = StatusIslandPlacement(screenGeometry: geometry, metrics: expandingMetrics).frame
        let expandedFrame = StatusIslandPlacement(screenGeometry: geometry, metrics: expandedMetrics).frame
        let expandingVisibleFrame = screenFrame(
            ofFlippedLocalRect: expandingMetrics.hitTestFrame,
            in: expandingFrame
        )

        XCTAssertEqual(expandingFrame, expandedFrame)
        XCTAssertEqual(expandingMetrics.panelSize, expandedMetrics.panelSize)
        XCTAssertEqual(expandingMetrics.islandSize, compactMetrics.islandSize)
        XCTAssertEqual(expandingVisibleFrame, compactFrame)
        XCTAssertEqual(expandingMetrics.hitTestFrame.midX, expandingMetrics.panelSize.width / 2)
        XCTAssertLessThan(compactFrame.width, expandedFrame.width)
    }

    func testStatusIslandCompactSizeUsesTighterVisualTuning() {
        let plainMetrics = StatusIslandMetrics(screen: nil, isExpanded: false)
        let notchedGeometry = StatusIslandScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            visibleFrame: CGRect(x: 0, y: 0, width: 1728, height: 1079),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 1079, width: 758, height: 38),
            auxiliaryTopRightArea: CGRect(x: 970, y: 1079, width: 758, height: 38),
            safeAreaTopInset: 38,
            isBuiltInDisplay: true
        )
        let notchedMetrics = StatusIslandMetrics(screenGeometry: notchedGeometry, isExpanded: false)

        XCTAssertEqual(plainMetrics.compactWidth, 336)
        XCTAssertEqual(plainMetrics.compactHeight, 42)
        XCTAssertEqual(notchedMetrics.compactWidth, 326)
        XCTAssertEqual(notchedMetrics.compactHeight, 38)
    }

    func testStatusIslandCompactSurfaceDoesNotLeakCornerShadow() {
        let compactShadow = StatusIslandShadowStyle.surface(isExpanded: false)
        let expandedShadow = StatusIslandShadowStyle.surface(isExpanded: true)

        XCTAssertEqual(compactShadow.opacity, 0)
        XCTAssertEqual(compactShadow.radius, 0)
        XCTAssertEqual(compactShadow.y, 0)
        XCTAssertGreaterThan(expandedShadow.opacity, 0)
        XCTAssertGreaterThan(expandedShadow.radius, 0)
        XCTAssertGreaterThan(expandedShadow.y, 0)
    }

    func testStatusIslandExpandedHoverRegionKeepsDropdownTopCentered() {
        let metrics = StatusIslandMetrics(screen: nil, isExpanded: true)

        XCTAssertEqual(metrics.panelSize.width, metrics.expandedWidth + metrics.sideShadowInset * 2)
        XCTAssertEqual(metrics.panelSize.height, metrics.islandSize.height + metrics.bottomShadowInset)
        XCTAssertEqual(metrics.hitTestFrame.size, metrics.islandSize)
        XCTAssertEqual(metrics.hitTestFrame.midX, metrics.panelSize.width / 2)
        XCTAssertEqual(metrics.hitTestFrame.minY, 0)
        XCTAssertEqual(metrics.hitTestFrame.maxY, metrics.islandSize.height)
        XCTAssertLessThan(metrics.hitTestFrame.maxY, metrics.panelSize.height)
    }

    func testStatusIslandPlacementPinsNonNotchedScreenToPhysicalTopEdge() {
        let geometry = StatusIslandScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
            safeAreaTopInset: 0,
            isBuiltInDisplay: false
        )
        let metrics = StatusIslandMetrics(screenGeometry: geometry, isExpanded: false)
        let placement = StatusIslandPlacement(screenGeometry: geometry, metrics: metrics)

        XCTAssertFalse(metrics.isNotchedScreen)
        XCTAssertEqual(placement.frame.maxY, geometry.frame.maxY)
    }

    func testStatusIslandDoesNotInferNotchFromBuiltInDisplaySizeAlone() {
        let geometry = StatusIslandScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
            safeAreaTopInset: 25,
            isBuiltInDisplay: true
        )
        let metrics = StatusIslandMetrics(screenGeometry: geometry, isExpanded: false)

        XCTAssertFalse(geometry.hasUsableCameraHousing)
        XCTAssertFalse(metrics.isNotchedScreen)
        XCTAssertEqual(metrics.notchHeight, 0)
        XCTAssertEqual(metrics.notchWidth, 0)
    }

    func testStatusIslandUsesCameraHousingAreasForNotchedScreen() {
        let geometry = StatusIslandScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            visibleFrame: CGRect(x: 0, y: 0, width: 1728, height: 1079),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 1079, width: 758, height: 38),
            auxiliaryTopRightArea: CGRect(x: 970, y: 1079, width: 758, height: 38),
            safeAreaTopInset: 38,
            isBuiltInDisplay: true
        )
        let metrics = StatusIslandMetrics(screenGeometry: geometry, isExpanded: false)
        let placement = StatusIslandPlacement(screenGeometry: geometry, metrics: metrics)

        XCTAssertTrue(geometry.hasUsableCameraHousing)
        XCTAssertTrue(metrics.isNotchedScreen)
        XCTAssertEqual(metrics.notchHeight, 38)
        XCTAssertEqual(metrics.notchWidth, 212)
        XCTAssertEqual(placement.frame.maxY, geometry.frame.maxY)
    }

    @MainActor
    func testMainWindowCloseHiderPreventsWindowDestruction() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 120, height: 80),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let closeHider = MainWindowCloseHider()

        XCTAssertFalse(closeHider.windowShouldClose(window))
    }

    @MainActor
    func testMainWindowCloseHiderAllowsCloseDuringApplicationTermination() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 120, height: 80),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let closeHider = MainWindowCloseHider(isApplicationTerminating: { true })

        XCTAssertTrue(closeHider.windowShouldClose(window))
    }

    func testTerminationCoordinatorBroadcastsTerminationRequestForSwiftUISheetOwners() {
        AppTerminationState.resetForTests()

        var didReceiveTerminationRequest = false
        let observer = NotificationCenter.default.addObserver(
            forName: .applicationTerminationRequested,
            object: nil,
            queue: nil
        ) { _ in
            didReceiveTerminationRequest = true
            XCTAssertTrue(AppTerminationState.isTerminating)
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        AppTerminationCoordinator.beginTerminationRequest()

        XCTAssertTrue(didReceiveTerminationRequest)
    }

    @MainActor
    func testTerminationCoordinatorDismissesAttachedSheetsBeforeQuitReply() {
        let parent = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 240, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let sheet = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 160, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        var didEndSheet = false
        parent.beginSheet(sheet) { response in
            didEndSheet = response == .cancel
        }
        XCTAssertTrue(parent.attachedSheet === sheet)

        AppTerminationCoordinator.dismissAttachedSheets(windows: [parent])

        XCTAssertNil(parent.attachedSheet)
        XCTAssertTrue(didEndSheet)
        parent.close()
    }

    @MainActor
    func testTerminationCoordinatorDismissesSheetWindowsFromWindowList() {
        let parent = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 240, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let sheet = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 160, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        var didEndSheet = false
        parent.beginSheet(sheet) { response in
            didEndSheet = response == .cancel
        }
        XCTAssertTrue(sheet.sheetParent === parent)

        AppTerminationCoordinator.dismissAttachedSheets(windows: [sheet])

        XCTAssertNil(sheet.sheetParent)
        XCTAssertTrue(didEndSheet)
        parent.close()
    }

    private func wavUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private func wavUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private func pcmEnergy(_ data: Data, sampleRange: Range<Int>) -> Int64 {
        sampleRange.reduce(into: Int64(0)) { energy, sampleIndex in
            let offset = 44 + sampleIndex * 2
            let sample = Int16(bitPattern: wavUInt16(data, at: offset))
            energy += Int64(abs(Int(sample)))
        }
    }

    private func stereoPcmEnergy(_ data: Data, sampleRange: Range<Int>) -> Int64 {
        sampleRange.reduce(into: Int64(0)) { energy, sampleIndex in
            let offset = 44 + sampleIndex * 4
            let left = Int16(bitPattern: wavUInt16(data, at: offset))
            let right = Int16(bitPattern: wavUInt16(data, at: offset + 2))
            energy += Int64(abs(Int(left)) + abs(Int(right)))
        }
    }

    private func screenFrame(ofFlippedLocalRect localRect: CGRect, in panelFrame: CGRect) -> CGRect {
        CGRect(
            x: panelFrame.minX + localRect.minX,
            y: panelFrame.maxY - localRect.maxY,
            width: localRect.width,
            height: localRect.height
        )
    }

    private func contrastRatio(
        _ first: FlightReminderBannerPalette,
        _ second: FlightReminderBannerPalette
    ) -> Double {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ palette: FlightReminderBannerPalette) -> Double {
        func linearized(_ component: Double) -> Double {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearized(palette.red)
            + 0.7152 * linearized(palette.green)
            + 0.0722 * linearized(palette.blue)
    }
}

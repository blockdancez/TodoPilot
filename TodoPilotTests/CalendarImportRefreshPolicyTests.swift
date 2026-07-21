import XCTest
@testable import TodoPilot

final class CalendarImportRefreshPolicyTests: XCTestCase {
    func testAutomaticRefreshIsSkippedUntilLastRefreshIsTenMinutesOld() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertFalse(CalendarAutomaticRefreshPolicy.shouldRefresh(
            lastRefreshAt: now.addingTimeInterval(-(10 * 60) + 1),
            isRefreshing: false,
            now: now
        ))
        XCTAssertTrue(CalendarAutomaticRefreshPolicy.shouldRefresh(
            lastRefreshAt: now.addingTimeInterval(-(10 * 60)),
            isRefreshing: false,
            now: now
        ))
    }

    func testAutomaticRefreshWaitsForAnInFlightRefresh() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertFalse(CalendarAutomaticRefreshPolicy.shouldRefresh(
            lastRefreshAt: nil,
            isRefreshing: true,
            now: now
        ))
        XCTAssertTrue(CalendarAutomaticRefreshPolicy.shouldRefresh(
            lastRefreshAt: nil,
            isRefreshing: false,
            now: now
        ))
    }
}

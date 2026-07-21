import XCTest
@testable import TodoPilot

final class LocalMigrationCoordinatorTests: XCTestCase {
    func testMigrationIsIdempotent() throws {
        let suiteName = "TodoPilotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let coordinator = LocalMigrationCoordinator(defaults: defaults)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = try coordinator.ensureMigrated()
        let second = try coordinator.ensureMigrated()

        XCTAssertEqual(first.appliedVersions, [LocalMigrationCoordinator.currentSchemaVersion])
        XCTAssertEqual(second.appliedVersions, [])
        XCTAssertEqual(second.currentVersion, LocalMigrationCoordinator.currentSchemaVersion)
    }

    func testRecoveryManifestCapturesSchemaAndTaskCount() {
        let coordinator = LocalMigrationCoordinator()
        let createdAt = Date(timeIntervalSince1970: 10)

        let manifest = coordinator.makeRecoveryManifest(taskCount: 3, createdAt: createdAt)

        XCTAssertEqual(manifest.schemaVersion, LocalMigrationCoordinator.currentSchemaVersion)
        XCTAssertEqual(manifest.taskCount, 3)
        XCTAssertEqual(manifest.createdAt, createdAt)
    }
}

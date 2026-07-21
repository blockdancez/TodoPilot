import Foundation

struct LocalMigrationResult: Equatable {
    let previousVersion: Int
    let currentVersion: Int
    let appliedVersions: [Int]
}

struct LocalRecoveryManifest: Equatable {
    let schemaVersion: Int
    let createdAt: Date
    let taskCount: Int
}

struct LocalMigrationCoordinator {
    static let currentSchemaVersion = 1

    private let defaults: UserDefaults
    private let schemaVersionKey = "storage.schemaVersion"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func ensureMigrated() throws -> LocalMigrationResult {
        let previousVersion = defaults.integer(forKey: schemaVersionKey)

        guard previousVersion <= Self.currentSchemaVersion else {
            throw TodoPilotError.storageFailure("Local schema is newer than this app build.")
        }

        if previousVersion == Self.currentSchemaVersion {
            return LocalMigrationResult(
                previousVersion: previousVersion,
                currentVersion: Self.currentSchemaVersion,
                appliedVersions: []
            )
        }

        let startVersion = max(previousVersion + 1, 1)
        let appliedVersions = Array(startVersion...Self.currentSchemaVersion)
        defaults.set(Self.currentSchemaVersion, forKey: schemaVersionKey)

        return LocalMigrationResult(
            previousVersion: previousVersion,
            currentVersion: Self.currentSchemaVersion,
            appliedVersions: appliedVersions
        )
    }

    func makeRecoveryManifest(taskCount: Int, createdAt: Date = Date()) -> LocalRecoveryManifest {
        LocalRecoveryManifest(
            schemaVersion: Self.currentSchemaVersion,
            createdAt: createdAt,
            taskCount: taskCount
        )
    }

    func resetForTests() {
        defaults.removeObject(forKey: schemaVersionKey)
    }
}

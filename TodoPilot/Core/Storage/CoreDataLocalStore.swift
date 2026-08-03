import CoreData
import CoreGraphics
import CryptoKit
import Foundation

struct LocalCaptureSession: Equatable, Identifiable {
    let id: UUID
    let startedAt: Date
    let completedAt: Date?
    let status: String
    let screenCount: Int
    let selectionHash: String?
}

@MainActor
protocol CaptureSessionRecording {
    func startCaptureSession(surface: String, screenCount: Int, startedAt: Date) -> UUID
    func completeCaptureSession(_ id: UUID, completedAt: Date, displayID: CGDirectDisplayID, bounds: CGRect)
    func cancelCaptureSession(_ id: UUID, completedAt: Date)
    func failCaptureSession(_ id: UUID, completedAt: Date)
}

@MainActor
final class CoreDataLocalStore: TaskStorePersistence, CaptureSessionRecording, AgentRunPersistence {
    private struct TaskSourceSnapshot {
        let source: TodoTaskSource
        let sourceKey: String?
        let sourceQuote: String?
    }

    private enum Entity {
        static let task = "TaskRecord"
        static let taskSource = "TaskSourceRecord"
        static let setting = "SettingRecord"
        static let reminderEvent = "ReminderEventRecord"
        static let captureSession = "CaptureSessionRecord"
        static let agentRun = "AgentRunRecord"
    }

    private enum Keys {
        static let legacyMigrationCompleted = "coreData.local.tasks.legacyMigrationCompleted.v1"
        static let storeInitialized = "coreData.local.tasks.storeInitialized.v1"
    }

    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext
    private let legacyPersistence: TaskStorePersistence?
    private let defaults: UserDefaults

    init(
        storeURL: URL? = nil,
        inMemory: Bool = false,
        defaults: UserDefaults = .standard,
        legacyPersistence: TaskStorePersistence? = nil,
        migratesLegacyUserDefaults: Bool = true
    ) {
        self.defaults = defaults
        self.legacyPersistence = legacyPersistence
            ?? (migratesLegacyUserDefaults ? UserDefaultsTaskStorePersistence(defaults: defaults) : nil)
        self.container = NSPersistentContainer(
            name: "TodoPilotLocalStore",
            managedObjectModel: Self.makeModel()
        )

        let description: NSPersistentStoreDescription
        if inMemory {
            description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
        } else {
            description = NSPersistentStoreDescription(url: storeURL ?? Self.defaultStoreURL())
            description.type = NSSQLiteStoreType
        }
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            assertionFailure("Failed to load TodoPilot Core Data store: \(loadError)")
        }

        self.context = container.viewContext
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.undoManager = nil
    }

    func load() -> [TodoTask]? {
        let storedTasks = fetchTasks()
        guard storedTasks.isEmpty else {
            markInitialized()
            markLegacyMigrated()
            return storedTasks
        }

        if !defaults.bool(forKey: Keys.legacyMigrationCompleted),
           let legacyTasks = legacyPersistence?.load() {
            replaceTasks(with: legacyTasks)
            markLegacyMigrated()
            markInitialized()
            return legacyTasks
        }

        if defaults.bool(forKey: Keys.storeInitialized) {
            return []
        }

        return nil
    }

    func save(_ tasks: [TodoTask]) {
        replaceTasks(with: tasks)
        markInitialized()
        markLegacyMigrated()
    }

    func startCaptureSession(surface: String, screenCount: Int, startedAt: Date = Date()) -> UUID {
        let id = UUID()
        let object = NSEntityDescription.insertNewObject(forEntityName: Entity.captureSession, into: context)
        object.setValue(id, forKey: "localID")
        object.setValue(startedAt, forKey: "startedAt")
        object.setValue(nil, forKey: "completedAt")
        object.setValue("STARTED", forKey: "status")
        object.setValue(Int64(max(0, screenCount)), forKey: "screenCount")
        object.setValue(nil, forKey: "selectionHash")
        object.setValue(surface, forKey: "surface")
        saveContext()
        return id
    }

    func completeCaptureSession(
        _ id: UUID,
        completedAt: Date = Date(),
        displayID: CGDirectDisplayID,
        bounds: CGRect
    ) {
        updateCaptureSession(id) { object in
            object.setValue(completedAt, forKey: "completedAt")
            object.setValue("COMPLETED", forKey: "status")
            object.setValue(Self.selectionHash(displayID: displayID, bounds: bounds), forKey: "selectionHash")
        }
    }

    func cancelCaptureSession(_ id: UUID, completedAt: Date = Date()) {
        updateCaptureSession(id) { object in
            object.setValue(completedAt, forKey: "completedAt")
            object.setValue("CANCELLED", forKey: "status")
        }
    }

    func failCaptureSession(_ id: UUID, completedAt: Date = Date()) {
        updateCaptureSession(id) { object in
            object.setValue(completedAt, forKey: "completedAt")
            object.setValue("FAILED", forKey: "status")
        }
    }

    func loadCaptureSessions() -> [LocalCaptureSession] {
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.captureSession)
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: true)]
        return (try? context.fetch(request))?.compactMap { object in
            guard let id = object.value(forKey: "localID") as? UUID,
                  let startedAt = object.value(forKey: "startedAt") as? Date,
                  let status = object.value(forKey: "status") as? String else {
                return nil
            }
            return LocalCaptureSession(
                id: id,
                startedAt: startedAt,
                completedAt: object.value(forKey: "completedAt") as? Date,
                status: status,
                screenCount: Int((object.value(forKey: "screenCount") as? Int64) ?? 0),
                selectionHash: object.value(forKey: "selectionHash") as? String
            )
        } ?? []
    }

    func loadAgentRuns() -> [AgentRun] {
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.agentRun)
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: true)]
        return (try? context.fetch(request))?.compactMap { object in
            guard let runID = object.value(forKey: "runID") as? UUID,
                  let taskID = object.value(forKey: "taskID") as? UUID,
                  let providerValue = object.value(forKey: "provider") as? String,
                  let provider = AgentProvider(rawValue: providerValue),
                  let sessionIdentityHash = object.value(forKey: "sessionIdentityHash") as? String,
                  let stateValue = object.value(forKey: "state") as? String,
                  let state = AgentRunState(rawValue: stateValue),
                  let startedAt = object.value(forKey: "startedAt") as? Date,
                  let lastEventAt = object.value(forKey: "lastEventAt") as? Date,
                  let overrideValue = object.value(forKey: "userOverride") as? String,
                  let userOverride = AgentRunUserOverride(rawValue: overrideValue),
                  let reminderValue = object.value(forKey: "reminderState") as? String,
                  let reminderState = AgentRunReminderState(rawValue: reminderValue) else {
                return nil
            }

            let outcome = (object.value(forKey: "outcome") as? String).flatMap(AgentRunOutcome.init(rawValue:))
            let processNumber = object.value(forKey: "originProcessID") as? NSNumber
            return AgentRun(
                id: runID,
                taskID: taskID,
                provider: provider,
                sessionIdentityHash: sessionIdentityHash,
                turnIdentityHash: object.value(forKey: "turnIdentityHash") as? String,
                workspaceDisplayName: object.value(forKey: "workspaceDisplayName") as? String,
                originBundleID: object.value(forKey: "originBundleID") as? String,
                originProcessID: processNumber.map { Int32(truncating: $0) },
                state: state,
                outcome: outcome,
                startedAt: startedAt,
                endedAt: object.value(forKey: "endedAt") as? Date,
                lastEventAt: lastEventAt,
                userOverride: userOverride,
                reminderState: reminderState
            )
        } ?? []
    }

    func saveAgentRun(_ run: AgentRun) {
        upsertAgentRun(run)
        saveContext()
    }

    func saveAgentRuns(_ runs: [AgentRun]) {
        for run in runs {
            upsertAgentRun(run)
        }
        saveContext()
    }

    private func upsertAgentRun(_ run: AgentRun) {
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.agentRun)
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "runID == %@", run.id as CVarArg)
        let object = (try? context.fetch(request).first)
            ?? NSEntityDescription.insertNewObject(forEntityName: Entity.agentRun, into: context)
        object.setValue(run.id, forKey: "runID")
        object.setValue(run.taskID, forKey: "taskID")
        object.setValue(run.provider.rawValue, forKey: "provider")
        object.setValue(run.sessionIdentityHash, forKey: "sessionIdentityHash")
        object.setValue(run.turnIdentityHash, forKey: "turnIdentityHash")
        object.setValue(run.workspaceDisplayName, forKey: "workspaceDisplayName")
        object.setValue(run.originBundleID, forKey: "originBundleID")
        object.setValue(run.originProcessID.map { Int64($0) }, forKey: "originProcessID")
        object.setValue(run.state.rawValue, forKey: "state")
        object.setValue(run.outcome?.rawValue, forKey: "outcome")
        object.setValue(run.startedAt, forKey: "startedAt")
        object.setValue(run.endedAt, forKey: "endedAt")
        object.setValue(run.lastEventAt, forKey: "lastEventAt")
        object.setValue(run.userOverride.rawValue, forKey: "userOverride")
        object.setValue(run.reminderState.rawValue, forKey: "reminderState")
    }

    func deleteAgentRun(_ runID: UUID) {
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.agentRun)
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "runID == %@", runID as CVarArg)
        guard let object = try? context.fetch(request).first else {
            return
        }
        context.delete(object)
        saveContext()
    }

    private func fetchTasks() -> [TodoTask] {
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.task)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let taskRecords = (try? context.fetch(request)) ?? []
        let sourcesByTaskID = fetchTaskSourcesByTaskID()

        return taskRecords.compactMap { object in
            guard let id = object.value(forKey: "localID") as? UUID,
                  let title = object.value(forKey: "title") as? String,
                  let priorityValue = object.value(forKey: "priority") as? String,
                  let priority = TodoTaskPriority(rawValue: priorityValue),
                  let statusValue = object.value(forKey: "status") as? String,
                  let status = TodoTaskStatus(rawValue: statusValue),
                  let createdAt = object.value(forKey: "createdAt") as? Date,
                  let updatedAt = object.value(forKey: "updatedAt") as? Date else {
                return nil
            }

            let sourceQuote = object.value(forKey: "sourceQuote") as? String
                ?? sourcesByTaskID[id]?.sourceQuote
            let sourceSnapshot = sourcesByTaskID[id]

            return TodoTask(
                id: id,
                title: title,
                detail: object.value(forKey: "detail") as? String,
                priority: priority,
                dueAt: object.value(forKey: "dueAt") as? Date,
                sourceQuote: sourceQuote,
                source: sourceSnapshot?.source ?? .manual,
                sourceKey: sourceSnapshot?.sourceKey,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: object.value(forKey: "deletedAt") as? Date
            )
        }
    }

    private func replaceTasks(with tasks: [TodoTask]) {
        let repairedTasks = TodoTaskIdentityRepair.deduplicated(tasks)
        deleteAll(Entity.taskSource)
        deleteAll(Entity.task)

        for task in repairedTasks {
            insertTask(task)
            insertTaskSource(for: task)
        }
        saveContext()
    }

    private func insertTask(_ task: TodoTask) {
        let object = NSEntityDescription.insertNewObject(forEntityName: Entity.task, into: context)
        object.setValue(task.id, forKey: "localID")
        object.setValue(task.title, forKey: "title")
        object.setValue(task.detail, forKey: "detail")
        object.setValue(task.priority.rawValue, forKey: "priority")
        object.setValue(task.status.rawValue, forKey: "status")
        object.setValue(task.dueAt, forKey: "dueAt")
        object.setValue(task.sourceQuote, forKey: "sourceQuote")
        object.setValue(task.createdAt, forKey: "createdAt")
        object.setValue(task.updatedAt, forKey: "updatedAt")
        object.setValue(task.deletedAt, forKey: "deletedAt")
    }

    private func insertTaskSource(for task: TodoTask) {
        let object = NSEntityDescription.insertNewObject(forEntityName: Entity.taskSource, into: context)
        object.setValue(UUID(), forKey: "localID")
        object.setValue(task.id, forKey: "taskLocalID")
        object.setValue(task.source.rawValue, forKey: "sourceType")
        object.setValue(task.sourceKey, forKey: "sourceHash")
        object.setValue(task.sourceQuote, forKey: "sourceQuote")
        object.setValue(nil, forKey: "ocrTextRef")
        object.setValue(task.createdAt, forKey: "createdAt")
    }

    private func fetchTaskSourcesByTaskID() -> [UUID: TaskSourceSnapshot] {
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.taskSource)
        let records = (try? context.fetch(request)) ?? []
        var result: [UUID: TaskSourceSnapshot] = [:]
        for record in records {
            guard let taskID = record.value(forKey: "taskLocalID") as? UUID else {
                continue
            }
            result[taskID] = TaskSourceSnapshot(
                source: TodoTaskSource(storedValue: record.value(forKey: "sourceType") as? String),
                sourceKey: record.value(forKey: "sourceHash") as? String,
                sourceQuote: record.value(forKey: "sourceQuote") as? String
            )
        }
        return result
    }

    private func updateCaptureSession(_ id: UUID, mutate: (NSManagedObject) -> Void) {
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.captureSession)
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "localID == %@", id as CVarArg)
        guard let object = try? context.fetch(request).first else {
            return
        }
        mutate(object)
        saveContext()
    }

    private func deleteAll(_ entityName: String) {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        guard let objects = try? context.fetch(request) else {
            return
        }
        for object in objects {
            context.delete(object)
        }
    }

    private func saveContext() {
        guard context.hasChanges else {
            return
        }
        try? context.save()
    }

    private func markLegacyMigrated() {
        defaults.set(true, forKey: Keys.legacyMigrationCompleted)
    }

    private func markInitialized() {
        defaults.set(true, forKey: Keys.storeInitialized)
    }

    private static func selectionHash(displayID: CGDirectDisplayID, bounds: CGRect) -> String {
        let payload = [
            String(displayID),
            String(Int(bounds.origin.x.rounded())),
            String(Int(bounds.origin.y.rounded())),
            String(Int(bounds.width.rounded())),
            String(Int(bounds.height.rounded()))
        ].joined(separator: ":")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func defaultStoreURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = baseURL.appendingPathComponent("TodoPilot", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("TodoPilot.sqlite")
    }
}

private extension CoreDataLocalStore {
    static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.entities = [
            taskEntity(),
            taskSourceEntity(),
            settingEntity(),
            reminderEventEntity(),
            captureSessionEntity(),
            agentRunEntity()
        ]
        return model
    }

    static func taskEntity() -> NSEntityDescription {
        entity(Entity.task, attributes: [
            attribute("localID", .UUIDAttributeType),
            attribute("title", .stringAttributeType),
            attribute("detail", .stringAttributeType, optional: true),
            attribute("priority", .stringAttributeType),
            attribute("status", .stringAttributeType),
            attribute("dueAt", .dateAttributeType, optional: true),
            attribute("sourceQuote", .stringAttributeType, optional: true),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
            attribute("deletedAt", .dateAttributeType, optional: true)
        ])
    }

    static func taskSourceEntity() -> NSEntityDescription {
        entity(Entity.taskSource, attributes: [
            attribute("localID", .UUIDAttributeType),
            attribute("taskLocalID", .UUIDAttributeType),
            attribute("sourceType", .stringAttributeType),
            attribute("sourceHash", .stringAttributeType, optional: true),
            attribute("sourceQuote", .stringAttributeType, optional: true),
            attribute("ocrTextRef", .stringAttributeType, optional: true),
            attribute("createdAt", .dateAttributeType)
        ])
    }

    static func settingEntity() -> NSEntityDescription {
        entity(Entity.setting, attributes: [
            attribute("key", .stringAttributeType),
            attribute("value", .stringAttributeType),
            attribute("updatedAt", .dateAttributeType)
        ])
    }

    static func reminderEventEntity() -> NSEntityDescription {
        entity(Entity.reminderEvent, attributes: [
            attribute("localID", .UUIDAttributeType),
            attribute("taskLocalID", .UUIDAttributeType, optional: true),
            attribute("eventType", .stringAttributeType),
            attribute("createdAt", .dateAttributeType)
        ])
    }

    static func captureSessionEntity() -> NSEntityDescription {
        entity(Entity.captureSession, attributes: [
            attribute("localID", .UUIDAttributeType),
            attribute("startedAt", .dateAttributeType),
            attribute("completedAt", .dateAttributeType, optional: true),
            attribute("status", .stringAttributeType),
            attribute("screenCount", .integer64AttributeType),
            attribute("selectionHash", .stringAttributeType, optional: true),
            attribute("surface", .stringAttributeType, optional: true)
        ])
    }

    static func agentRunEntity() -> NSEntityDescription {
        let agentRun = entity(Entity.agentRun, attributes: [
            attribute("runID", .UUIDAttributeType),
            attribute("taskID", .UUIDAttributeType),
            attribute("provider", .stringAttributeType),
            attribute("sessionIdentityHash", .stringAttributeType),
            attribute("turnIdentityHash", .stringAttributeType, optional: true),
            attribute("workspaceDisplayName", .stringAttributeType, optional: true),
            attribute("originBundleID", .stringAttributeType, optional: true),
            attribute("originProcessID", .integer64AttributeType, optional: true),
            attribute("state", .stringAttributeType),
            attribute("outcome", .stringAttributeType, optional: true),
            attribute("startedAt", .dateAttributeType),
            attribute("endedAt", .dateAttributeType, optional: true),
            attribute("lastEventAt", .dateAttributeType),
            attribute("userOverride", .stringAttributeType),
            attribute("reminderState", .stringAttributeType)
        ])
        agentRun.uniquenessConstraints = [["runID"]]
        return agentRun
    }

    static func entity(_ name: String, attributes: [NSAttributeDescription]) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = "NSManagedObject"
        entity.properties = attributes
        return entity
    }

    static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool = false
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        return attribute
    }
}

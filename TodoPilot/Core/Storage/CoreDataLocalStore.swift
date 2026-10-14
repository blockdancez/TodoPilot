import CoreData
import CoreGraphics
import CryptoKit
import Foundation
import OSLog

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

    private static let performanceLogger = Logger(subsystem: "com.fubb.TodoPilot", category: "storage-performance")
    private var persistentStoreLoaded = true
    private var taskLoadFailed = false

    // 仅用于存储回归测试：故障发生在真实 fetch/save 边界，不改变持久化协议。
    enum PersistenceStage: Equatable {
        case fetch(String)
        case save
    }
    var persistenceFaultInjector: ((PersistenceStage) throws -> Void)?
    var storageTestContext: NSManagedObjectContext { context }

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
            persistentStoreLoaded = false
            Self.logStorageError(loadError)
        }

        self.context = container.viewContext
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.undoManager = nil
    }

    func load() -> [TodoTask]? {
        autoreleasepool {
            guard persistentStoreLoaded else { return nil }
            do {
                let storedTasks = try fetchTasks()
                if !storedTasks.isEmpty {
                    taskLoadFailed = false
                    markInitialized()
                    markLegacyMigrated()
                    return storedTasks
                }

                if !defaults.bool(forKey: Keys.legacyMigrationCompleted),
                   let legacyTasks = legacyPersistence?.load() {
                    try synchronizeTasks(with: legacyTasks)
                    taskLoadFailed = false
                    markLegacyMigrated()
                    markInitialized()
                    return legacyTasks
                }

                taskLoadFailed = false
                return defaults.bool(forKey: Keys.storeInitialized) ? [] : nil
            } catch {
                // 读取失败不能被当成空库；成功重载前禁止完整快照覆盖原有任务。
                context.rollback()
                taskLoadFailed = true
                Self.logStorageError(error)
                return nil
            }
        }
    }

    func save(_ tasks: [TodoTask]) {
        let startedAt = ProcessInfo.processInfo.systemUptime
        var inserted = 0
        var updated = 0
        var deleted = 0
        var noop = true
        var success = false
        defer {
            let durationMS = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
            Self.performanceLogger.info("operation=tasks.save duration_ms=\(durationMS, privacy: .public) total=\(tasks.count, privacy: .public) insert=\(inserted, privacy: .public) update=\(updated, privacy: .public) delete=\(deleted, privacy: .public) noop=\(noop, privacy: .public) success=\(success, privacy: .public)")
        }
        autoreleasepool {
            guard persistentStoreLoaded, !taskLoadFailed else { return }
            do {
                try synchronizeTasks(with: tasks) {
                    context.processPendingChanges()
                    inserted = context.insertedObjects.count
                    updated = context.updatedObjects.count
                    deleted = context.deletedObjects.count
                    noop = !context.hasChanges
                }
                success = true
                markInitialized()
                markLegacyMigrated()
            } catch {
                context.rollback()
                Self.logStorageError(error)
            }
        }
    }

    func startCaptureSession(surface: String, screenCount: Int, startedAt: Date = Date()) -> UUID {
        let id = UUID()
        performStorageTransaction {
            let object = NSEntityDescription.insertNewObject(forEntityName: Entity.captureSession, into: context)
            object.setValue(id, forKey: "localID")
            object.setValue(startedAt, forKey: "startedAt")
            object.setValue(nil, forKey: "completedAt")
            object.setValue("STARTED", forKey: "status")
            object.setValue(Int64(max(0, screenCount)), forKey: "screenCount")
            object.setValue(nil, forKey: "selectionHash")
            object.setValue(surface, forKey: "surface")
        }
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
        autoreleasepool {
            do { return try fetchCaptureSessions() }
            catch {
                context.rollback()
                Self.logStorageError(error)
                return []
            }
        }
    }

    private func fetchCaptureSessions() throws -> [LocalCaptureSession] {
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.captureSession)
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: true)]
        return try fetchRecords(request).compactMap { object in
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
        }
    }

    func loadAgentRuns() -> [AgentRun] {
        autoreleasepool {
            do { return try fetchAgentRuns() }
            catch {
                context.rollback()
                Self.logStorageError(error)
                return []
            }
        }
    }

    private func fetchAgentRuns() throws -> [AgentRun] {
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.agentRun)
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: true)]
        return try fetchRecords(request).compactMap { object in
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
        }
    }

    func saveAgentRun(_ run: AgentRun) {
        performStorageTransaction { try upsertAgentRun(run) }
    }

    func saveAgentRuns(_ runs: [AgentRun]) {
        performStorageTransaction {
            for run in runs {
                try upsertAgentRun(run)
            }
        }
    }

    private func upsertAgentRun(_ run: AgentRun) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.agentRun)
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "runID == %@", run.id as CVarArg)
        let object = try fetchRecords(request).first
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
        performStorageTransaction {
            let request = NSFetchRequest<NSManagedObject>(entityName: Entity.agentRun)
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "runID == %@", runID as CVarArg)
            if let object = try fetchRecords(request).first {
                context.delete(object)
            }
        }
    }

    private func fetchTasks() throws -> [TodoTask] {
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.task)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let taskRecords = try fetchRecords(request)
        let sourcesByTaskID = try fetchTaskSourcesByTaskID()

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

    private func synchronizeTasks(with tasks: [TodoTask], beforeSave: () -> Void = {}) throws {
        let repairedTasks = TodoTaskIdentityRepair.deduplicated(tasks)
        // 每次保存只建立临时映射；先成功读取两张表，再执行任何变更。
        let taskRecords = try fetchRecords(NSFetchRequest<NSManagedObject>(entityName: Entity.task))
        let sourceRecords = try fetchRecords(NSFetchRequest<NSManagedObject>(entityName: Entity.taskSource))
        let incomingIDs = Set(repairedTasks.map(\.id))
        var tasksByID: [UUID: NSManagedObject] = [:]
        var sourcesByTaskID: [UUID: NSManagedObject] = [:]
        for object in taskRecords {
            guard let id = object.value(forKey: "localID") as? UUID,
                  incomingIDs.contains(id), tasksByID[id] == nil else {
                context.delete(object)
                continue
            }
            tasksByID[id] = object
        }
        for object in sourceRecords {
            guard let id = object.value(forKey: "taskLocalID") as? UUID,
                  incomingIDs.contains(id), tasksByID[id] != nil, sourcesByTaskID[id] == nil else {
                context.delete(object)
                continue
            }
            sourcesByTaskID[id] = object
        }
        for task in repairedTasks {
            let object = tasksByID[task.id]
                ?? NSEntityDescription.insertNewObject(forEntityName: Entity.task, into: context)
            updateTask(task, on: object)
            let source = sourcesByTaskID[task.id]
                ?? NSEntityDescription.insertNewObject(forEntityName: Entity.taskSource, into: context)
            if source.value(forKey: "localID") == nil {
                source.setValue(UUID(), forKey: "localID")
            }
            setValueIfChanged(task.id, forKey: "taskLocalID", on: source)
            setValueIfChanged(task.source.rawValue, forKey: "sourceType", on: source)
            setValueIfChanged(task.sourceKey, forKey: "sourceHash", on: source)
            setValueIfChanged(task.sourceQuote, forKey: "sourceQuote", on: source)
            setValueIfChanged(nil, forKey: "ocrTextRef", on: source)
            setValueIfChanged(task.createdAt, forKey: "createdAt", on: source)
        }
        beforeSave()
        try saveContext()
    }

    private func updateTask(_ task: TodoTask, on object: NSManagedObject) {
        setValueIfChanged(task.id, forKey: "localID", on: object)
        setValueIfChanged(task.title, forKey: "title", on: object)
        setValueIfChanged(task.detail, forKey: "detail", on: object)
        setValueIfChanged(task.priority.rawValue, forKey: "priority", on: object)
        setValueIfChanged(task.status.rawValue, forKey: "status", on: object)
        setValueIfChanged(task.dueAt, forKey: "dueAt", on: object)
        setValueIfChanged(task.sourceQuote, forKey: "sourceQuote", on: object)
        setValueIfChanged(task.createdAt, forKey: "createdAt", on: object)
        setValueIfChanged(task.updatedAt, forKey: "updatedAt", on: object)
        setValueIfChanged(task.deletedAt, forKey: "deletedAt", on: object)
    }

    private func setValueIfChanged(_ value: Any?, forKey key: String, on object: NSManagedObject) {
        let current = object.value(forKey: key)
        if current == nil, value == nil { return }
        if let current = current as? NSObject, let value = value as? NSObject,
           current.isEqual(value) { return }
        object.setValue(value, forKey: key)
    }

    private func fetchTaskSourcesByTaskID() throws -> [UUID: TaskSourceSnapshot] {
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.taskSource)
        let records = try fetchRecords(request)
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
        performStorageTransaction {
            let request = NSFetchRequest<NSManagedObject>(entityName: Entity.captureSession)
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "localID == %@", id as CVarArg)
            if let object = try fetchRecords(request).first {
                mutate(object)
            }
        }
    }

    private func fetchRecords(_ request: NSFetchRequest<NSManagedObject>) throws -> [NSManagedObject] {
        try persistenceFaultInjector?(.fetch(request.entityName ?? ""))
        return try context.fetch(request)
    }

    private func performStorageTransaction(_ mutate: () throws -> Void) {
        autoreleasepool {
            guard persistentStoreLoaded else { return }
            do {
                try mutate()
                try saveContext()
            } catch {
                // 共用 context 的任一事务失败都立即回滚，避免下次保存夹带未提交记录。
                context.rollback()
                Self.logStorageError(error)
            }
        }
    }

    private func saveContext() throws {
        guard context.hasChanges else { return }
        try persistenceFaultInjector?(.save)
        try context.save()
    }

    private static func logStorageError(_ error: Error) {
        let error = error as NSError
        let allowedDomains = [NSCocoaErrorDomain, NSOSStatusErrorDomain, NSPOSIXErrorDomain, NSMachErrorDomain]
        let domain = allowedDomains.contains(error.domain) ? error.domain : "other"
        performanceLogger.error("storage.failure domain=\(domain, privacy: .public) code=\(error.code, privacy: .public)")
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

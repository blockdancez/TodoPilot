import Darwin
import Foundation

enum AgentHookEvent: String, Codable, CaseIterable {
    case started
    case completed
    case failed
    case cancelled
    case sessionEnded
}

struct AgentHookEnvelopeV1: Codable, Equatable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let provider: AgentProvider
    let event: AgentHookEvent
    let sessionHash: String
    let turnHash: String?
    let title: String?
    let workspaceName: String?
    let occurredAt: Date
    let originBundleID: String?
    let originProcessID: Int32?
    let errorKind: String?
}

enum AgentBridgeRuntime {
    static func directoryURL(uid: uid_t = getuid()) -> URL {
        URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("com.fubb.TodoPilot-\(uid)", isDirectory: true)
    }

    static func socketURL(uid: uid_t = getuid()) -> URL {
        directoryURL(uid: uid).appendingPathComponent("agent-hook-v1.sock", isDirectory: false)
    }

    static func endpointHasPrivateOwnership(uid: uid_t = getuid()) -> Bool {
        var directoryInfo = stat()
        var socketInfo = stat()
        guard lstat(directoryURL(uid: uid).path, &directoryInfo) == 0,
              lstat(socketURL(uid: uid).path, &socketInfo) == 0 else {
            return false
        }
        return (directoryInfo.st_mode & S_IFMT) == S_IFDIR
            && directoryInfo.st_uid == uid
            && (directoryInfo.st_mode & 0o777) == 0o700
            && (socketInfo.st_mode & S_IFMT) == S_IFSOCK
            && socketInfo.st_uid == uid
            && (socketInfo.st_mode & 0o777) == 0o600
    }
}

enum AgentBridgeProbe {
    static func canConnect(
        socketURL: URL = AgentBridgeRuntime.socketURL(),
        timeoutMilliseconds: Int32 = 250
    ) -> Bool {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        let originalFlags = fcntl(fd, F_GETFL, 0)
        guard originalFlags >= 0,
              fcntl(fd, F_SETFL, originalFlags | O_NONBLOCK) >= 0 else {
            return false
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = socketURL.path
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        let copied = path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { destination in
                destination.withMemoryRebound(to: CChar.self, capacity: capacity) {
                    strlcpy($0, source, capacity)
                }
            }
        }
        guard copied < capacity else { return false }

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if connected == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let pollResult = poll(&descriptor, 1, max(1, timeoutMilliseconds))
        guard pollResult > 0, (descriptor.revents & Int16(POLLOUT)) != 0 else {
            return false
        }
        var socketError: Int32 = 0
        var socketErrorSize = socklen_t(MemoryLayout<Int32>.size)
        return getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &socketErrorSize) == 0
            && socketError == 0
    }
}

enum AgentBridgeValidationError: Error, Equatable {
    case oversized
    case malformed
    case unsupportedVersion
    case invalidIdentity
    case invalidTitle
    case invalidWorkspace
    case invalidOrigin
    case invalidErrorKind
}

enum AgentBridgeEnvelopeValidator {
    static let maximumMessageSize = 16 * 1_024
    private static let allowedErrorKinds: Set<String> = [
        "providerFailure",
        "aborted",
        "unknown"
    ]

    static func decode(_ data: Data) throws -> AgentHookEnvelopeV1 {
        guard data.count <= maximumMessageSize else {
            throw AgentBridgeValidationError.oversized
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            // 保留新 Hook 的毫秒先后顺序，同时兼容旧 Helper 的整秒时间。
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid agent event timestamp")
            }
            return date
        }
        guard let envelope = try? decoder.decode(AgentHookEnvelopeV1.self, from: data) else {
            throw AgentBridgeValidationError.malformed
        }
        try validate(envelope)
        return envelope
    }

    static func validate(_ envelope: AgentHookEnvelopeV1) throws {
        guard envelope.schemaVersion == AgentHookEnvelopeV1.schemaVersion else {
            throw AgentBridgeValidationError.unsupportedVersion
        }
        guard isSHA256(envelope.sessionHash),
              envelope.turnHash.map(isSHA256) ?? true else {
            throw AgentBridgeValidationError.invalidIdentity
        }
        if let title = envelope.title {
            guard !title.isEmpty,
                  title.count <= 80,
                  title.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0) }) else {
                throw AgentBridgeValidationError.invalidTitle
            }
        }
        if let workspaceName = envelope.workspaceName {
            guard !workspaceName.isEmpty,
                  workspaceName.count <= 100,
                  workspaceName == URL(fileURLWithPath: workspaceName).lastPathComponent,
                  !workspaceName.contains("/") else {
                throw AgentBridgeValidationError.invalidWorkspace
            }
        }
        if let bundleID = envelope.originBundleID {
            guard !bundleID.isEmpty, bundleID.count <= 160,
                  bundleID.unicodeScalars.allSatisfy({
                      !CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0)
                  }) else {
                throw AgentBridgeValidationError.invalidOrigin
            }
        }
        if let processID = envelope.originProcessID, processID <= 0 {
            throw AgentBridgeValidationError.invalidOrigin
        }
        if let errorKind = envelope.errorKind, !allowedErrorKinds.contains(errorKind) {
            throw AgentBridgeValidationError.invalidErrorKind
        }
    }

    static func peerUIDIsAllowed(_ peerUID: uid_t, currentUID: uid_t = getuid()) -> Bool {
        peerUID == currentUID
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 97...102:
                true
            default:
                false
            }
        }
    }
}

final class AgentBridgeServer {
    typealias EnvelopeHandler = @Sendable (AgentHookEnvelopeV1) -> Void

    private let queue: DispatchQueue
    private let fileManager: FileManager
    private let uid: uid_t
    private var listenerFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var handler: EnvelopeHandler?

    init(
        fileManager: FileManager = .default,
        uid: uid_t = getuid(),
        queue: DispatchQueue = DispatchQueue(label: "com.fubb.TodoPilot.agent-bridge", qos: .utility)
    ) {
        self.fileManager = fileManager
        self.uid = uid
        self.queue = queue
    }

    deinit {
        stop()
    }

    func start(handler: @escaping EnvelopeHandler) throws {
        guard listenerFD < 0 else {
            self.handler = handler
            return
        }

        let directoryURL = AgentBridgeRuntime.directoryURL(uid: uid)
        let socketURL = AgentBridgeRuntime.socketURL(uid: uid)
        try preparePrivateDirectory(directoryURL)
        if fileManager.fileExists(atPath: socketURL.path) {
            try fileManager.removeItem(at: socketURL)
        }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        do {
            try bindAndListen(fd: fd, path: socketURL.path)
            guard chmod(socketURL.path, S_IRUSR | S_IWUSR) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            Darwin.close(fd)
            try? fileManager.removeItem(at: socketURL)
            throw error
        }

        listenerFD = fd
        self.handler = handler
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptPendingConnection()
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        readSource = source
        source.resume()
    }

    func stop() {
        handler = nil
        if let source = readSource {
            readSource = nil
            source.cancel()
        } else if listenerFD >= 0 {
            Darwin.close(listenerFD)
        }
        listenerFD = -1
        try? fileManager.removeItem(at: AgentBridgeRuntime.socketURL(uid: uid))
    }

    private func preparePrivateDirectory(_ url: URL) throws {
        var info = stat()
        if lstat(url.path, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == uid else {
                throw POSIXError(.EPERM)
            }
        } else if errno == ENOENT {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        } else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard chmod(url.path, S_IRWXU) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func bindAndListen(fd: Int32, path: String) throws {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8CString)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count <= capacity else {
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                _ = pathBytes.withUnsafeBufferPointer { source in
                    memcpy(destination, source.baseAddress, pathBytes.count)
                }
            }
        }

        let length = socklen_t(MemoryLayout<sa_family_t>.size + pathBytes.count)
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, length)
            }
        }
        guard bindResult == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard Darwin.listen(fd, 16) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func acceptPendingConnection() {
        let clientFD = Darwin.accept(listenerFD, nil, nil)
        guard clientFD >= 0 else {
            return
        }
        defer { Darwin.close(clientFD) }

        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        guard getpeereid(clientFD, &peerUID, &peerGID) == 0,
              AgentBridgeEnvelopeValidator.peerUIDIsAllowed(peerUID, currentUID: uid) else {
            return
        }

        var timeout = timeval(tv_sec: 0, tv_usec: 250_000)
        _ = withUnsafePointer(to: &timeout) { pointer in
            setsockopt(clientFD, SOL_SOCKET, SO_RCVTIMEO, pointer, socklen_t(MemoryLayout<timeval>.size))
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while data.count <= AgentBridgeEnvelopeValidator.maximumMessageSize {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(clientFD, rawBuffer.baseAddress, rawBuffer.count)
            }
            guard count > 0 else {
                break
            }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard !data.isEmpty,
              data.count <= AgentBridgeEnvelopeValidator.maximumMessageSize,
              let envelope = try? AgentBridgeEnvelopeValidator.decode(data) else {
            return
        }
        handler?(envelope)
    }
}

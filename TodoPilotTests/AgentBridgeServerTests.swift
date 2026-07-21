import Darwin
import XCTest
@testable import TodoPilot

final class AgentBridgeServerTests: XCTestCase {
    func testEnvelopeRoundTripAcceptsMinimalSafeFields() throws {
        let envelope = TodoPilot.AgentHookEnvelopeV1(
            schemaVersion: 1,
            provider: .codex,
            event: .started,
            sessionHash: String(repeating: "a", count: 64),
            turnHash: String(repeating: "b", count: 64),
            title: "实现 Agent 监控",
            workspaceName: "TodoPilot",
            occurredAt: Date(timeIntervalSince1970: 1_800_000_000),
            originBundleID: "com.openai.codex",
            originProcessID: 123,
            errorKind: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let restored = try AgentBridgeEnvelopeValidator.decode(encoder.encode(envelope))

        XCTAssertEqual(restored, envelope)
    }

    func testEnvelopeRejectsUnknownVersionAndOversize() throws {
        let envelope = TodoPilot.AgentHookEnvelopeV1(
            schemaVersion: 2,
            provider: .cursor,
            event: .completed,
            sessionHash: String(repeating: "c", count: 64),
            turnHash: nil,
            title: nil,
            workspaceName: nil,
            occurredAt: Date(timeIntervalSince1970: 1_800_000_000),
            originBundleID: nil,
            originProcessID: nil,
            errorKind: nil
        )

        XCTAssertThrowsError(try AgentBridgeEnvelopeValidator.validate(envelope)) { error in
            XCTAssertEqual(error as? AgentBridgeValidationError, .unsupportedVersion)
        }
        XCTAssertThrowsError(
            try AgentBridgeEnvelopeValidator.decode(Data(repeating: 0, count: AgentBridgeEnvelopeValidator.maximumMessageSize + 1))
        ) { error in
            XCTAssertEqual(error as? AgentBridgeValidationError, .oversized)
        }
    }

    func testEnvelopeRejectsRawLikeIdentityMultilineTitleAndFullPath() {
        let base = TodoPilot.AgentHookEnvelopeV1(
            schemaVersion: 1,
            provider: .claudeCode,
            event: .failed,
            sessionHash: "raw-session-id",
            turnHash: nil,
            title: "line one\nline two",
            workspaceName: "/Users/example/SecretProject",
            occurredAt: Date(timeIntervalSince1970: 1_800_000_000),
            originBundleID: nil,
            originProcessID: nil,
            errorKind: "providerFailure"
        )

        XCTAssertThrowsError(try AgentBridgeEnvelopeValidator.validate(base))
        XCTAssertFalse(AgentBridgeEnvelopeValidator.peerUIDIsAllowed(getuid() + 1, currentUID: getuid()))
        XCTAssertTrue(AgentBridgeEnvelopeValidator.peerUIDIsAllowed(getuid(), currentUID: getuid()))
    }

    func testRuntimePathIsUserScopedAndShortEnoughForUnixSocket() {
        let path = AgentBridgeRuntime.socketURL(uid: 501).path

        XCTAssertEqual(path, "/tmp/com.fubb.TodoPilot-501/agent-hook-v1.sock")
        XCTAssertLessThan(path.utf8.count, 104)
    }

    func testServerCreatesPrivateSocketAndAcceptsCurrentUIDEnvelope() throws {
        let server = AgentBridgeServer()
        let received = expectation(description: "safe envelope received")
        let envelope = TodoPilot.AgentHookEnvelopeV1(
            schemaVersion: 1,
            provider: .claudeCode,
            event: .started,
            sessionHash: String(repeating: "d", count: 64),
            turnHash: nil,
            title: "检查本地 bridge",
            workspaceName: "TodoPilot",
            occurredAt: Date(timeIntervalSince1970: 1_800_000_000),
            originBundleID: nil,
            originProcessID: nil,
            errorKind: nil
        )
        try server.start { value in
            XCTAssertEqual(value, envelope)
            received.fulfill()
        }
        defer { server.stop() }

        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: AgentBridgeRuntime.directoryURL().path
        )
        let socketAttributes = try FileManager.default.attributesOfItem(
            atPath: AgentBridgeRuntime.socketURL().path
        )
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((socketAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertTrue(AgentBridgeRuntime.endpointHasPrivateOwnership())
        XCTAssertTrue(AgentBridgeProbe.canConnect())

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try sendToBridge(encoder.encode(envelope))
        wait(for: [received], timeout: 1)
    }

    private func sendToBridge(_ data: Data) throws {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        guard fd >= 0 else { return }
        defer { Darwin.close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(AgentBridgeRuntime.socketURL().path.utf8CString)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                _ = bytes.withUnsafeBufferPointer { source in
                    memcpy(destination, source.baseAddress, bytes.count)
                }
            }
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sa_family_t>.size + bytes.count))
            }
        }
        guard connected == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(fd, baseAddress.advanced(by: offset), buffer.count - offset)
                guard written > 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                offset += written
            }
        }
        _ = Darwin.shutdown(fd, SHUT_WR)
    }
}

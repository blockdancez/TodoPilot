import Darwin
import Foundation

struct UnixDomainSocketClient {
    private let timeoutMilliseconds: Int32

    init(timeoutMilliseconds: Int32 = 250) {
        self.timeoutMilliseconds = max(0, timeoutMilliseconds)
    }

    func send(_ data: Data, to socketPath: String) {
        guard data.count <= 16 * 1024 else { return }
        guard socketPath.utf8.count < MemoryLayout<sockaddr_un>.size - 2 else { return }

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }

        var noSignal: Int32 = 1
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSignal,
            socklen_t(MemoryLayout<Int32>.size)
        )

        let originalFlags = fcntl(descriptor, F_GETFL, 0)
        guard originalFlags >= 0 else { return }
        guard fcntl(descriptor, F_SETFL, originalFlags | O_NONBLOCK) >= 0 else { return }

        let deadline = DispatchTime.now().uptimeNanoseconds
            + UInt64(timeoutMilliseconds) * 1_000_000

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let sunPathSize = MemoryLayout.size(ofValue: address.sun_path)
        let copied = socketPath.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { destination in
                destination.withMemoryRebound(to: CChar.self, capacity: socketPath.utf8.count + 1) {
                    strlcpy($0, source, sunPathSize)
                }
            }
        }
        guard copied < sunPathSize else { return }

        let connected = withUnsafePointer(to: &address) { pointer -> Bool in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                let result = Darwin.connect(
                    descriptor,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
                if result == 0 { return true }
                guard errno == EINPROGRESS else { return false }
                return waitUntilWritable(descriptor: descriptor, deadline: deadline)
                    && socketError(descriptor: descriptor) == 0
            }
        }
        guard connected else { return }

        var payload = data
        payload.append(0x0A)
        payload.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < rawBuffer.count {
                let count = Darwin.send(
                    descriptor,
                    baseAddress.advanced(by: sent),
                    rawBuffer.count - sent,
                    0
                )
                if count > 0 {
                    sent += count
                    continue
                }
                if count < 0, errno == EINTR { continue }
                if count < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                    guard waitUntilWritable(descriptor: descriptor, deadline: deadline) else { return }
                    continue
                }
                return
            }
        }
    }

    private func waitUntilWritable(descriptor: Int32, deadline: UInt64) -> Bool {
        var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { return false }
            let remainingNanoseconds = deadline - now
            let remainingMilliseconds = Int32(min(
                UInt64(Int32.max),
                max(1, (remainingNanoseconds + 999_999) / 1_000_000)
            ))
            let result = poll(&pollDescriptor, 1, remainingMilliseconds)
            if result > 0 {
                return (pollDescriptor.revents & Int16(POLLOUT)) != 0
            }
            if result < 0, errno == EINTR { continue }
            return false
        }
    }

    private func socketError(descriptor: Int32) -> Int32 {
        var error: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &size) == 0 else {
            return errno
        }
        return error
    }
}

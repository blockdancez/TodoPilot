import Darwin
import Foundation

@main
enum TodoPilotAgentHookMain {
    private static let maximumInputBytes = 256 * 1024

    static func main() {
        // Provider hooks must never be made unavailable by TodoPilot. Every
        // invalid-input, decode, connection, and delivery failure is fail-open.
        guard let provider = providerArgument() else { return }
        defer {
            if let output = provider.noOpSuccessOutput {
                FileHandle.standardOutput.write(output)
            }
        }
        guard let input = readBoundedStandardInput() else { return }

        let adapter = AgentHookAdapter()
        guard let envelope = try? adapter.envelope(from: input, provider: provider) else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let encoded = try? encoder.encode(envelope), encoded.count <= 16 * 1024 else { return }

        UnixDomainSocketClient(timeoutMilliseconds: 250).send(
            encoded,
            to: AgentHookRuntimePath.socketPath()
        )
    }

    private static func providerArgument() -> AgentHookProvider? {
        let arguments = CommandLine.arguments.dropFirst()
        guard let flagIndex = arguments.firstIndex(of: "--provider") else { return nil }
        let valueIndex = arguments.index(after: flagIndex)
        guard valueIndex != arguments.endIndex else { return nil }
        return AgentHookProvider(rawValue: arguments[valueIndex])
    }

    private static func readBoundedStandardInput() -> Data? {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 8 * 1024)

        while true {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(STDIN_FILENO, rawBuffer.baseAddress, rawBuffer.count)
            }
            if count == 0 { return result }
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            guard result.count + count <= maximumInputBytes else { return nil }
            result.append(contentsOf: buffer.prefix(count))
        }
    }
}

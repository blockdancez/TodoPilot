import Darwin
import Foundation

enum AgentHookRuntimePath {
    static func socketPath(userID: uid_t = getuid()) -> String {
        "/tmp/com.fubb.TodoPilot-\(userID)/agent-hook-v1.sock"
    }
}

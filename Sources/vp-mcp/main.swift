import Foundation
import VPCore
import VPMCP

// stdio MCP server for Claude Code: JSON-RPC, one message per line. Logs go to stderr only.
signal(SIGPIPE, SIG_IGN)  // a reply to a closed pipe must not kill the server mid-cleanup
let paths = Paths.default()
let waiters = Waiters(paths: paths)
try? waiters.markPluginSeen(now: .now)
let server = MCPServer(store: Store(paths: paths), waiters: waiters,
                       pid: ProcessInfo.processInfo.processIdentifier, cwd: FileManager.default.currentDirectoryPath)

actor Output {
    func write(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}
let output = Output()

for try await line in FileHandle.standardInput.bytes.lines where !line.isEmpty {
    await server.start(line: line, write: { await output.write($0) })
}
// stdin closed: Claude Code ended the session. Cancel waits, finish replies, leave no waiter behind.
await server.shutdown()
waiters.unregister(pid: ProcessInfo.processInfo.processIdentifier)

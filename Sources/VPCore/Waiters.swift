import Foundation

/// A Claude Code session blocked in `wait_for_next_recording`.
public struct Waiter: Codable, Sendable, Equatable {
    public var pid: Int32
    public var cwd: String
    public var startedAt: Date
    public init(pid: Int32, cwd: String, startedAt: Date) { self.pid = pid; self.cwd = cwd; self.startedAt = startedAt }
}

/// `waiters/<pid>.json` files: how the MCP server tells the app a session is waiting,
/// without any socket.
public struct Waiters: Sendable {
    public let paths: Paths
    public init(paths: Paths) { self.paths = paths }

    private func file(_ pid: Int32) -> URL { paths.waiters.appending(path: "\(pid).json") }

    public func register(_ w: Waiter) throws {
        try paths.ensureRoot()
        try writeJSON(w, to: file(w.pid))
    }

    public func unregister(pid: Int32) { try? FileManager.default.removeItem(at: file(pid)) }

    /// Live waiters, newest first. Files left by dead processes are deleted.
    public func live(isAlive: (Int32) -> Bool = Waiters.processIsAlive) -> [Waiter] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: paths.waiters.path)) ?? []
        var out: [Waiter] = []
        for name in names where name.hasSuffix(".json") && !name.hasPrefix(".") {
            guard let w = try? readJSON(Waiter.self, from: paths.waiters.appending(path: name)) else { continue }
            if isAlive(w.pid) { out.append(w) } else { unregister(pid: w.pid) }
        }
        return out.sorted { $0.startedAt > $1.startedAt }
    }

    public func mostRecent(isAlive: (Int32) -> Bool = Waiters.processIsAlive) -> Waiter? { live(isAlive: isAlive).first }

    public static func processIsAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 || errno == EPERM }

    private var pluginSeenFile: URL { paths.root.appending(path: "plugin-seen.json") }
    private struct Seen: Codable { var at: Date }

    public func markPluginSeen(now: Date) throws {
        try paths.ensureRoot()
        try writeJSON(Seen(at: now), to: pluginSeenFile)
    }

    public func pluginSeen() -> Date? { (try? readJSON(Seen.self, from: pluginSeenFile))?.at }
}

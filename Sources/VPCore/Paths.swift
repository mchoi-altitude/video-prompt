import Foundation

/// Folder layout under the data root (`~/Library/Application Support/VideoPrompt`).
public struct Paths: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root }

    /// `VIDEO_PROMPT_HOME` if set, else the Application Support folder. Created with mode 0700.
    public static func `default`() -> Paths {
        let root: URL
        if let home = ProcessInfo.processInfo.environment["VIDEO_PROMPT_HOME"], !home.isEmpty {
            root = URL(fileURLWithPath: (home as NSString).expandingTildeInPath)
        } else {
            root = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support/VideoPrompt")
        }
        let p = Paths(root: root)
        try? p.ensureRoot()
        return p
    }

    public var recordings: URL { root.appending(path: "recordings") }
    public var waiters: URL { root.appending(path: "waiters") }
    public var models: URL { root.appending(path: "models") }
    public func recording(_ id: String) -> URL { recordings.appending(path: id) }
    public func raw(_ id: String) -> URL { recording(id).appending(path: "raw") }

    public func ensureRoot() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try fm.createDirectory(at: recordings, withIntermediateDirectories: true)
        try fm.createDirectory(at: waiters, withIntermediateDirectories: true)
    }

    /// Creates `recordings/<id>/` and returns the id: `YYYYMMDD-HHMMSS`, then `-2`, `-3`… on collision.
    public func newRecordingID(now: Date, calendar: Calendar = .current) throws -> String {
        try ensureRoot()
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        let stamp = String(format: "%04d%02d%02d-%02d%02d%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
        var id = stamp, n = 1
        while true {
            do {
                try FileManager.default.createDirectory(at: recording(id), withIntermediateDirectories: false)
                return id
            } catch CocoaError.fileWriteFileExists {
                n += 1
                id = "\(stamp)-\(n)"
            }
        }
    }
}

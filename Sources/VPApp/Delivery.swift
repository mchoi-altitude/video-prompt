import Foundation
import VPCore
import VPProcess

public protocol Pasteboard: Sendable { func setString(_ s: String) }

/// What to paste into Claude Code: quoted, because the data folder path has a space.
public func reference(for id: String, paths: Paths) -> String {
    "@\"\(paths.recording(id).appending(path: "prompt.md").path)\""
}

public enum SendOutcome: Equatable, Sendable {
    case delivered(Waiter)
    /// The waiting session was gone by the time Send was pressed; saved and copied instead.
    case fellBackToClipboard
}

/// The review panel's four buttons.
public struct Delivery: Sendable {
    let store: Store
    let paths: Paths
    let waiters: Waiters
    let pasteboard: Pasteboard
    let isAlive: @Sendable (Int32) -> Bool

    public init(store: Store, paths: Paths, waiters: Waiters, pasteboard: Pasteboard,
                isAlive: @escaping @Sendable (Int32) -> Bool = Waiters.processIsAlive) {
        self.store = store; self.paths = paths; self.waiters = waiters; self.pasteboard = pasteboard; self.isAlive = isAlive
    }

    /// Sends to the most recent waiting session, checked now (it may have quit while the panel was open).
    public func send(_ id: String, edits: ReviewEdits) throws -> SendOutcome {
        guard let w = waiters.mostRecent(isAlive: isAlive) else {
            try saveAndCopy(id, edits: edits)
            return .fellBackToClipboard
        }
        try finalize(id: id, edits: edits, store: store, paths: paths, deliverTo: w)
        return .delivered(w)
    }

    public func saveAndCopy(_ id: String, edits: ReviewEdits) throws {
        try finalize(id: id, edits: edits, store: store, paths: paths)
        pasteboard.setString(reference(for: id, paths: paths))
    }

    /// Saves without waking a waiting session, and copies the reference.
    public func copyReference(_ id: String, edits: ReviewEdits) throws { try saveAndCopy(id, edits: edits) }

    public func discard(_ id: String) throws { try store.trash([id]) }
}

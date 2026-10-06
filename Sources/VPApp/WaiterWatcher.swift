import Combine
import Foundation
import VPCore

/// Whether a Claude Code session is blocked in `wait_for_next_recording`. The app polls every second.
@MainActor
public final class WaiterWatcher: ObservableObject {
    @Published public private(set) var current: Waiter?
    private let waiters: Waiters

    public init(waiters: Waiters) { self.waiters = waiters }

    public func poll() {
        let w = waiters.mostRecent()
        if w != current { current = w }
    }
}

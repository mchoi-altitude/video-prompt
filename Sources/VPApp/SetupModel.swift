import Combine
import Foundation

public enum MicAccess: Equatable, Sendable { case notDetermined, granted, denied }

/// What the first-run window checks; the app reads the real system, tests fake it.
public protocol SetupSystem: Sendable {
    var screenGranted: Bool { get }
    var micAccess: MicAccess { get }
    var speechInstalled: Bool { get }
    var pluginSeen: Bool { get }
}

public enum StepStatus: Equatable, Sendable {
    case todo, done
    /// Usable without it, but something is missing (e.g. microphone denied).
    case warning
}

/// First-run setup: Screen Recording, Microphone, speech-to-text, Claude Code. Claude Code is
/// optional (Copy reference works without the plugin); a denied microphone still lets you finish.
@MainActor
public final class SetupModel: ObservableObject {
    @Published public private(set) var screen: StepStatus = .todo
    @Published public private(set) var microphone: StepStatus = .todo
    @Published public private(set) var speech: StepStatus = .todo
    @Published public private(set) var claude: StepStatus = .todo
    private let system: SetupSystem

    public init(system: SetupSystem) {
        self.system = system
        refresh()
    }

    public func refresh() {
        screen = system.screenGranted ? .done : .todo
        microphone = switch system.micAccess { case .granted: .done; case .denied: .warning; case .notDetermined: .todo }
        speech = system.speechInstalled ? .done : .todo
        claude = system.pluginSeen ? .done : .todo
    }

    public var canFinish: Bool { screen == .done && microphone != .todo && speech == .done }
}

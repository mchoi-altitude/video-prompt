import Foundation
import VPCore

public struct AppSettings: Codable, Equatable, Sendable {
    public var retention: RetentionPolicy = .default
    public var lastMode: CaptureMode = .window
    public var drawingsFade = true
    public var reviewStep = true
    public init() {}
}

/// Settings as one JSON blob in UserDefaults; anything unreadable falls back to defaults.
public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let key = "settings"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var settings: AppSettings {
        get {
            guard let data = defaults.data(forKey: Self.key),
                  let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
            return s
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.key) }
    }
}

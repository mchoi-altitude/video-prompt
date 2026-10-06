import Foundation
import VPCore

public struct AppSettings: Codable, Equatable, Sendable {
    public var retention: RetentionPolicy = .default
    public var lastMode: CaptureMode = .window
    public var drawingsFade = true
    public var reviewStep = true
    /// The first-run setup window has been shown once.
    public var setupShown = false
    public init() {}

    private enum K: String, CodingKey { case retention, lastMode, drawingsFade, reviewStep, setupShown }

    /// Missing keys keep their defaults, so adding a setting never resets the others.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let d = AppSettings()
        retention = (try? c.decodeIfPresent(RetentionPolicy.self, forKey: .retention)) ?? d.retention
        lastMode = (try? c.decodeIfPresent(CaptureMode.self, forKey: .lastMode)) ?? d.lastMode
        drawingsFade = (try? c.decodeIfPresent(Bool.self, forKey: .drawingsFade)) ?? d.drawingsFade
        reviewStep = (try? c.decodeIfPresent(Bool.self, forKey: .reviewStep)) ?? d.reviewStep
        setupShown = (try? c.decodeIfPresent(Bool.self, forKey: .setupShown)) ?? d.setupShown
    }
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

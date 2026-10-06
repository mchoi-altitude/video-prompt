import CoreGraphics
import Foundation
import Testing
import VPCore
@testable import VPApp

private func freshDefaults() -> UserDefaults {
    let name = "vp-test-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

@Test func defaultsMatchSpec() {
    let s = SettingsStore(defaults: freshDefaults()).settings
    #expect(s.lastMode == .window)
    #expect(s.drawingsFade)
    #expect(s.reviewStep)
    #expect(s.retention == .days(3))
}

@Test func settingsRoundTrip() {
    let d = freshDefaults()
    let store = SettingsStore(defaults: d)
    store.settings.retention = .keepLast(20)
    store.settings.lastMode = .area
    #expect(SettingsStore(defaults: d).settings.retention == .keepLast(20))
    #expect(SettingsStore(defaults: d).settings.lastMode == .area)
}

@Test func corruptBlobFallsBackToDefaults() {
    let d = freshDefaults()
    d.set(Data("nope".utf8), forKey: "settings")
    #expect(SettingsStore(defaults: d).settings == AppSettings())
}

@Test func pointFlipsY() {
    #expect(ScreenGeometry.topLeft(CGPoint(x: 10, y: 890), primaryHeight: 900) == Point(x: 10, y: 10))
}

@Test func rectFlipsY() {
    #expect(ScreenGeometry.topLeft(CGRect(x: 40, y: 276, width: 740, height: 560), primaryHeight: 900)
            == Rect(x: 40, y: 64, w: 740, h: 560))
}

@Test func rectRoundTrips() {
    let r = Rect(x: 40, y: 64, w: 740, h: 560)
    #expect(ScreenGeometry.topLeft(ScreenGeometry.appKit(r, primaryHeight: 900), primaryHeight: 900) == r)
}

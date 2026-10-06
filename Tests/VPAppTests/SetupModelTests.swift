import Foundation
import Testing
@testable import VPApp

final class FakeSystem: SetupSystem, @unchecked Sendable {
    var screen = false, mic: MicAccess = .notDetermined, speech = false, plugin = false
    var screenGranted: Bool { screen }
    var micAccess: MicAccess { mic }
    var speechInstalled: Bool { speech }
    var pluginSeen: Bool { plugin }
}

@Test @MainActor func stepsFollowSystemState() {
    let sys = FakeSystem(); let m = SetupModel(system: sys)
    #expect(m.screen == .todo && m.microphone == .todo && m.speech == .todo && m.claude == .todo)
    sys.screen = true; sys.mic = .granted; sys.speech = true; sys.plugin = true
    m.refresh()
    #expect(m.screen == .done && m.microphone == .done && m.speech == .done && m.claude == .done)
}

@Test @MainActor func doneNeedsPermissionsAndSpeech() {
    let sys = FakeSystem(); let m = SetupModel(system: sys)
    sys.screen = true; sys.mic = .granted; m.refresh()
    #expect(!m.canFinish)                       // speech-to-text still missing
    sys.speech = true; m.refresh()
    #expect(m.canFinish)                        // Claude Code connection is optional
}

@Test @MainActor func deniedMicStillLetsYouFinish() {
    let sys = FakeSystem(); let m = SetupModel(system: sys)
    sys.screen = true; sys.mic = .denied; sys.speech = true; m.refresh()
    #expect(m.microphone == .warning)
    #expect(m.canFinish)
}

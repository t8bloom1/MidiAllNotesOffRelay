import SwiftUI

@main
struct MidiAllNotesOffRelayApp: App {
    // Settings is the single source of truth; the engine observes it.
    @StateObject private var settings: AppSettings
    @StateObject private var engine: MidiEngine

    init() {
        let s = AppSettings()
        _settings = StateObject(wrappedValue: s)
        _engine = StateObject(wrappedValue: MidiEngine(settings: s))
    }

    var body: some Scene {
        WindowGroup {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(engine)
                .frame(minWidth: 440, minHeight: 460)
        }
        .windowResizability(.contentSize)
    }
}

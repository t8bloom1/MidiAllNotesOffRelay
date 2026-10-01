import Foundation
import Combine

/// What incoming MIDI message triggers the relay.
///
/// Reason's transport **Stop** button emits a MIDI System Real-Time **Stop**
/// message (status byte `0xFC`, decimal 252) — a channel-less, data-less
/// message. That is the primary trigger. The Control Change options are kept
/// as fallbacks for setups/DAWs that instead send "all notes off" (CC 123) or
/// "all sound off" (CC 120).
enum TriggerMode: Int, CaseIterable, Identifiable {
    case stop            = 0   // System Real-Time Stop, 0xFC
    case allNotesOff     = 1   // CC 123
    case allSoundOff     = 2   // CC 120
    case stopOrAllNotes  = 3   // 0xFC OR CC 123
    case any             = 4   // 0xFC OR CC 120 OR CC 123

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .stop:           return "MIDI Stop (0xFC)"
        case .allNotesOff:    return "All Notes Off (CC 123)"
        case .allSoundOff:    return "All Sound Off (CC 120)"
        case .stopOrAllNotes: return "Stop or All Notes Off (0xFC / CC 123)"
        case .any:            return "Any (Stop / CC 120 / CC 123)"
        }
    }

    /// Whether this mode reacts to the System Real-Time Stop message (0xFC).
    var listensForStop: Bool {
        switch self {
        case .stop, .stopOrAllNotes, .any: return true
        case .allNotesOff, .allSoundOff:   return false
        }
    }

    /// The Control Change controller numbers this mode listens for (may be empty).
    var controllerNumbers: Set<UInt8> {
        switch self {
        case .stop:           return []
        case .allNotesOff:    return [123]
        case .allSoundOff:    return [120]
        case .stopOrAllNotes: return [123]
        case .any:            return [120, 123]
        }
    }
}

/// Observable, persisted application settings.
///
/// Persistence is via `UserDefaults`. The MIDI endpoints are stored by their
/// stable CoreMIDI `uniqueID` (an Int32) rather than by name, so the app keeps
/// working if two ports happen to share a name. `0` means "not selected".
final class AppSettings: ObservableObject {

    // MARK: Persisted keys
    private enum Key {
        static let inputUniqueID  = "inputUniqueID"
        static let outputUniqueID = "outputUniqueID"
        static let outputChannel  = "outputChannel"   // 1...16 (user-facing)
        static let outputNote     = "outputNote"      // 0...127
        static let outputVelocity = "outputVelocity"  // 1...127
        static let gateMillis     = "gateMillis"      // note-on duration in ms
        static let triggerMode    = "triggerMode"     // TriggerMode.rawValue
    }

    private let defaults: UserDefaults

    // MARK: Published, persisted properties

    /// CoreMIDI uniqueID of the input source to listen on. 0 = none selected.
    @Published var inputUniqueID: Int32 {
        didSet { defaults.set(Int(inputUniqueID), forKey: Key.inputUniqueID) }
    }

    /// CoreMIDI uniqueID of the output destination to send to. 0 = none selected.
    @Published var outputUniqueID: Int32 {
        didSet { defaults.set(Int(outputUniqueID), forKey: Key.outputUniqueID) }
    }

    /// Output MIDI channel, 1...16 as shown to the user (wire value is 0...15).
    @Published var outputChannel: Int {
        didSet { defaults.set(outputChannel, forKey: Key.outputChannel) }
    }

    /// Output note number, 0...127.
    @Published var outputNote: Int {
        didSet { defaults.set(outputNote, forKey: Key.outputNote) }
    }

    /// Output note velocity, 1...127.
    @Published var outputVelocity: Int {
        didSet { defaults.set(outputVelocity, forKey: Key.outputVelocity) }
    }

    /// How long the note is held on before the note-off, in milliseconds.
    @Published var gateMillis: Int {
        didSet { defaults.set(gateMillis, forKey: Key.gateMillis) }
    }

    /// Which CC message(s) trigger the relay.
    @Published var triggerMode: TriggerMode {
        didSet { defaults.set(triggerMode.rawValue, forKey: Key.triggerMode) }
    }

    // MARK: Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.inputUniqueID  = Int32(defaults.integer(forKey: Key.inputUniqueID))
        self.outputUniqueID = Int32(defaults.integer(forKey: Key.outputUniqueID))

        // Sensible first-run defaults.
        self.outputChannel  = defaults.object(forKey: Key.outputChannel)  as? Int ?? 1
        self.outputNote     = defaults.object(forKey: Key.outputNote)     as? Int ?? 60   // Middle C
        self.outputVelocity = defaults.object(forKey: Key.outputVelocity) as? Int ?? 100
        self.gateMillis     = defaults.object(forKey: Key.gateMillis)     as? Int ?? 500
        let modeRaw         = defaults.object(forKey: Key.triggerMode)    as? Int ?? TriggerMode.stop.rawValue
        self.triggerMode    = TriggerMode(rawValue: modeRaw) ?? .stop
    }

    // MARK: Convenience

    /// MIDI wire channel (0...15) derived from the 1...16 user value.
    var outputChannelZeroBased: UInt8 {
        UInt8(max(1, min(16, outputChannel)) - 1)
    }
}

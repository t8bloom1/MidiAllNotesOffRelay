import Foundation
import CoreMIDI
import Combine

/// A selectable MIDI endpoint (source or destination) for the settings UI.
struct MidiEndpoint: Identifiable, Hashable {
    let uniqueID: Int32
    let displayName: String
    var id: Int32 { uniqueID }
}

/// Owns the CoreMIDI client, an input port, and an output port. It listens on
/// the user-selected source for "all notes off"-style Control Change messages
/// (on any channel) and, when one is seen, emits a timed note on/off on the
/// user-selected destination.
final class MidiEngine: ObservableObject {

    // MARK: Published state for the UI

    @Published private(set) var sources: [MidiEndpoint] = []
    @Published private(set) var destinations: [MidiEndpoint] = []

    /// Human-readable status line shown in the UI.
    @Published private(set) var statusMessage: String = "Starting…"

    /// Timestamp of the last successful relay, for UI feedback.
    @Published private(set) var lastTriggerDate: Date?

    // MARK: Dependencies

    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()

    // MARK: CoreMIDI handles

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()

    /// The source we are currently connected to (so we can disconnect cleanly).
    private var connectedSource: MIDIEndpointRef?

    /// Serial queue guarding pending note-off work so a rapid re-trigger cancels
    /// the previous scheduled note-off.
    private let scheduleQueue = DispatchQueue(label: "com.example.MidiAllNotesOffRelay.schedule")
    private var pendingNoteOff: DispatchWorkItem?

    // MARK: Lifecycle

    init(settings: AppSettings) {
        self.settings = settings
        setupClientAndPorts()
        refreshEndpoints()
        observeSetupChanges()
        connectSelectedSource()
        updateStatus()
    }

    deinit {
        if let src = connectedSource {
            MIDIPortDisconnectSource(inputPort, src)
        }
        if outputPort != 0 { MIDIPortDispose(outputPort) }
        if inputPort != 0 { MIDIPortDispose(inputPort) }
        if client != 0 { MIDIClientDispose(client) }
    }

    // MARK: Setup

    private func setupClientAndPorts() {
        // MIDIClient notifies us when the MIDI environment changes (ports added/removed).
        let notifyBlock: MIDINotifyBlock = { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.refreshEndpoints()
                // A port we depend on may have appeared or disappeared.
                self.connectSelectedSource()
                self.updateStatus()
            }
        }
        var status = MIDIClientCreateWithBlock("MidiAllNotesOffRelay.Client" as CFString, &client, notifyBlock)
        guard status == noErr else {
            statusMessage = "Failed to create MIDI client (\(status))."
            return
        }

        // Input port with a receive block (modern, packet-list based API).
        let receiveBlock: MIDIReceiveBlock = { [weak self] eventList, _ in
            self?.handleIncoming(eventList)
        }
        status = MIDIInputPortCreateWithProtocol(
            client,
            "MidiAllNotesOffRelay.Input" as CFString,
            ._1_0,
            &inputPort,
            receiveBlock
        )
        guard status == noErr else {
            statusMessage = "Failed to create MIDI input port (\(status))."
            return
        }

        // Output port for sending our note.
        status = MIDIOutputPortCreate(client, "MidiAllNotesOffRelay.Output" as CFString, &outputPort)
        if status != noErr {
            statusMessage = "Failed to create MIDI output port (\(status))."
        }
    }

    /// React when the user changes the selected input source.
    private func observeSetupChanges() {
        settings.$inputUniqueID
            .removeDuplicates()
            .sink { [weak self] _ in
                // Defer to the next runloop tick so `settings` has committed the value.
                DispatchQueue.main.async {
                    self?.connectSelectedSource()
                    self?.updateStatus()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Endpoint enumeration

    /// Rebuild the lists of available sources and destinations.
    func refreshEndpoints() {
        var srcs: [MidiEndpoint] = []
        for i in 0..<MIDIGetNumberOfSources() {
            let ep = MIDIGetSource(i)
            guard ep != 0 else { continue }
            srcs.append(MidiEndpoint(uniqueID: uniqueID(of: ep), displayName: name(of: ep)))
        }

        var dests: [MidiEndpoint] = []
        for i in 0..<MIDIGetNumberOfDestinations() {
            let ep = MIDIGetDestination(i)
            guard ep != 0 else { continue }
            dests.append(MidiEndpoint(uniqueID: uniqueID(of: ep), displayName: name(of: ep)))
        }

        self.sources = srcs
        self.destinations = dests
    }

    // MARK: Source connection

    /// Connect the input port to whichever source matches the saved uniqueID,
    /// disconnecting any previously connected source first.
    private func connectSelectedSource() {
        // Disconnect previous.
        if let src = connectedSource {
            MIDIPortDisconnectSource(inputPort, src)
            connectedSource = nil
        }

        let wanted = settings.inputUniqueID
        guard wanted != 0 else { return }

        guard let ep = endpoint(forUniqueID: wanted, isSource: true) else { return }
        let status = MIDIPortConnectSource(inputPort, ep, nil)
        if status == noErr {
            connectedSource = ep
        }
    }

    // MARK: Incoming MIDI

    private func handleIncoming(_ eventList: UnsafePointer<MIDIEventList>) {
        let mode = settings.triggerMode
        let triggers = mode.controllerNumbers
        let watchStop = mode.listensForStop

        // Walk the event list. For the MIDI 1.0 protocol, each message arrives as
        // a single 32-bit Universal MIDI Packet (UMP) word laid out as:
        //   byte 3 (bits 28-31): message type nibble
        //   byte 3 (bits 24-27): group nibble
        //   byte 2 (bits 16-23): status byte
        //   byte 1 (bits  8-15): data byte 1
        //   byte 0 (bits  0- 7): data byte 2
        var packet = eventList.pointee.packet
        let numPackets = Int(eventList.pointee.numPackets)

        for _ in 0..<numPackets {
            let wordCount = Int(packet.wordCount)
            // Access the words tuple safely.
            withUnsafeBytes(of: packet.words) { raw in
                let words = raw.bindMemory(to: UInt32.self)
                var index = 0
                while index < wordCount {
                    let word = words[index]
                    let messageType = UInt8((word >> 28) & 0xF)
                    let statusByte  = UInt8((word >> 16) & 0xFF)

                    switch messageType {
                    case 0x1:
                        // System Real-Time / System Common. MIDI Stop = 0xFC.
                        if watchStop && statusByte == 0xFC {
                            fireOnMain()
                        }
                        index += 1

                    case 0x2:
                        // MIDI 1.0 Channel Voice (single word).
                        let statusNibble = UInt8((statusByte >> 4) & 0xF) // high nibble of status
                        let controller   = UInt8((word >> 8) & 0x7F)      // data byte 1
                        // 0xB = Control Change (any channel; channel is ignored).
                        if statusNibble == 0xB && triggers.contains(controller) {
                            fireOnMain()
                        }
                        index += 1

                    default:
                        // Skip messages of other types by their known word counts.
                        index += wordsForMessageType(messageType)
                    }
                }
            }

            packet = MIDIEventPacketNext(&packet).pointee
        }
    }

    /// The receive block runs on a realtime MIDI thread; hop to main before
    /// touching settings or sending output.
    private func fireOnMain() {
        DispatchQueue.main.async { [weak self] in
            self?.fireRelay()
        }
    }

    /// Number of 32-bit words occupied by a Universal MIDI Packet message type.
    private func wordsForMessageType(_ type: UInt8) -> Int {
        switch type {
        case 0x0, 0x1, 0x2, 0x6: return 1
        case 0x3, 0x4, 0x8, 0x9, 0xA: return 2
        case 0xB, 0xC: return 3
        case 0xD, 0xE, 0xF: return 4
        default: return 1
        }
    }

    // MARK: Relay (send the configured note)

    /// Public entry point for the "Send test note" button.
    func sendTestNote() {
        fireRelay()
    }

    private func fireRelay() {
        let channel = settings.outputChannelZeroBased
        let note = UInt8(max(0, min(127, settings.outputNote)))
        let velocity = UInt8(max(1, min(127, settings.outputVelocity)))
        let gate = max(1, settings.gateMillis)

        guard let dest = endpoint(forUniqueID: settings.outputUniqueID, isSource: false) else {
            DispatchQueue.main.async { self.statusMessage = "Triggered, but no output destination selected." }
            return
        }

        // Note On.
        sendChannelVoice(status: 0x90, channel: channel, data1: note, data2: velocity, to: dest)

        // Schedule Note Off after the gate, cancelling any previous pending one.
        scheduleQueue.async { [weak self] in
            guard let self = self else { return }
            self.pendingNoteOff?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                // Note Off (velocity 0 note-on is common, but use real Note Off 0x80).
                self.sendChannelVoice(status: 0x80, channel: channel, data1: note, data2: 0, to: dest)
            }
            self.pendingNoteOff = work
            self.scheduleQueue.asyncAfter(deadline: .now() + .milliseconds(gate), execute: work)
        }

        DispatchQueue.main.async {
            self.lastTriggerDate = Date()
            self.updateStatus()
        }
    }

    /// Build and send a single MIDI 1.0 channel-voice message via the output port.
    private func sendChannelVoice(status: UInt8, channel: UInt8, data1: UInt8, data2: UInt8, to dest: MIDIEndpointRef) {
        let statusByte = status | (channel & 0x0F)

        // Build a Universal MIDI Packet (UMP) MIDI 1.0 channel-voice word:
        //   nibble 7: message type 0x2 (MIDI 1.0 channel voice)
        //   nibble 6: group (0)
        //   byte 1:   status byte (status high nibble | channel)
        //   byte 2:   data1
        //   byte 3:   data2
        let word: UInt32 =
            (UInt32(0x2) << 28) |
            (UInt32(statusByte) << 16) |
            (UInt32(data1) << 8) |
            UInt32(data2)

        var eventList = MIDIEventList()
        let packet = MIDIEventListInit(&eventList, ._1_0)
        var w = word
        // timestamp 0 = send immediately.
        _ = MIDIEventListAdd(&eventList, MemoryLayout<MIDIEventList>.size, packet, 0, 1, &w)

        let sendStatus = MIDISendEventList(outputPort, dest, &eventList)
        if sendStatus != noErr {
            DispatchQueue.main.async { self.statusMessage = "MIDI send failed (\(sendStatus))." }
        }
    }

    // MARK: Helpers

    private func endpoint(forUniqueID uid: Int32, isSource: Bool) -> MIDIEndpointRef? {
        guard uid != 0 else { return nil }
        let count = isSource ? MIDIGetNumberOfSources() : MIDIGetNumberOfDestinations()
        for i in 0..<count {
            let ep = isSource ? MIDIGetSource(i) : MIDIGetDestination(i)
            if uniqueID(of: ep) == uid { return ep }
        }
        return nil
    }

    private func uniqueID(of ep: MIDIEndpointRef) -> Int32 {
        var uid: Int32 = 0
        MIDIObjectGetIntegerProperty(ep, kMIDIPropertyUniqueID, &uid)
        return uid
    }

    private func name(of ep: MIDIEndpointRef) -> String {
        var cf: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(ep, kMIDIPropertyDisplayName, &cf)
        if status == noErr, let cf = cf {
            return cf.takeRetainedValue() as String
        }
        return "Unknown"
    }

    private func updateStatus() {
        var parts: [String] = []
        if settings.inputUniqueID == 0 {
            parts.append("No input selected")
        } else if connectedSource == nil {
            parts.append("Input unavailable")
        } else {
            parts.append("Listening")
        }
        if settings.outputUniqueID == 0 {
            parts.append("no output")
        }
        if let last = lastTriggerDate {
            let f = DateFormatter()
            f.dateStyle = .none
            f.timeStyle = .medium
            parts.append("last trigger \(f.string(from: last))")
        }
        statusMessage = parts.joined(separator: " · ")
    }
}

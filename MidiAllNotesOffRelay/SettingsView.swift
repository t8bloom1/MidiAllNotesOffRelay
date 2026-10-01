import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var engine: MidiEngine

    var body: some View {
        Form {
            Section("Listen") {
                Picker("Input bus", selection: inputSelection) {
                    Text("— none —").tag(Int32(0))
                    ForEach(engine.sources) { ep in
                        Text(ep.displayName).tag(ep.uniqueID)
                    }
                }

                Picker("Trigger on", selection: $settings.triggerMode) {
                    ForEach(TriggerMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Text("MIDI Stop (0xFC) is channel-less. The CC options react on any channel of the input bus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Send") {
                Picker("Output bus", selection: outputSelection) {
                    Text("— none —").tag(Int32(0))
                    ForEach(engine.destinations) { ep in
                        Text(ep.displayName).tag(ep.uniqueID)
                    }
                }

                Stepper(value: $settings.outputChannel, in: 1...16) {
                    LabeledContent("Channel", value: "\(settings.outputChannel)")
                }

                Stepper(value: $settings.outputNote, in: 0...127) {
                    LabeledContent("Note", value: "\(settings.outputNote)  (\(Self.noteName(settings.outputNote)))")
                }

                Stepper(value: $settings.outputVelocity, in: 1...127) {
                    LabeledContent("Velocity", value: "\(settings.outputVelocity)")
                }

                Stepper(value: $settings.gateMillis, in: 10...5000, step: 10) {
                    LabeledContent("Note length", value: "\(settings.gateMillis) ms")
                }
            }

            Section {
                HStack {
                    Button("Refresh MIDI ports") { engine.refreshEndpoints() }
                    Spacer()
                    Button("Send test note") { engine.sendTestNote() }
                        .disabled(settings.outputUniqueID == 0)
                }
                Text(engine.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("MIDI All-Notes-Off Relay")
    }

    // Bindings that route through the published settings values.
    private var inputSelection: Binding<Int32> {
        Binding(get: { settings.inputUniqueID }, set: { settings.inputUniqueID = $0 })
    }
    private var outputSelection: Binding<Int32> {
        Binding(get: { settings.outputUniqueID }, set: { settings.outputUniqueID = $0 })
    }

    /// Human-friendly note name (C-1 .. G9), matching the common convention
    /// where MIDI note 60 = C4 (middle C).
    static func noteName(_ note: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = (note / 12) - 1
        return "\(names[note % 12])\(octave)"
    }
}

# MIDI All-Notes-Off Relay (macOS)

A small macOS app that listens on a MIDI input bus for a transport **Stop**
message and, when it sees one, sends a configurable note (Note On, held for a
configurable duration, then Note Off) on a configurable output bus.

Built for the workflow: **Reason DAW → press Stop → Reason emits MIDI Stop
(0xFC) → this app fires a note** you can route wherever you like.

## What it does

- Listens on a **selectable input bus**.
- Triggers on a **configurable** message:
  - **MIDI Stop** = System Real-Time `0xFC` (decimal 252) — the message Reason's
    transport Stop button sends. This is the default.
  - **All Notes Off** = CC 123 (fallback)
  - **All Sound Off** = CC 120 (fallback)
  - **Stop or All Notes Off** = 0xFC or CC 123
  - **Any** = 0xFC or CC 120 or CC 123
- MIDI Stop is **channel-less** (System Real-Time). The CC fallbacks react on
  **any MIDI channel** of the input bus.
- On trigger, sends on a **selectable output bus**:
  - configurable **channel** (1–16)
  - configurable **note** (0–127)
  - configurable **velocity** (1–127)
  - **Note On**, wait a configurable **note length** (default **500 ms**), **Note Off**
- Settings persist across launches (via `UserDefaults`).
- "Send test note" button to verify your output routing without Reason.

## Requirements

- macOS 13.0 or later
- Xcode 15 or later

## Build & run

1. Copy the `MidiAllNotesOffRelay` folder to your Mac.
2. Open `MidiAllNotesOffRelay.xcodeproj` in Xcode.
3. Select the `MidiAllNotesOffRelay` scheme and press **Run** (⌘R), or
   **Product → Archive** to produce a distributable `.app`.
4. To run from the Dock: in Xcode do **Product → Show Build Folder in Finder**,
   find `MidiAllNotesOffRelay.app`, and drag it to `/Applications` (or anywhere),
   then keep it in the Dock.

### Command-line build (optional)

From the project root on your Mac:

```bash
xcodebuild -project MidiAllNotesOffRelay.xcodeproj \
  -scheme MidiAllNotesOffRelay \
  -configuration Release build
```

The built app path is printed near the end of the log (under `Release/`).

## Setup for Reason

1. In Reason, enable an **External MIDI Instrument** / Control Surface output, or
   use a virtual MIDI bus (macOS **IAC Driver**, enabled in
   *Audio MIDI Setup → MIDI Studio → IAC Driver → "Device is online"*).
2. Route Reason's output to that bus, and select the **same bus** as the
   **Input bus** in this app.
3. Choose the **Trigger on** mode. The default is **MIDI Stop (0xFC)**, which is
   what Reason's transport Stop button sends. If your setup doesn't emit Stop on
   that bus, try **Any** to also catch CC 120 / CC 123.
4. Pick your **Output bus / channel / note** and you're set.

## Notes / possible extensions

- If you want per-channel triggering (only react on, say, channel 1), that's a
  small change in `MidiEngine.handleIncoming` — currently the channel nibble is
  intentionally ignored.
- Velocity, note length, and trigger mode are all live — changing them takes
  effect on the next trigger.
- The app uses the modern CoreMIDI `MIDIEventList` API (`MIDISendEventList`,
  `MIDIInputPortCreateWithProtocol`).

## Code signing

The project uses automatic signing with hardened runtime enabled. For personal
use, Xcode's "Sign to Run Locally" is sufficient. For distribution to other
Macs, set your Developer ID team in the target's Signing & Capabilities.

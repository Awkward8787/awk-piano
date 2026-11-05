# Awk Piano: piano, at your pace

A native, offline macOS piano-learning game for adults and children. Requires macOS 14 Sonoma or later. The app is a universal binary for Apple silicon and Intel Macs.

## Install

Open `Awk Piano-Mac.dmg`, then drag **Awk Piano** into **Applications**. Launch it from Applications. The ZIP is an alternative: unzip and move Awk Piano.app to Applications.

This locally built preview is ad-hoc signed. It is not signed with an Apple Developer ID or notarized by Apple, so macOS may block a downloaded copy. If macOS blocks it, try opening it once, then use System Settings > Privacy & Security > Open Anyway for Awk Piano. This option is subject to your Mac's security or organization policies. Developer ID signing and notarization are needed for a normal public release without this warning.

## Start playing

1. Select **Your first five notes**. Start in **Learn** mode at 75% speed.
2. Connect a USB MIDI keyboard. Awk Piano automatically listens to all available MIDI sources; click **Refresh MIDI devices** after connecting if needed.
3. Press **Play** or Space. Play the highlighted key when the falling note reaches the piano. Learn waits for each note or chord.
4. Without a piano, use the computer keyboard or click the on-screen keys. A S D F G H J K are white keys; W E T Y U are black keys. The full row A W S E D F T G Y H U J K O L spans C through the next octave's D. A begins at C4. Change Octave for another register.

Middle C is C4 (MIDI note 60). The first lesson uses C D E F G. Place your right thumb on C and your remaining fingers on the next four white keys. For the C major scale, a common ascending right-hand fingering is 1 2 3 1 2 3 4 5, with thumb crossing under after E. Awk Piano does not analyze fingering or hand posture.

## Add the songs you want

Choose **Add a MIDI song**, use File > Add MIDI Song (Command-O), drop `.mid` or `.midi` files into Awk Piano, or open a MIDI file with Awk Piano. Multi-file import is supported. Use MIDI piano arrangements you have permission to use. Popular songs are not bundled and Awk Piano does not connect to a streaming music catalog. MP3 and WAV recordings cannot be imported as lessons.

Supported: Standard MIDI File format 0 and 1, ticks-per-quarter timing, tempo changes, running status, track names, chords, sustain-pedal note durations. The drum channel is omitted. Limits: 20 MB per file and 200,000 completed notes. Format 2 sequences and SMPTE-timed files need conversion to format 0 or 1. Imported instruments use the built-in piano sound; MIDI program changes are not reproduced.

Choose a melody or piano **Track** when a file contains multiple instruments. Right hand selects notes at or above middle C; Left hand selects notes below middle C. This is a pitch-based convenience, not automatic hand detection. Use track selection for arrangements that separate hands into tracks. Imported MIDI must already contain a suitable arrangement; Awk Piano does not simplify it or infer finger numbers.

Imported songs are copied into Awk Piano's local library, so you can move the original MIDI afterward. Control-click an imported song to remove that library copy. Original files are preserved.

## Practice modes

- **Learn:** waits for correct note presses, including every note of a chord. Accuracy measures correct versus incorrect presses. Notes must be pressed again for repeated notes. Holding a key before its turn does not automatically count.
- **Perform:** time keeps moving. Play within about a quarter-second of each note's onset in song time. Missed notes and incorrect presses reduce accuracy. The selected notes are sounded by your playing, not automatically.
- **Listen:** Awk Piano plays the selected arrangement so you can hear the melody and watch the notes. No score is recorded.

Speed can be adjusted from 25% to 150%. The pitch stays the same. Loop a difficult section using the start and end sliders and **Go to loop**. Each loop starts a new attempt. Seeking clears the current attempt and excludes earlier notes from accuracy. Best completion accuracy is stored locally per song. Best scores combine hand/track selections and Learn/Perform attempts; they are encouragement, not a standardized assessment.

Mute Awk Piano if your keyboard already produces sound and you hear doubled notes. Awk Piano uses macOS's installed piano soundbank. Losing app focus pauses practice to prevent stuck computer keys. Imported MIDI pedal durations affect playback; a physical pedal is not currently graded or forwarded to the built-in instrument. MIDI input is supported; sending notes to an external MIDI instrument is not included.

## Privacy and storage

No account, subscription, network connection, analytics, microphone, or cloud upload is needed. Songs are stored as JSON in `~/Library/Application Support/Awk Piano/Songs`. Best scores are stored in the app's macOS UserDefaults. The app listens to all MIDI sources visible to CoreMIDI, including virtual inputs. It does not send MIDI to external devices.

## Build from source

Install Xcode and its command-line tools, then run:

```sh
./build.sh /path/to/Awk Piano.app
/path/to/Awk Piano.app/Contents/MacOS/Awk Piano --self-test
```

The build uses Swift, AppKit, SwiftUI, CoreMIDI, and AVFoundation. No third-party packages are downloaded. `build.sh` builds both arm64 and x86_64 executables and combines them into a universal app, then applies an ad-hoc signature.

`Sources/MIDIFile.swift` contains the MIDI parser and demos. `MIDIHardware.swift` handles audio and keyboard devices. `PracticeModel.swift` handles gameplay and persistence. `Views.swift` contains the native interface and shared theme tokens. `main.swift` starts the application and installs its menus. `Tests/SelfTests.swift` supplies the parser and MIDI-stream tests.

## Preview status

This is a functional first version, not an App Store release. See `Verification.md` for the checks actually run and remaining limits. No commercial song library, sheet-music notation, automatic fingering, microphone pitch detection, Bluetooth pairing flow, external MIDI output, or adaptive teaching curriculum is included.

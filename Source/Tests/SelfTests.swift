import Foundation

func runSelfTests() {
    var passed = 0
    func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { print("FAIL: \(name)"); exit(1) }; print("PASS: \(name)"); passed += 1
    }
    func be(_ n: Int, _ bytes: Int) -> [UInt8] { (0..<bytes).reversed().map { UInt8((n >> ($0*8)) & 255) } }
    func vlq(_ n: Int) -> [UInt8] { var v = n; var b = [UInt8(v & 127)]; v >>= 7; while v > 0 { b.insert(UInt8(v & 127) | 128, at: 0); v >>= 7 }; return b }
    func file(_ tracks: [[UInt8]], format: Int = 1, division: Int = 480) -> Data {
        var data = Array("MThd".utf8) + be(6,4) + be(format,2) + be(tracks.count,2) + be(division,2)
        for t in tracks { data += Array("MTrk".utf8) + be(t.count,4) + t }
        return Data(data)
    }
    func rejects(_ data: Data) -> Bool { do { _ = try MIDIFile.parse(data, title: "Invalid"); return false } catch { return true } }
    do {
        let song = try MIDIFile.parse(file([[0,144,60,100] + vlq(480) + [128,60,0,0,255,47,0]], format: 0), title: "One note")
        check(song.notes.count == 1 && abs(song.notes[0].duration-0.5) < 0.001, "Format 0 note timing")
        let tempo: [UInt8] = [0,255,81,3,7,161,32] + vlq(480) + [255,81,3,15,66,64,0,255,47,0]
        let melody: [UInt8] = [0,255,3,5] + Array("Piano".utf8) + [0,144,60,90] + vlq(960) + [128,60,0,0,255,47,0]
        let changed = try MIDIFile.parse(file([tempo,melody]), title: "Tempo")
        check(abs(changed.notes[0].duration-1.5) < 0.001 && changed.tracks[0].name == "Piano", "Format 1 global tempo changes and track names")
        let running: [UInt8] = [0,144,60,90,0,64,90] + vlq(480) + [60,0,0,64,0,0,255,47,0]
        let chord = try MIDIFile.parse(file([running]), title: "Chord")
        check(chord.notes.count == 2 && chord.notes.allSatisfy { abs($0.duration-0.5) < 0.001 }, "Running status, chords, velocity-zero note off")
        let sustain: [UInt8] = [0,144,60,90,0,176,64,127] + vlq(240) + [128,60,0] + vlq(240) + [176,64,0,0,255,47,0]
        let pedaled = try MIDIFile.parse(file([sustain]), title: "Sustain")
        check(abs(pedaled.notes[0].duration-0.5) < 0.001, "Sustain extends notes until pedal release")
        let drums: [UInt8] = [0,153,36,100,0,144,60,100] + vlq(480) + [137,36,0,0,128,60,0,0,255,47,0]
        let piano = try MIDIFile.parse(file([drums]), title: "Drums")
        check(piano.notes.count == 1 && piano.notes[0].pitch == 60, "Percussion channel excluded")
        check(rejects(Data([1,2,3])), "Invalid headers rejected")
        check(rejects(file([[0,144,60]])), "Truncated events rejected")
        check(rejects(file([running], format: 2)), "Format 2 rejected with explanation")
        check(rejects(file([running], division: 0xE728)), "SMPTE timing rejected with explanation")
        check(rejects(file([[0,255,47,0]])), "Empty songs rejected")
        check(rejects(file([[0,60,90,0,255,47,0]])), "Invalid running status rejected")
        let demos = demoSongs()
        check(demos.count == 4 && demos.allSatisfy { !$0.notes.isEmpty && $0.duration > 1 }, "All included lessons are playable")
        let restored = try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(changed))
        check(restored.notes.count == changed.notes.count && restored.tracks[0].name == "Piano", "Song library persistence round trip")
        let hardware = MIDIHardware(); var received: [(Int,Bool)] = []
        hardware.onNote = { pitch, _, down in received.append((pitch,down)) }
        hardware.consume([144,60]); hardware.consume([100,64,100,248,60,0]); hardware.consume([128,64,0])
        check(received.count == 4 && received[0].0 == 60 && received[0].1 && !received[2].1 && !received[3].1, "Live MIDI fragmented packets, running status, clock, note off")
        print("\(passed)/\(passed) checks passed")
    } catch { print("FAIL: unexpected error: \(error)"); exit(1) }
}

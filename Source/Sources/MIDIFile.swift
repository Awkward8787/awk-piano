import Foundation

struct PianoNote: Identifiable, Codable {
    var id: Int
    var pitch: Int
    var start: Double
    var duration: Double
    var velocity: Int
    var track: Int
    var channel: Int
}
struct SongTrack: Identifiable, Codable { var id: Int; var name: String; var count: Int }
struct Song: Identifiable, Codable {
    var id: String
    var title: String
    var subtitle: String
    var notes: [PianoNote]
    var tracks: [SongTrack]
    var bpm: Double
    var duration: Double { max(1, notes.map { $0.start + $0.duration }.max() ?? 1) }
}
enum MIDIError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
struct MIDIReader {
    var bytes: [UInt8]; var position = 0
    mutating func byte() throws -> UInt8 {
        guard position < bytes.count else { throw MIDIError.invalid("This MIDI file ends unexpectedly.") }
        defer { position += 1 }; return bytes[position]
    }
    mutating func take(_ n: Int) throws -> [UInt8] {
        guard n >= 0, n <= bytes.count - position else { throw MIDIError.invalid("This MIDI file contains an incomplete event.") }
        defer { position += n }; return Array(bytes[position..<position+n])
    }
    mutating func number(_ n: Int) throws -> Int { try take(n).reduce(0) { ($0 << 8) | Int($1) } }
    mutating func variable() throws -> Int {
        var value = 0
        for _ in 0..<4 { let b = try byte(); value = (value << 7) | Int(b & 127); if b < 128 { return value } }
        throw MIDIError.invalid("This MIDI file contains an invalid event length.")
    }
}
struct MIDIFile {
    struct Raw { var pitch: Int; var start: Int; var end: Int; var velocity: Int; var track: Int; var channel: Int }
    static func parse(_ data: Data, title: String) throws -> Song {
        guard data.count <= 20_000_000 else { throw MIDIError.invalid("Please choose a MIDI file smaller than 20 MB.") }
        var r = MIDIReader(bytes: Array(data))
        guard try r.take(4) == Array("MThd".utf8) else { throw MIDIError.invalid("Choose a Standard MIDI File (.mid or .midi), rather than an audio recording.") }
        let size = try r.number(4)
        guard size >= 6 else { throw MIDIError.invalid("The MIDI header is incomplete.") }
        let format = try r.number(2), trackCount = try r.number(2), division = try r.number(2)
        guard format <= 1 else { throw MIDIError.invalid("Format 2 MIDI files contain independent sequences. Export this song as format 0 or 1.") }
        guard division > 0, division & 0x8000 == 0 else { throw MIDIError.invalid("Export this MIDI with beats/ticks timing; SMPTE timing is not supported.") }
        guard trackCount > 0, trackCount <= 1024 else { throw MIDIError.invalid("The MIDI track count is invalid.") }
        _ = try r.take(size - 6)
        var tempos: [(Int, Int)] = [(0, 500000)]
        var raw: [Raw] = []; var names: [Int: String] = [:]
        for track in 0..<trackCount {
            guard try r.take(4) == Array("MTrk".utf8) else { throw MIDIError.invalid("A MIDI track header is missing.") }
            let length = try r.number(4)
            var t = MIDIReader(bytes: try r.take(length))
            var tick = 0, running: UInt8 = 0
            var active: [Int: [(Int, Int)]] = [:]
            var sustained: [Int: [(Int, Int, Int)]] = [:]
            var pedal: Set<Int> = []
            func append(_ pitch: Int, _ channel: Int, _ start: Int, _ velocity: Int, _ end: Int) {
                raw.append(Raw(pitch: pitch, start: start, end: max(start + 1, end), velocity: velocity, track: track, channel: channel))
            }
            while t.position < t.bytes.count {
                tick += try t.variable()
                let first = try t.byte()
                var status = first
                if first < 128 {
                    guard running >= 128 else { throw MIDIError.invalid("A MIDI running-status event has no status byte.") }
                    status = running; t.position -= 1
                }
                if status == 255 {
                    running = 0
                    let type = try t.byte(), count = try t.variable(), payload = try t.take(count)
                    if type == 81, payload.count == 3 {
                        let tempo = payload.reduce(0) { ($0 << 8) | Int($1) }
                        if tempo > 0 { tempos.append((tick, tempo)) }
                    }
                    if type == 3 { names[track] = String(bytes: payload, encoding: .utf8) ?? String(bytes: payload, encoding: .isoLatin1) }
                    if type == 47 { break }
                } else if status == 240 || status == 247 {
                    running = 0; let n = try t.variable(); _ = try t.take(n)
                } else {
                    guard status < 240 else { throw MIDIError.invalid("Unsupported system event in this MIDI file.") }
                    running = status
                    let kind = status & 240, channel = Int(status & 15)
                    let a = Int(try t.byte()), b = (kind == 192 || kind == 208) ? 0 : Int(try t.byte())
                    guard a < 128, b < 128 else { throw MIDIError.invalid("A MIDI note contains invalid data.") }
                    let key = channel * 128 + a
                    if kind == 144 && b > 0 { active[key, default: []].append((tick, b)) }
                    if kind == 128 || (kind == 144 && b == 0) {
                        if var queue = active[key], !queue.isEmpty {
                            let note = queue.removeFirst(); active[key] = queue
                            if pedal.contains(channel) { sustained[channel, default: []].append((a, note.0, note.1)) }
                            else { append(a, channel, note.0, note.1, tick) }
                        }
                    }
                    if kind == 176 && a == 64 {
                        if b >= 64 { pedal.insert(channel) }
                        else {
                            pedal.remove(channel)
                            for n in sustained[channel] ?? [] { append(n.0, channel, n.1, n.2, tick) }
                            sustained[channel] = []
                        }
                    }
                }
                guard raw.count < 200000 else { throw MIDIError.invalid("This song has too many notes. Export a shorter piano arrangement.") }
            }
            for (key, queue) in active { for n in queue { append(key % 128, key / 128, n.0, n.1, tick) } }
            for (channel, list) in sustained { for n in list { append(n.0, channel, n.1, n.2, tick) } }
        }
        // Stable ordering ensures an explicit tempo at tick zero replaces the default.
        let sorted = tempos.enumerated().sorted { $0.element.0 == $1.element.0 ? $0.offset < $1.offset : $0.element.0 < $1.element.0 }.map { $0.element }
        var segments: [(tick: Int, seconds: Double, tempo: Int)] = []
        var previousTick = 0, previousTempo = 500000; var elapsed = 0.0
        for (tick, tempo) in sorted {
            elapsed += Double(tick - previousTick) / Double(division) * Double(previousTempo) / 1_000_000
            segments.append((tick, elapsed, tempo)); previousTick = tick; previousTempo = tempo
        }
        func seconds(_ tick: Int) -> Double {
            var low = 0, high = segments.count
            while low < high { let middle = (low + high) / 2; if segments[middle].tick <= tick { low = middle + 1 } else { high = middle } }
            let s = segments[max(0, low-1)]
            return s.seconds + Double(tick - s.tick) / Double(division) * Double(s.tempo) / 1_000_000
        }
        let notes = raw.filter { $0.channel != 9 }.sorted { $0.start == $1.start ? $0.pitch < $1.pitch : $0.start < $1.start }.enumerated().map { i, n in
            PianoNote(id: i, pitch: n.pitch, start: seconds(n.start), duration: max(0.05, seconds(n.end) - seconds(n.start)), velocity: n.velocity, track: n.track, channel: n.channel)
        }
        guard !notes.isEmpty else { throw MIDIError.invalid("No playable notes were found. Drum-channel notes are excluded.") }
        let tracks = Set(notes.map(\.track)).sorted().map { id in SongTrack(id: id, name: names[id].flatMap { $0.isEmpty ? nil : $0 } ?? "Track \(id+1)", count: notes.filter { $0.track == id }.count) }
        return Song(id: UUID().uuidString, title: title, subtitle: "Your MIDI arrangement", notes: notes, tracks: tracks, bpm: 60_000_000 / Double(segments.last(where: { $0.tick == 0 })?.tempo ?? 500000))
    }
}
func noteName(_ pitch: Int) -> String { ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"][max(0,pitch) % 12] + String(pitch / 12 - 1) }
func isBlack(_ pitch: Int) -> Bool { [1,3,6,8,10].contains(pitch % 12) }
func demoSongs() -> [Song] {
    func make(_ id: String, _ title: String, _ subtitle: String, _ melody: [Int], _ beat: Double) -> Song {
        let notes = melody.enumerated().compactMap { i, p -> PianoNote? in p == 0 ? nil : PianoNote(id: i, pitch: p, start: Double(i) * beat + 1, duration: beat * 0.85, velocity: 88, track: 0, channel: 0) }
        return Song(id: id, title: title, subtitle: subtitle, notes: notes, tracks: [SongTrack(id: 0, name: "Melody", count: notes.count)], bpm: 60 / beat)
    }
    return [make("first", "Your first five notes", "Lesson 1 · Find middle C", [60,62,64,65,67,0,67,65,64,62,60,0,60,64,67,64,60], 0.8),
            make("ode", "Ode to Joy", "Beethoven · Beginner melody", [64,64,65,67,67,65,64,62,60,60,62,64,64,62,62,0,64,64,65,67,67,65,64,62,60,60,62,64,62,60,60], 0.55),
            make("twinkle", "Twinkle, Twinkle", "Traditional · Beginner melody", [60,60,67,67,69,69,67,0,65,65,64,64,62,62,60,0,67,67,65,65,64,64,62,0,67,67,65,65,64,64,62,0,60,60,67,67,69,69,67,0,65,65,64,64,62,62,60], 0.55),
            make("scale", "The C major climb", "Lesson 2 · Build finger confidence", [60,62,64,65,67,69,71,72,0,72,71,69,67,65,64,62,60], 0.65)]
}

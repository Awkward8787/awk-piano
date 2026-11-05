import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class PracticeModel: ObservableObject {
    @Published var songs = demoSongs()
    @Published var selectedID = "first"
    @Published var selectedTrack = -1 { didSet { if oldValue != selectedTrack { reset() } } }
    @Published var hand = "Both hands" { didSet { if oldValue != hand { reset() } } }
    @Published var mode = "Learn" { didSet { if oldValue != mode { reset() } } }
    @Published var audience = "Everyone"
    @Published var playing = false
    @Published var time = 0.0
    @Published var speed = 0.75
    @Published var volume = true { didSet { if !volume { audio.silence() } } }
    @Published var held: Set<Int> = []
    @Published var hit: Set<Int> = []
    @Published var wrong = 0
    @Published var streak = 0
    @Published var bestStreak = 0
    @Published var devices: [String] = []
    @Published var feedback = "Start with middle C. Take your time."
    @Published var error: String?
    @Published var loading = false
    @Published var loop = false
    @Published var loopStart = 0.0
    @Published var loopEnd = 1.0
    @Published var completed = false
    @Published var octave = 4
    @Published var bestScores: [String: Int] = [:]
    @Published var showHelp = false
    @Published var showLessons = false
    let audio = PianoAudio()
    let midi = MIDIHardware()
    private var timer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var sounding: [Int: Double] = [:]
    private var played: Set<Int> = []
    private var missed: Set<Int> = []
    private var skipped: Set<Int> = []
    var practiceEnd: Double { max(1, notes.map { $0.start + $0.duration }.max() ?? 1) }
    private var keyMonitor: Any?
    private var keyUpMonitor: Any?
    private var computerHeld: [UInt16: Int] = [:]
    private var virtualHeld: Set<Int> = []
    private var midiHeld: Set<Int> = []
    private let fileManager = FileManager.default
    private var library: URL { if let root = ProcessInfo.processInfo.environment["EBEL_DATA_ROOT"] { return URL(fileURLWithPath: root).appendingPathComponent("Songs", isDirectory: true) }; return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Awk Piano/Songs", isDirectory: true) }
    var song: Song { songs.first { $0.id == selectedID } ?? songs[0] }
    var notes: [PianoNote] {
        song.notes.filter { (selectedTrack == -1 || $0.track == selectedTrack) && (hand == "Both hands" || (hand == "Right hand" ? $0.pitch >= 60 : $0.pitch < 60)) }
    }
    var upcoming: [PianoNote] { notes.filter { $0.start + $0.duration >= time - 0.3 && $0.start < time + 5 } }
    var expected: [PianoNote] {
        guard let first = notes.first(where: { !hit.contains($0.id) && $0.start >= time - 0.24 }) else { return [] }
        return notes.filter { !hit.contains($0.id) && abs($0.start-first.start) < 0.035 }
    }
    var accuracy: Int { let attempts = hit.count + wrong + missed.count; return attempts == 0 ? 0 : Int((Double(hit.count) / Double(attempts) * 100).rounded()) }
    var keyRange: ClosedRange<Int> {
        let pitches = notes.map(\.pitch)
        let low = min(48, pitches.min() ?? 48), high = max(84, pitches.max() ?? 84)
        let bottom = max(0, (low / 12) * 12)
        return bottom...min(127, ((high / 12) + 1) * 12)
    }
    init() {
        bestScores = UserDefaults.standard.dictionary(forKey: "Awk Piano.bestScores.v1") as? [String:Int] ?? [:]
        do {
            try fileManager.createDirectory(at: library, withIntermediateDirectories: true)
            for url in try fileManager.contentsOfDirectory(at: library, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "json" }) {
                if let saved = try? JSONDecoder().decode(Song.self, from: Data(contentsOf: url)), !saved.notes.isEmpty { songs.append(saved) }
            }
        } catch { self.error = "Your song library could not be opened: \(error.localizedDescription)" }
        midi.onNote = { [weak self] pitch, velocity, down in self?.input(pitch, velocity: velocity, down: down, external: true) }
        midi.onDevices = { [weak self] names, error in self?.devices = names; if let error { self?.error = error } }
        midi.refresh()
        if !audio.available { self.error = "Piano audio could not start: \(audio.failure)" }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/60, repeats: true) { [weak self] _ in self?.tick() }
        installKeyboard()
    }
    func choose(_ id: String) { pause(); selectedID = id; selectedTrack = -1; hand = "Both hands"; loop = false; reset() }
    func reset() {
        pause(); time = loop ? loopStart : 0; hit = []; missed = []; skipped = []; wrong = 0; streak = 0; bestStreak = 0; completed = false
        feedback = notes.isEmpty ? "No notes in this selection. Try another hand or track." : "Ready when you are. Press Play."
        played = []; sounding = [:]; loopEnd = min(max(loopEnd, loopStart+0.5), song.duration)
    }
    func toggle() {
        if playing { pause(); return }
        guard !notes.isEmpty else { feedback = "Choose a hand or track with notes."; return }
        if completed || time >= song.duration { reset() }
        lastTick = ProcessInfo.processInfo.systemUptime; playing = true
        feedback = mode == "Learn" ? "Play the highlighted notes. The song waits for you." : mode == "Listen" ? "Listen, watch, then try Learn mode." : "Follow the notes as they reach the keys."
    }
    func pause() { playing = false; audio.silence(); sounding = [:] }
    func seek(_ newTime: Double) {
        let wasPlaying = playing; pause(); time = min(song.duration, max(0, newTime)); completed = false
        hit = []; missed = []; skipped = Set(notes.filter { $0.start < time-0.24 }.map(\.id)); wrong = 0; streak = 0
        played = Set(notes.filter { $0.start < time }.map(\.id)); lastTick = ProcessInfo.processInfo.systemUptime; playing = wasPlaying
    }
    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let delta = min(0.1, now - lastTick); lastTick = now
        guard playing else { return }
        var next = time + delta * speed
        if mode == "Learn", let waiting = notes.first(where: { !hit.contains($0.id) && $0.start >= time - 0.24 }), next >= waiting.start {
            next = waiting.start
            feedback = "Your turn: " + notes.filter { !hit.contains($0.id) && abs($0.start-waiting.start) < 0.035 }.map { noteName($0.pitch) }.joined(separator: " + ")
        }
        time = next
        if mode != "Learn" {
            for n in notes where n.start <= time && !played.contains(n.id) {
                played.insert(n.id)
                if volume && mode == "Listen" { audio.on(n.pitch, velocity: n.velocity); sounding[n.pitch] = max(sounding[n.pitch] ?? 0, n.start + n.duration) }
            }
            if mode == "Perform" {
                for n in notes where n.start < time - 0.25 && !hit.contains(n.id) && !missed.contains(n.id) && !skipped.contains(n.id) { missed.insert(n.id); streak = 0 }
            }
        }
        for (pitch, end) in sounding where time >= end { if !held.contains(pitch) { audio.off(pitch) }; sounding.removeValue(forKey: pitch) }
        if loop && time >= loopEnd && loopEnd > loopStart { seek(loopStart); return }
        if time >= practiceEnd + 0.3 {
            pause(); time = practiceEnd; completed = true
            feedback = mode == "Listen" ? "Now make it yours. Switch to Learn and play along." : "Practice complete. \(hit.count) notes played, best streak \(bestStreak)."
            if mode != "Listen" { bestScores[song.id] = max(bestScores[song.id] ?? 0, accuracy); UserDefaults.standard.set(bestScores, forKey: "Awk Piano.bestScores.v1") }
        }
    }
    func input(_ pitch: Int, velocity: Int = 90, down: Bool, external: Bool = false) {
        if external { if down { midiHeld.insert(pitch) } else { midiHeld.remove(pitch) } }
        else { if down { virtualHeld.insert(pitch) } else { virtualHeld.remove(pitch) } }
        held = midiHeld.union(virtualHeld)
        if !down { if !held.contains(pitch), sounding[pitch] == nil { audio.off(pitch) }; return }
        if volume { audio.on(pitch, velocity: velocity) }
        guard playing, mode != "Listen" else { return }
        if let n = notes.first(where: { $0.pitch == pitch && !hit.contains($0.id) && abs($0.start-time) <= 0.24 }) {
            hit.insert(n.id); streak += 1; bestStreak = max(bestStreak, streak)
            feedback = audience == "Kids" ? "You got it! \(streak) in a row." : "Nice work. \(noteName(pitch)) played."
        } else { wrong += 1; streak = 0; feedback = "Try " + (expected.first.map { noteName($0.pitch) } ?? "the next highlighted note") + ". You can do this." }
    }
    func importFiles() {
        pause()
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "mid")!, UTType(filenameExtension: "midi")!]
        panel.allowsMultipleSelection = true; panel.message = "Add piano arrangements as Standard MIDI Files (.mid or .midi)."
        if panel.runModal() == .OK { importURLs(panel.urls) }
    }
    func importURLs(_ urls: [URL]) {
        guard !loading else { return }; loading = true; pause()
        DispatchQueue.global(qos: .userInitiated).async {
            var imported: [Song] = []; var failures: [String] = []
            for url in urls {
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let values = try url.resourceValues(forKeys: [.fileSizeKey])
                    guard (values.fileSize ?? 0) <= 20_000_000 else { throw MIDIError.invalid("Please choose a MIDI file smaller than 20 MB.") }
                    let song = try MIDIFile.parse(Data(contentsOf: url), title: url.deletingPathExtension().lastPathComponent)
                    let encoded = try JSONEncoder().encode(song)
                    try encoded.write(to: self.library.appendingPathComponent(song.id + ".json"), options: .atomic)
                    imported.append(song)
                } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            let result = imported, problems = failures
            DispatchQueue.main.async {
                self.songs.append(contentsOf: result); self.loading = false
                if let first = result.first { self.choose(first.id); self.feedback = "Song added. Choose a track, then press Play." }
                if !problems.isEmpty { self.error = problems.joined(separator: "\n\n") }
            }
        }
    }
    func removeSong() {
        guard !demoSongs().contains(where: { $0.id == selectedID }) else { return }
        let id = selectedID
        do { try fileManager.removeItem(at: library.appendingPathComponent(id + ".json")); choose("first"); songs.removeAll { $0.id == id } }
        catch { self.error = "The song could not be removed: \(error.localizedDescription)" }
    }
    func installKeyboard() {
        let mapping: [String:Int] = ["a":0,"w":1,"s":2,"e":3,"d":4,"f":5,"t":6,"g":7,"y":8,"h":9,"u":10,"j":11,"k":12,"o":13,"l":14]
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.modifierFlags.intersection([.command,.control,.option]).isEmpty,
                  !(NSApp.keyWindow?.firstResponder is NSTextView), !self.showHelp else { return event }
            if event.keyCode == 49 { if !event.isARepeat { self.toggle() }; return nil }
            if let offset = mapping[event.charactersIgnoringModifiers?.lowercased() ?? ""] {
                if !event.isARepeat { let p = (self.octave+1)*12+offset; self.computerHeld[event.keyCode] = p; self.input(p, down: true) }; return nil
            }
            return event
        }
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self, let p = self.computerHeld.removeValue(forKey: event.keyCode) else { return event }
            self.input(p, down: false); return nil
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }; self.pause(); self.computerHeld = [:]; self.virtualHeld = []; self.midiHeld = []; self.held = []
        }
    }
}

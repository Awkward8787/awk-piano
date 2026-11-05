import SwiftUI
import UniformTypeIdentifiers

enum Theme {
    static let background = Color(red: 0.055, green: 0.078, blue: 0.09)
    static let panel = Color(red: 0.085, green: 0.113, blue: 0.125)
    static let raised = Color(red: 0.12, green: 0.153, blue: 0.165)
    static let accent = Color(red: 0.55, green: 0.22, blue: 0.86)
    static let gold = Color(red: 0.93, green: 0.68, blue: 0.18)
    static let text = Color(red: 0.94, green: 0.96, blue: 0.94)
    static let muted = Color(red: 0.64, green: 0.71, blue: 0.72)
    static let ivory = Color(red: 0.95, green: 0.94, blue: 0.88)
    static let line = Color.white.opacity(0.08)
    static let radius: CGFloat = 16
    static let gap: CGFloat = 16
}
struct KeyGeometry {
    let range: ClosedRange<Int>
    let width: CGFloat
    var whites: [Int] { range.filter { !isBlack($0) } }
    var unit: CGFloat { width / CGFloat(whites.count) }
    func center(_ pitch: Int) -> CGFloat {
        let count = range.filter { $0 < pitch && !isBlack($0) }.count
        return (CGFloat(count) + (isBlack(pitch) ? 0 : 0.5)) * unit
    }
}
struct AwkPianoView: View {
    @ObservedObject var model: PracticeModel
    @State private var isDropping = false
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 248)
            VStack(alignment: .leading, spacing: Theme.gap) {
                header
                settings
                practiceStage
                transport
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background).foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .frame(minWidth: 1040, minHeight: 760)
        .tint(Theme.accent)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropping) { providers in
            let group = DispatchGroup()
            let lock = NSLock()
            var urls: [URL] = []
            for provider in providers {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { lock.lock(); urls.append(url); lock.unlock() }
                    group.leave()
                }
            }
            group.notify(queue: .main) { model.importURLs(urls) }
            return !providers.isEmpty
        }
        .overlay { if isDropping { RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.accent, lineWidth: 3).padding(8).allowsHitTesting(false) } }
        .alert("Something needs attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        .sheet(isPresented: $model.showHelp) { help }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "pianokeys").font(.system(size: 25)).foregroundStyle(Theme.accent)
                Text("Awk Piano").font(.system(size: 34, weight: .semibold, design: .rounded)).tracking(-1)
            }.padding(.bottom, 4)
            Text("A little practice. A lot of possibility.").font(.system(size: 11)).foregroundStyle(Theme.muted)
            Button(action: model.importFiles) {
                HStack { Image(systemName: "plus"); Text(model.loading ? "Adding song…" : "Add a MIDI song"); Spacer() }.padding(12)
            }.buttonStyle(.plain).background(Theme.gold.opacity(0.15), in: RoundedRectangle(cornerRadius: 9)).foregroundStyle(Theme.gold).padding(.top, 28).disabled(model.loading)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    label("START HERE").padding(.top, 26)
                    ForEach(model.songs.filter { ["first","scale"].contains($0.id) }) { row($0) }
                    label("SONG LIBRARY").padding(.top, 20)
                    ForEach(model.songs.filter { !["first","scale"].contains($0.id) }) { row($0) }
                    if model.songs.count == 4 {
                        Text("Your favorite songs belong here. Drop in a MIDI piano arrangement to get started.")
                            .font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(4).padding(.top, 10)
                    }
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 10) {
                HStack { Image(systemName: model.devices.isEmpty ? "keyboard" : "cable.connector"); Text(model.devices.isEmpty ? "Computer keyboard ready" : "MIDI connected").fontWeight(.medium) }.font(.system(size: 12)).foregroundStyle(Theme.accent)
                Text(model.devices.isEmpty ? "Connect a USB MIDI piano, or play with A S D F G H J K." : model.devices.joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(3)
                Button("Refresh MIDI devices", action: model.midi.refresh).font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Theme.muted)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Theme.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            Button { model.showHelp = true } label: { Label("How to play", systemImage: "questionmark.circle").font(.system(size: 12)) }.buttonStyle(.plain).foregroundStyle(Theme.muted).padding(.top, 18)
        }.padding(20).background(Theme.panel)
    }
    func label(_ title: String) -> some View { Text(title).font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(Theme.muted).padding(.bottom, 6) }
    func row(_ song: Song) -> some View {
        Button { model.choose(song.id) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: song.id == model.selectedID ? "waveform" : "music.note").font(.system(size: 14)).frame(width: 18).padding(.top, 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title).font(.system(size: 13, weight: .medium)).multilineTextAlignment(.leading)
                    Text(song.subtitle).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(2)
                    if let best = model.bestScores[song.id] { Text("Best accuracy: \(best)%").font(.system(size: 10)).foregroundStyle(Theme.accent) }
                }
                Spacer(minLength: 0)
            }.padding(11).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).background(song.id == model.selectedID ? Theme.raised : .clear, in: RoundedRectangle(cornerRadius: 10))
        .foregroundStyle(song.id == model.selectedID ? Theme.accent : Theme.text)
        .accessibilityAddTraits(song.id == model.selectedID ? .isSelected : [])
        .contextMenu { if !demoSongs().contains(where: { $0.id == song.id }) { Button("Remove from library", role: .destructive) { model.choose(song.id); model.removeSong() } } }
    }
    var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                label(model.audience == "Kids" ? "LET’S MAKE SOME MUSIC" : "YOUR DAILY MOMENT OF MUSIC")
                Text(model.song.title).font(.system(size: 34, weight: .semibold, design: .rounded)).tracking(-0.7).lineLimit(1).minimumScaleFactor(0.7)
                Text(model.song.subtitle + "   ·   \(Int(model.song.bpm.rounded())) BPM   ·   \(model.notes.count) notes").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 10)
            VStack(alignment: .trailing, spacing: 10) {
                Picker("Learner", selection: $model.audience) { Text("Everyone").tag("Everyone"); Text("Kids").tag("Kids") }.labelsHidden().frame(width: 125)
                Text("Learn at your own pace").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }
    }
    var settings: some View {
        HStack(spacing: 16) {
            Picker("Mode", selection: $model.mode) { Text("Learn").tag("Learn"); Text("Perform").tag("Perform"); Text("Hear it").tag("Listen") }.pickerStyle(.segmented).frame(width: 245).help("Learn waits for correct notes. Perform keeps time. Hear it plays the song.")
            Spacer(minLength: 0)
            Picker("Track", selection: $model.selectedTrack) { Text("All tracks").tag(-1); ForEach(model.song.tracks) { Text($0.name).tag($0.id) } }.labelsHidden().frame(maxWidth: 160)
            Picker("Hand", selection: $model.hand) { ForEach(["Both hands", "Right hand", "Left hand"], id: \.self) { Text($0) } }.labelsHidden().frame(width: 130).help("Hand split uses middle C. Choose a track for arrangements with separate hand tracks.")
        }.padding(.vertical, 5)
    }
    var practiceStage: some View {
        VStack(spacing: 0) {
            HStack {
                Label(model.mode == "Learn" ? "THE SONG WAITS FOR YOU" : model.mode == "Listen" ? "HEAR IT FIRST" : "PLAY IN TIME", systemImage: model.mode == "Learn" ? "hand.tap" : "waveform.path")
                    .font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(Theme.muted)
                Spacer()
                if model.mode != "Listen" {
                    Text("\(model.hit.count) played").font(.system(size: 12, weight: .medium))
                    Text("·").foregroundStyle(Theme.muted)
                    Text("\(model.streak) streak").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
                    if model.hit.count + model.wrong > 0 { Text("·  \(model.accuracy)%").font(.system(size: 12)).foregroundStyle(Theme.muted) }
                }
            }.padding(18)
            GeometryReader { geometry in
                let keys = KeyGeometry(range: model.keyRange, width: geometry.size.width)
                Canvas { context, size in
                    for p in keys.whites {
                        let x = keys.center(p) - keys.unit / 2
                        if p % 12 == 0 { context.fill(Path(CGRect(x: x, y: 0, width: keys.unit, height: size.height)), with: .color(.white.opacity(0.018))) }
                        var path = Path(); path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(path, with: .color(Theme.line), lineWidth: 0.5)
                    }
                    let scale = max(35, (size.height - 30) / 4.5)
                    for second in 0...5 {
                        let phase = model.time.truncatingRemainder(dividingBy: 1)
                        let y = size.height - (Double(second) - phase) * scale
                        if y > 0 && y < size.height {
                            var line = Path(); line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y)); context.stroke(line, with: .color(Theme.line), lineWidth: 0.5)
                        }
                    }
                    for n in model.upcoming {
                        let w = keys.unit * (isBlack(n.pitch) ? 0.58 : 0.88)
                        let y = size.height - (n.start - model.time) * scale
                        let h = max(16, n.duration * scale)
                        let rect = CGRect(x: keys.center(n.pitch) - w/2, y: y-h, width: w, height: h)
                        let done = model.hit.contains(n.id)
                        let color = done ? Theme.accent.opacity(0.25) : Theme.accent.opacity(isBlack(n.pitch) ? 0.65 : 0.92)
                        context.fill(Path(roundedRect: rect, cornerRadius: min(5,w/3)), with: .color(color))
                        if w > 17 && h > 24 {
                            context.draw(Text(noteName(n.pitch)).font(.system(size: min(10,w*0.32), weight: .semibold)).foregroundStyle(Theme.background), at: CGPoint(x: rect.midX, y: rect.maxY - 12))
                        }
                    }
                    context.fill(Path(CGRect(x: 0, y: size.height-2, width: size.width, height: 2)), with: .color(Theme.accent.opacity(0.8)))
                }.clipped()
                .accessibilityLabel("Falling piano notes. Next notes: " + model.expected.map { noteName($0.pitch) }.joined(separator: ", "))
                if model.notes.isEmpty {
                    VStack(spacing: 12) { Image(systemName: "music.note").font(.largeTitle); Text("No notes in this selection").font(.title3); Text("Choose another track or both hands.").foregroundStyle(Theme.muted) }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            keyboard.frame(height: 126)
            HStack(spacing: 10) {
                Image(systemName: model.completed ? "checkmark.circle.fill" : "sparkle").foregroundStyle(Theme.accent)
                Text(model.feedback).font(.system(size: 12, weight: .medium)).lineLimit(2)
                Spacer(minLength: 0)
                if model.completed { Button("Play again", action: model.reset).buttonStyle(.bordered).controlSize(.small) }
            }.padding(.horizontal, 18).frame(height: 52).background(Theme.raised.opacity(0.6))
        }.background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.radius)).clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.line))
        .frame(maxHeight: .infinity)
    }
    var keyboard: some View {
        GeometryReader { g in
            let keys = KeyGeometry(range: model.keyRange, width: g.size.width)
            ZStack(alignment: .topLeading) {
                ForEach(keys.whites, id: \.self) { pitch in pianoKey(pitch, width: keys.unit-1, height: 124).offset(x: keys.center(pitch)-keys.unit/2) }
                ForEach(model.keyRange.filter { isBlack($0) }, id: \.self) { pitch in pianoKey(pitch, width: keys.unit*0.6, height: 78).offset(x: keys.center(pitch)-keys.unit*0.3) }
            }
        }
    }
    func pianoKey(_ pitch: Int, width: CGFloat, height: CGFloat) -> some View {
        let black = isBlack(pitch)
        let expected = model.playing && model.mode == "Learn" && model.expected.contains { $0.pitch == pitch }
        let active = model.held.contains(pitch)
        return Button {
            model.input(pitch, down: true)
            DispatchQueue.main.asyncAfter(deadline: .now()+0.22) { model.input(pitch, down: false) }
        } label: {
            VStack {
                if expected { Image(systemName: "arrow.down").font(.system(size: 11, weight: .bold)).padding(.top, black ? 8 : 84) }
                Spacer(minLength: 0)
                if !black { Text(noteName(pitch)).font(.system(size: max(7,min(10,width*0.4)), weight: pitch == 60 ? .bold : .medium)).padding(.bottom, 10) }
            }.frame(width: max(1,width), height: height)
                .foregroundStyle(active || expected ? Theme.background : black ? Theme.ivory : Theme.background.opacity(0.7))
                .background(active ? Theme.accent : expected ? Theme.accent.opacity(0.7) : black ? Theme.background : Theme.ivory, in: UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Play " + noteName(pitch)).help(noteName(pitch))
    }
    var transport: some View {
        VStack(spacing: 15) {
            HStack(spacing: 12) {
                Text(clock(model.time)).monospacedDigit().frame(width: 38, alignment: .leading)
                Slider(value: Binding(get: { model.time }, set: { model.seek($0) }), in: 0...model.song.duration).accessibilityLabel("Song position")
                Text(clock(model.song.duration)).monospacedDigit().foregroundStyle(Theme.muted)
            }.font(.system(size: 11))
            HStack(spacing: 14) {
                Button(action: model.reset) { Image(systemName: "backward.end.fill").frame(width: 24, height: 30) }.buttonStyle(.plain).help("Restart song")
                Button(action: model.toggle) {
                    Label(model.playing ? "Pause" : "Play", systemImage: model.playing ? "pause.fill" : "play.fill").font(.system(size: 13, weight: .semibold)).frame(width: 88, height: 40)
                }.buttonStyle(.plain).foregroundStyle(Theme.background).background(Theme.accent, in: RoundedRectangle(cornerRadius: 10)).disabled(model.notes.isEmpty || model.loading).help("Play or pause (Space)")
                HStack(spacing: 8) { Image(systemName: "speedometer").foregroundStyle(Theme.muted); Slider(value: $model.speed, in: 0.25...1.5, step: 0.05).frame(width: 100).accessibilityLabel("Practice speed"); Text("\(Int((model.speed*100).rounded()))%").monospacedDigit().frame(width: 36) }.font(.system(size: 12))
                Spacer(minLength: 0)
                Button { model.volume.toggle() } label: { Image(systemName: model.volume ? "speaker.wave.2" : "speaker.slash").frame(width: 24, height: 30) }.buttonStyle(.plain).help(model.volume ? "Mute piano" : "Unmute piano").accessibilityLabel(model.volume ? "Mute piano" : "Unmute piano")
                Toggle("Loop", isOn: $model.loop).toggleStyle(.button).controlSize(.small).onChange(of: model.loop) { _, enabled in if enabled { model.loopStart = 0; model.loopEnd = model.song.duration } }
                Stepper("Octave \(model.octave)", value: $model.octave, in: 1...7).font(.system(size: 11)).fixedSize().help("Change computer keyboard octave. A plays C of this octave.")
            }
            if model.loop {
                HStack {
                    Text("Loop from \(clock(model.loopStart))").frame(width: 110, alignment: .leading)
                    Slider(value: $model.loopStart, in: 0...max(0.01, model.loopEnd-0.5)).accessibilityLabel("Loop start")
                    Text("to \(clock(model.loopEnd))")
                    Slider(value: $model.loopEnd, in: min(model.song.duration, model.loopStart+0.5)...model.song.duration).accessibilityLabel("Loop end")
                    Button("Go to loop") { model.seek(model.loopStart) }
                }.font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }
    }
    func clock(_ t: Double) -> String { String(format: "%d:%02d", Int(max(0,t))/60, Int(max(0,t))%60) }
    var help: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Make yourself at home.").font(.system(size: 30, weight: .semibold, design: .rounded))
            helpItem("1. Start with five notes", "Choose Your first five notes. Put your right thumb on middle C (C4), then use your other fingers for D, E, F and G. A keyboard with 61 or 88 keys gives you room for most songs.")
            helpItem("2. Play your way", "Learn pauses at every note or chord until you play it. Perform keeps the song moving and measures your accuracy. Listen demonstrates the selected notes. Lower the speed whenever you need to.")
            helpItem("3. Connect a piano", "Connect a class-compliant USB MIDI keyboard to your Mac, then refresh MIDI devices. Awk Piano listens to all connected MIDI sources. If you hear doubled notes, turn off local sound on your piano or mute Awk Piano.")
            helpItem("4. Bring your favorite music", "Click Add a MIDI song or drop a .mid or .midi file into the window. Choose a piano or melody track if a file has multiple instruments. Songs stay in your local library. Awk Piano imports MIDI arrangements, not MP3s or streaming songs.")
            helpItem("No piano connected?", "Use A W S E D F T G Y H U J K O L for C through D of the next octave, including black keys. A starts at C4 by default. Space plays or pauses. You can also click the on-screen keys.")
            helpItem("Practice a little section", "Turn on Loop, set the start and end, and click Go to loop. For hand practice, Right hand selects notes at or above C4 and Left hand selects notes below C4. Use tracks for more precise hand separation.")
            Text("Included melodies are public-domain compositions. Add MIDI arrangements you have permission to use. Awk Piano does not include a commercial-song catalog, sheet-music notation, or automatic fingering.").font(.system(size: 11)).foregroundStyle(Theme.muted)
            HStack { Spacer(); Button("Let’s play") { model.showHelp = false }.keyboardShortcut(.defaultAction) }
        }.padding(32).frame(width: 620).background(Theme.panel).foregroundStyle(Theme.text)
    }
    func helpItem(_ title: String, _ body: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent); Text(body).font(.system(size: 12)).lineSpacing(3).foregroundStyle(Theme.muted) } }
}

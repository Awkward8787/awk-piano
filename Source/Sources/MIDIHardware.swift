import Foundation
import CoreMIDI
import AVFoundation

final class PianoAudio {
    private let engine = AVAudioEngine()
    private var sampler: AVAudioUnitSampler?
    var available = false
    var failure = ""
    init() {
        if ProcessInfo.processInfo.environment["EBEL_DISABLE_AUDIO"] == "1" { failure = "Audio disabled for verification."; return }
        var description = AudioComponentDescription(componentType: kAudioUnitType_MusicDevice, componentSubType: kAudioUnitSubType_Sampler, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        guard AudioComponentFindNext(nil, &description) != nil else { failure = "The macOS sampler audio component is unavailable."; return }
        let sampler = AVAudioUnitSampler()
        self.sampler = sampler
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
        do {
            try sampler.loadSoundBankInstrument(at: URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls"), program: 0, bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: 0)
            try engine.start(); available = true
        } catch { failure = error.localizedDescription }
    }
    func on(_ pitch: Int, velocity: Int = 90) { guard available else { return }; sampler?.startNote(UInt8(clamping: pitch), withVelocity: UInt8(clamping: velocity), onChannel: 0) }
    func off(_ pitch: Int) { sampler?.stopNote(UInt8(clamping: pitch), onChannel: 0) }
    func silence() { for pitch in 0...127 { off(pitch) } }
}

final class MIDIHardware {
    var onNote: ((Int, Int, Bool) -> Void)?
    var onDevices: (([String], String?) -> Void)?
    private var client: MIDIClientRef = 0
    private var port: MIDIPortRef = 0
    private var sources: [MIDIEndpointRef] = []
    private var running: UInt8 = 0
    private var pending: [UInt8] = []
    private var sysex = false
    init() {
        let status = MIDIClientCreateWithBlock("Awk Piano" as CFString, &client) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        guard status == noErr else { return }
        MIDIInputPortCreateWithBlock(client, "Awk Piano piano input" as CFString, &port) { [weak self] list, _ in
            var bytes: [UInt8] = []
            var pointer = UnsafeRawPointer(list).advanced(by: MemoryLayout<MIDIPacketList>.offset(of: \.packet)!).assumingMemoryBound(to: MIDIPacket.self)
            for index in 0..<list.pointee.numPackets {
                let raw = UnsafeRawPointer(pointer).advanced(by: MemoryLayout<MIDIPacket>.offset(of: \.data)!).assumingMemoryBound(to: UInt8.self)
                bytes.append(contentsOf: UnsafeBufferPointer(start: raw, count: Int(pointer.pointee.length)))
                if index + 1 < list.pointee.numPackets { pointer = UnsafePointer(MIDIPacketNext(pointer)) }
            }
            let received = bytes
            DispatchQueue.main.async { self?.consume(received) }
        }
    }
    func refresh() {
        for source in sources { MIDIPortDisconnectSource(port, source) }
        sources = []; running = 0; pending = []; sysex = false
        var names: [String] = []
        for i in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(i)
            guard MIDIPortConnectSource(port, source, nil) == noErr else { continue }
            sources.append(source)
            var value: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &value)
            names.append(value?.takeRetainedValue() as String? ?? "MIDI keyboard")
        }
        onDevices?(names, port == 0 ? "MIDI input could not be started." : nil)
    }
    // Running status and fragmented messages are preserved across packets.
    func consume(_ bytes: [UInt8]) {
        for b in bytes {
            if b >= 248 { continue }
            if b == 240 { sysex = true; running = 0; pending = []; continue }
            if b == 247 { sysex = false; continue }
            if sysex { continue }
            if b >= 128 {
                pending = []
                running = b < 240 ? b : 0
                continue
            }
            guard running >= 128 else { continue }
            pending.append(b)
            let kind = running & 240
            let required = (kind == 192 || kind == 208) ? 1 : 2
            if pending.count == required {
                if kind == 144 { onNote?(Int(pending[0]), Int(pending[1]), pending[1] > 0) }
                if kind == 128 { onNote?(Int(pending[0]), Int(pending[1]), false) }
                pending = []
            }
        }
    }
    deinit { if port != 0 { MIDIPortDispose(port) }; if client != 0 { MIDIClientDispose(client) } }
}

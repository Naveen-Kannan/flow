import AVFoundation
import CoreAudio
import Foundation
import IOKit
import os

private let micLog = Logger(subsystem: "com.nkannan.flow", category: "mic")

public enum AudioRecorderError: Error {
    case microphoneDenied
    case alreadyRecording
    case notRecording
    case setupFailed
}

/// Records 16 kHz mono PCM `.wav`. Prefers the built-in mic: a Bluetooth headset mic (AirPods) takes
/// about a second to come up, recording silence over the first words, and drops the headset into
/// low-quality call audio. `FLOW_INPUT=default` uses the system default input instead.
/// Reads the device directly through a Core Audio IOProc: AVAudioEngine shares one IO unit between
/// input and output, so an input device other than the output device stops the engine ~40 ms in.
public final class AudioRecorder {
    private var device = AudioDeviceID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    private var writer: WavWriter?
    private var outputURL: URL?
    private let queue = DispatchQueue(label: "com.nkannan.flow.mic", qos: .userInitiated)

    public init() {}

    public var isRecording: Bool {
        proc != nil
    }

    public func begin() throws -> URL {
        guard proc == nil else { throw AudioRecorderError.alreadyRecording }
        guard MicrophonePermission.requestIfNeeded() else {
            throw AudioRecorderError.microphoneDenied
        }
        let preferBuiltIn = ProcessInfo.processInfo.environment["FLOW_INPUT"] != "default"
        guard let id = (preferBuiltIn ? InputDevice.builtIn() : nil) ?? InputDevice.defaultInput(),
              var asbd = InputDevice.format(id),
              let format = AVAudioFormat(streamDescription: &asbd)
        else { throw AudioRecorderError.setupFailed }

        let url = Self.makeOutputURL()
        let writer = try WavWriter(url)
        var proc: AudioDeviceIOProcID?
        let created = AudioDeviceCreateIOProcIDWithBlock(&proc, id, queue) { _, input, _, _, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input, deallocator: nil) else { return }
            writer.write(buffer)
        }
        guard created == noErr, let proc else {
            try? FileManager.default.removeItem(at: url)
            throw AudioRecorderError.setupFailed
        }
        guard AudioDeviceStart(id, proc) == noErr else {
            AudioDeviceDestroyIOProcID(id, proc)
            try? FileManager.default.removeItem(at: url)
            throw AudioRecorderError.setupFailed
        }

        device = id
        self.proc = proc
        self.writer = writer
        outputURL = url
        return url
    }

    public func finish() throws -> URL {
        guard let outputURL else { throw AudioRecorderError.notRecording }
        stop()
        self.outputURL = nil
        return outputURL
    }

    public func cancel() {
        stop()
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        self.outputURL = nil
    }

    private func stop() {
        if let proc {
            AudioDeviceStop(device, proc)
            AudioDeviceDestroyIOProcID(device, proc)
        }
        proc = nil
        if let writer {
            micLog.notice("recorded \(writer.frames) frames from device \(self.device) (built-in: \(self.device == InputDevice.builtIn() ?? 0))")
        }
        writer?.close()
        writer = nil
    }

    private static func makeOutputURL() -> URL {
        let name = "flow-\(UUID().uuidString).wav"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }
}

/// Any PCM in, 16 kHz mono Int16 wav out. Writes come from the tap thread; `close` flushes the header.
private final class WavWriter: @unchecked Sendable {
    private static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private(set) var frames = 0

    init(_ url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard let file, buffer.frameLength > 0 else { return }
        frames += Int(buffer.frameLength)
        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: Self.format)
            converter?.downmix = true
        }
        guard let converter else { return }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / buffer.format.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: capacity) else { return }
        var fed = false
        converter.convert(to: out, error: nil) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return buffer
        }
        if out.frameLength > 0 { try? file.write(from: out) }
    }

    func close() {
        lock.lock(); defer { lock.unlock() }
        file = nil
    }
}

enum InputDevice {
    /// The built-in mic, unless the lid is closed (the mic is then disconnected and records silence).
    static func builtIn() -> AudioDeviceID? {
        guard !lidClosed() else { return nil }
        return devices().first { transport($0) == kAudioDeviceTransportTypeBuiltIn && hasInput($0) }
    }

    static func defaultInput() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr && id != kAudioObjectUnknown ? id : nil
    }

    static func format(_ id: AudioDeviceID) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamFormat,
                                                 mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &asbd)
        return status == noErr && asbd.mSampleRate > 0 ? asbd : nil
    }

    private static func devices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func transport(_ id: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : 0
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func lidClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return (value?.takeRetainedValue() as? Bool) ?? false
    }
}

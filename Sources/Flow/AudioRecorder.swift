import AVFoundation
import Foundation

public enum AudioRecorderError: Error {
    case microphoneDenied
    case alreadyRecording
    case notRecording
    case setupFailed
}

public final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var outputURL: URL?

    public init() {}

    public func begin() throws -> URL {
        guard recorder == nil else { throw AudioRecorderError.alreadyRecording }
        guard MicrophonePermission.requestIfNeeded() else {
            throw AudioRecorderError.microphoneDenied
        }

        let url = Self.makeOutputURL()
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        guard recorder.record() else { throw AudioRecorderError.setupFailed }

        self.recorder = recorder
        outputURL = url
        return url
    }

    public func finish() throws -> URL {
        guard let recorder, let outputURL else { throw AudioRecorderError.notRecording }
        recorder.stop()
        self.recorder = nil
        self.outputURL = nil
        return outputURL
    }

    public func cancel() {
        recorder?.stop()
        recorder = nil

        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        self.outputURL = nil
    }

    private static func makeOutputURL() -> URL {
        let name = "flow-\(UUID().uuidString).m4a"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }
}

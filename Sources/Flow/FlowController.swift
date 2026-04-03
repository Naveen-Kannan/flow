import Foundation

public protocol AudioRecording: AnyObject {
    var isRecording: Bool { get }
    func begin() throws -> URL
    func finish() throws -> URL
    func cancel()
}

extension AudioRecorder: AudioRecording {}

public final class FlowController {
    public var onTranscript: ((String) -> Void)?
    public var onError: ((any Error) -> Void)?

    private let recorder: any AudioRecording
    private let transcriber: any AudioTranscriber
    private let lock = NSLock()
    private var activeRecordingURL: URL?

    public init(
        recorder: any AudioRecording = AudioRecorder(),
        transcriber: any AudioTranscriber = DefaultTranscriber.make()
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
    }

    public var isRecording: Bool {
        lock.withLock { activeRecordingURL != nil }
    }

    @discardableResult
    public func begin() throws -> URL {
        if let url = lock.withLock({ activeRecordingURL }) {
            return url
        }

        let url = try recorder.begin()
        lock.withLock {
            activeRecordingURL = url
        }
        return url
    }

    @discardableResult
    public func finishRecording() throws -> URL {
        guard lock.withLock({ activeRecordingURL != nil }) else {
            throw AudioRecorderError.notRecording
        }

        let url = try recorder.finish()
        lock.withLock {
            activeRecordingURL = nil
        }
        return url
    }

    public func commit() throws -> URL {
        let audioURL = try finishRecording()
        Task {
            do {
                let text = try await transcriber.transcribe(audioURL)
                await MainActor.run {
                    self.onTranscript?(text)
                }
            } catch {
                await MainActor.run {
                    self.onError?(error)
                }
            }
        }
        return audioURL
    }

    public func cancel() {
        let shouldCancel = lock.withLock {
            let hasRecording = activeRecordingURL != nil
            activeRecordingURL = nil
            return hasRecording
        }
        guard shouldCancel else { return }
        recorder.cancel()
    }

    public func transcribe(_ audioURL: URL) async throws -> String {
        try await transcriber.transcribe(audioURL)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

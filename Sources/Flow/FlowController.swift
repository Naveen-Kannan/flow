import Foundation

public final class FlowController {
    public var onTranscript: ((String) -> Void)?

    private let recorder: AudioRecorder
    private let transcriber: any AudioTranscriber

    public init(
        recorder: AudioRecorder = AudioRecorder(),
        transcriber: any AudioTranscriber = NoopTranscriber()
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
    }

    @discardableResult
    public func begin() throws -> URL {
        try recorder.begin()
    }

    @discardableResult
    public func finishRecording() throws -> URL {
        try recorder.finish()
    }

    public func commit() throws -> URL {
        let audioURL = try finishRecording()
        Task {
            if let text = try? await transcriber.transcribe(audioURL) {
                onTranscript?(text)
            }
        }
        return audioURL
    }

    public func cancel() {
        recorder.cancel()
    }

    public func transcribe(_ audioURL: URL) async throws -> String {
        try await transcriber.transcribe(audioURL)
    }
}

import Foundation
import Testing
@testable import Flow

@Test func noopTranscriberIncludesFileName() async throws {
    let url = URL(fileURLWithPath: "/tmp/example.m4a")
    let text = try await NoopTranscriber().transcribe(url)
    #expect(text.contains("example.m4a"))
}

@Test func beginIsIdempotentWhileRecording() throws {
    let recorder = StubRecorder()
    let controller = FlowController(recorder: recorder, transcriber: NoopTranscriber())

    let first = try controller.begin()
    let second = try controller.begin()

    #expect(first == second)
    #expect(recorder.beginCount == 1)
}

@Test func commitStopsRecordingAndPublishesTranscript() async throws {
    let recorder = StubRecorder()
    let controller = FlowController(recorder: recorder, transcriber: StubTranscriber(result: "hello"))
    let box = LockedBox<String?>(nil)
    controller.onTranscript = { text in
        box.withLock { $0 = text }
    }

    _ = try controller.begin()
    let url = try controller.commit()
    try await Task.sleep(for: .milliseconds(50))

    #expect(url == recorder.url)
    #expect(recorder.finishCount == 1)
    #expect(box.withLock { $0 } == "hello")
}

private final class StubRecorder: AudioRecording {
    let url = URL(fileURLWithPath: "/tmp/test.m4a")
    var beginCount = 0
    var finishCount = 0
    var isRecording = false

    func begin() throws -> URL {
        beginCount += 1
        isRecording = true
        return url
    }

    func finish() throws -> URL {
        guard isRecording else { throw AudioRecorderError.notRecording }
        finishCount += 1
        isRecording = false
        return url
    }

    func cancel() {
        isRecording = false
    }
}

private struct StubTranscriber: AudioTranscriber {
    let result: String

    func transcribe(_ audioURL: URL) async throws -> String {
        result
    }
}

private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) {
        self.value = value
    }

    func withLock<R>(_ body: (inout T) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

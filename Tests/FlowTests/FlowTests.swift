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
    let controller = FlowController(recorder: recorder, transcriber: NoopTranscriber(), playback: StubPlayback())

    let first = try controller.begin()
    let second = try controller.begin()

    #expect(first == second)
    #expect(recorder.beginCount == 1)
}

@Test func commitStopsRecordingAndPublishesTranscript() async throws {
    let recorder = StubRecorder()
    let controller = FlowController(recorder: recorder, transcriber: StubTranscriber(result: "hello"), playback: StubPlayback())
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
    var failBegin = false
    var failFinish = false
    var events: ((String) -> Void)?

    func begin() throws -> URL {
        events?("record")
        if failBegin { throw AudioRecorderError.setupFailed }
        beginCount += 1
        isRecording = true
        return url
    }

    func finish() throws -> URL {
        events?("stop")
        if failFinish { throw AudioRecorderError.setupFailed }
        guard isRecording else { throw AudioRecorderError.notRecording }
        finishCount += 1
        isRecording = false
        return url
    }

    func cancel() {
        events?("cancel")
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

private final class StubPlayback: RecordingPlayback {
    var events: ((String) -> Void)?
    func pauseForRecording() { events?("pause") }
    func resumeAfterRecording() { events?("resume") }
}

@Test func musicPausesBeforeMicAndResumesAtStop() throws {
    var events: [String] = []
    let recorder = StubRecorder()
    let playback = StubPlayback()
    recorder.events = { events.append($0) }
    playback.events = { events.append($0) }
    let controller = FlowController(recorder: recorder, transcriber: NoopTranscriber(), playback: playback)
    _ = try controller.begin()
    _ = try controller.begin()
    _ = try controller.finishRecording()
    controller.cancel()
    #expect(events == ["pause", "record", "stop", "resume"])
}

@Test func musicRestoredOnFailedStartCancelAndFailedStop() throws {
    for failure in ["start", "stop", "cancel"] {
        var events: [String] = []
        let recorder = StubRecorder()
        let playback = StubPlayback()
        recorder.events = { events.append($0) }
        playback.events = { events.append($0) }
        recorder.failBegin = failure == "start"
        recorder.failFinish = failure == "stop"
        let controller = FlowController(recorder: recorder, transcriber: NoopTranscriber(), playback: playback)
        if failure == "start" {
            #expect(throws: AudioRecorderError.self) { try controller.begin() }
        } else {
            _ = try controller.begin()
            if failure == "cancel" { controller.cancel() }
            else { #expect(throws: AudioRecorderError.self) { try controller.finishRecording() } }
        }
        #expect(events.last == "resume")
        #expect(!controller.isRecording)
    }
}

@Test func rapidPressAndReleaseRemainOrderedOnCommandQueue() async throws {
    let events = LockedBox<[String]>([])
    let recorder = StubRecorder()
    let playback = StubPlayback()
    recorder.events = { event in events.withLock { $0.append(event) } }
    playback.events = { event in events.withLock { $0.append(event) } }
    let controller = FlowController(recorder: recorder, transcriber: StubTranscriber(result: "ok"), playback: playback)
    controller.onTranscript = { _ in events.withLock { $0.append("text") } }
    let commands = FlowCommands(controller: controller).commands
    commands["flow.begin"]?()
    commands["flow.begin"]?()
    commands["flow.commit"]?()
    for _ in 0..<100 {
        if events.withLock({ $0.last == "text" }) { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(events.withLock { $0 } == ["pause", "record", "stop", "resume", "text"])
}

@Test func defaultBackendIsParakeetAndWhisperRemainsSelectable() {
    #expect(DefaultTranscriber.make(environment: [:]) is ParakeetTranscriber)
    #expect(!(DefaultTranscriber.make(environment: ["FLOW_TRANSCRIBER": "whisper"]) is ParakeetTranscriber))
}

private final class PlaybackURLProtocol: URLProtocol {
    static let requests = LockedBox<[String]>([])
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.withLock { $0.append(request.url!.lastPathComponent) }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func delayedResumeCannotInterruptAnotherRecording() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [PlaybackURLProtocol.self]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    PlaybackURLProtocol.requests.withLock { $0 = [] }
    let playback = TunesRecordingPlayback(resumeDelay: 0.15, session: session)
    playback.pauseForRecording()
    playback.resumeAfterRecording()
    try await Task.sleep(for: .milliseconds(50))
    #expect(PlaybackURLProtocol.requests.withLock { $0 } == ["begin"])
    playback.pauseForRecording()
    try await Task.sleep(for: .milliseconds(180))
    #expect(PlaybackURLProtocol.requests.withLock { $0 } == ["begin"])
    playback.resumeAfterRecording()
    try await Task.sleep(for: .milliseconds(250))
    #expect(PlaybackURLProtocol.requests.withLock { $0 } == ["begin", "end"])
}

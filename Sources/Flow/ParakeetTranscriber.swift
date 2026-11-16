import FluidAudio
import Foundation

public struct TimedToken: Sendable, Equatable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval
    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text; self.start = start; self.end = end
    }
}

public actor ParakeetTranscriber: AudioTranscriber {
    // One model per process: dictation and meeting notes share it.
    public static let shared = ParakeetTranscriber(
        modelDirectory: ProcessInfo.processInfo.environment["FLOW_PARAKEET_MODEL_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    )

    private let modelDirectory: URL?
    private var initialization: Task<Void, Error>?
    private var engine: AsrManager?
    private var last: Task<Void, Never>?
    private nonisolated let meetingJobs = MeetingJobs()

    public init(modelDirectory: URL? = nil) {
        self.modelDirectory = modelDirectory
    }

    public nonisolated var isTranscribingMeeting: Bool { meetingJobs.active }

    public func prepare() async throws {
        _ = try await manager()
    }

    public func transcribe(_ audioURL: URL) async throws -> String {
        try await serial { try await $0.transcribe(audioURL, source: .microphone) }
            .text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Long-file transcription with token timings; `system` selects the system-audio decoder state.
    public func transcribeTimed(_ audioURL: URL, system: Bool) async throws -> [TimedToken] {
        meetingJobs.add(1)
        defer { meetingJobs.add(-1) }
        let r = try await serial { try await $0.transcribeStreaming(audioURL, source: system ? .system : .microphone) }
        return (r.tokenTimings ?? []).map { TimedToken(text: $0.token, start: $0.startTime, end: $0.endTime) }
    }

    // Runs jobs one at a time, in call order.
    private func serial<T: Sendable>(_ job: @escaping @Sendable (AsrManager) async throws -> T) async throws -> T {
        let previous = last
        let task = Task { [self] in
            await previous?.value
            return try await job(try await manager())
        }
        last = Task { _ = try? await task.value }
        return try await task.value
    }

    private func manager() async throws -> AsrManager {
        if let engine { return engine }
        if let initialization {
            try await initialization.value
            return engine!
        }
        let directory = modelDirectory
        let task = Task { [self] in
            let models = try await AsrModels.downloadAndLoad(to: directory, version: .v2)
            let manager = AsrManager()
            try await manager.initialize(models: models)
            engine = manager
        }
        initialization = task
        do {
            try await task.value
            return engine!
        }
        catch {
            initialization = nil
            throw error
        }
    }
}

private final class MeetingJobs: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var active: Bool { lock.lock(); defer { lock.unlock() }; return count > 0 }
    func add(_ delta: Int) { lock.lock(); count += delta; lock.unlock() }
}

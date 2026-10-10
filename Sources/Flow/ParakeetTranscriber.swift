import FluidAudio
import Foundation

public actor ParakeetTranscriber: AudioTranscriber {
    private let modelDirectory: URL?
    private var initialization: Task<Void, Error>?
    private var engine: AsrManager?
    private var lastTranscription: Task<String, Error>?

    public init(modelDirectory: URL? = nil) {
        self.modelDirectory = modelDirectory
    }

    public func prepare() async throws {
        _ = try await manager()
    }

    public func transcribe(_ audioURL: URL) async throws -> String {
        let previous = lastTranscription
        let task = Task { [self] in
            _ = try? await previous?.value
            let manager = try await manager()
            let result = try await manager.transcribe(audioURL, source: .microphone)
            return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        lastTranscription = task
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

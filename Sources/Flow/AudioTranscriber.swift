import Foundation

public protocol AudioTranscriber {
    func transcribe(_ audioURL: URL) async throws -> String
}

public struct NoopTranscriber: AudioTranscriber {
    public init() {}

    public func transcribe(_ audioURL: URL) async throws -> String {
        "[transcription unavailable] \(audioURL.lastPathComponent)"
    }
}

public enum ShellTranscriberError: Error {
    case executableMissing
    case modelMissing
    case failed(String)
}

public struct WhisperShellTranscriber: AudioTranscriber {
    private let executablePath: String
    private let modelPath: String

    public init(
        executablePath: String = ProcessInfo.processInfo.environment["FLOW_WHISPER_CLI"] ?? "/opt/homebrew/bin/whisper-cli",
        modelPath: String = ProcessInfo.processInfo.environment["FLOW_WHISPER_MODEL"] ?? ""
    ) {
        self.executablePath = executablePath
        self.modelPath = modelPath
    }

    public func transcribe(_ audioURL: URL) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw ShellTranscriberError.executableMissing
        }
        guard !modelPath.isEmpty else {
            throw ShellTranscriberError.modelMissing
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["-m", modelPath, "-f", audioURL.path, "-nt"]
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw ShellTranscriberError.failed(output)
        }
        return output
    }
}

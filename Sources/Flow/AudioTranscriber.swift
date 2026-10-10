import Foundation

public protocol AudioTranscriber {
    func prepare() async throws
    func transcribe(_ audioURL: URL) async throws -> String
}

public extension AudioTranscriber {
    func prepare() async throws {}
}

public enum DefaultTranscriber {
    public static func make(environment: [String: String] = ProcessInfo.processInfo.environment) -> any AudioTranscriber {
        if environment["FLOW_TRANSCRIBER"] != "whisper" {
            let directory = environment["FLOW_PARAKEET_MODEL_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            return ParakeetTranscriber(modelDirectory: directory)
        }
        let executablePath = resolveExecutablePath(environment: environment)
        let modelPath = resolveModelPath(environment: environment)

        guard let executablePath else { return UnavailableTranscriber(error: .executableMissing) }
        guard let modelPath else { return UnavailableTranscriber(error: .modelMissing) }
        return WhisperShellTranscriber(executablePath: executablePath, modelPath: modelPath)
    }

    private static func resolveExecutablePath(environment: [String: String]) -> String? {
        let candidates = environment["FLOW_WHISPER_CLI"].map { [$0] }
            ?? ["/opt/homebrew/bin/whisper-cli"]

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func resolveModelPath(environment: [String: String]) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = environment["FLOW_WHISPER_MODEL"].map { [$0] } ?? [
            "\(home)/.local/share/flow/models/ggml-tiny.en.bin",
            "\(home)/.local/share/flow/models/ggml-base.en.bin",
        ]

        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }
}

private struct UnavailableTranscriber: AudioTranscriber {
    let error: ShellTranscriberError
    func prepare() async throws { throw error }
    func transcribe(_ audioURL: URL) async throws -> String { throw error }
}

public enum ShellTranscriberError: Error {
    case executableMissing
    case modelMissing
    case conversionFailed(String)
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

        let inputURL = try prepareInputFile(audioURL)
        defer {
            if inputURL != audioURL {
                try? FileManager.default.removeItem(at: inputURL)
            }
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["-m", modelPath, "-f", inputURL.path, "-nt"]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let stderrResult = OutputBox()
        let done = DispatchGroup()
        done.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrResult.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            done.leave()
        }
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        done.wait()

        let stdout = String(
            decoding: stdoutData,
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = String(
            decoding: stderrResult.data,
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw ShellTranscriberError.failed(stderr.isEmpty ? stdout : stderr)
        }
        return stdout
    }

    private func prepareInputFile(_ audioURL: URL) throws -> URL {
        if audioURL.pathExtension.lowercased() == "wav" {
            return audioURL
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flow-\(UUID().uuidString).wav")
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = [
            "-f", "WAVE",
            "-d", "LEI16@16000",
            audioURL.path,
            outputURL.path,
        ]
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw ShellTranscriberError.conversionFailed(output)
        }
        return outputURL
    }
}

private final class OutputBox: @unchecked Sendable {
    var data = Data()
}

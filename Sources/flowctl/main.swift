import AVFoundation
import Flow
import Foundation

@main
struct FlowCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            printUsage()
            return
        }

        let playback = TunesRecordingPlayback()
        do {
            switch command {
            case "prepare":
                try await makeTranscriber().prepare()
                print("transcriber ready")
            case "doctor":
                print("backend: \(ProcessInfo.processInfo.environment["FLOW_TRANSCRIBER"] ?? "parakeet (English v2)")")
                print("microphone: \(MicrophonePermission.granted ? "granted" : "not granted")")
            case "record":
                let seconds = args.count > 1 ? Double(args[1]) ?? 3 : 3
                let controller = FlowController(playback: playback)
                let url = try controller.begin()
                print("recording: \(url.path)")
                try await Task.sleep(for: .seconds(seconds))
                let output = try controller.finishRecording()
                print("saved: \(output.path)")
            case "ptt":
                let controller = FlowController(playback: playback)
                _ = try controller.begin()
                print("recording; press return to stop")
                _ = readLine()
                let output = try controller.finishRecording()
                print("saved: \(output.path)")
            case "benchmark":
                guard args.count > 1 else { printUsage(); return }
                let transcriber = makeTranscriber()
                let start = Date()
                try await transcriber.prepare()
                print(String(format: "prepare: %.3f s", Date().timeIntervalSince(start)))
                let url = URL(fileURLWithPath: args[1])
                for index in 1...3 {
                    let start = Date()
                    let text = try await transcriber.transcribe(url)
                    print(String(format: "run %d: %.3f s", index, Date().timeIntervalSince(start)))
                    if index == 3 { print(text) }
                }
            case "transcribe":
                guard args.count > 1 else {
                    printUsage()
                    return
                }
                let url = URL(fileURLWithPath: args[1])
                let transcriber = makeTranscriber()
                let text = try await transcriber.transcribe(url)
                print(text)
            default:
                printUsage()
            }
            await playback.waitForResume()
        } catch {
            await playback.waitForResume()
            fputs("error: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    static func makeTranscriber() -> any AudioTranscriber {
        DefaultTranscriber.make()
    }

    static func printUsage() {
        print(
            """
            usage:
              flowctl prepare
              flowctl doctor
              flowctl record [seconds]
              flowctl ptt
              flowctl transcribe <audio-file>
              flowctl benchmark <audio-file>
            """
        )
    }
}

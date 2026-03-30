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

        do {
            switch command {
            case "doctor":
                print("microphone: \(MicrophonePermission.granted ? "granted" : "not granted")")
            case "record":
                let seconds = args.count > 1 ? Double(args[1]) ?? 3 : 3
                let controller = FlowController()
                let url = try controller.begin()
                print("recording: \(url.path)")
                try await Task.sleep(for: .seconds(seconds))
                let output = try controller.finishRecording()
                print("saved: \(output.path)")
            case "ptt":
                let controller = FlowController()
                _ = try controller.begin()
                print("recording; press return to stop")
                _ = readLine()
                let output = try controller.finishRecording()
                print("saved: \(output.path)")
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
        } catch {
            fputs("error: \(error)\n", stderr)
        }
    }

    static func makeTranscriber() -> any AudioTranscriber {
        let env = ProcessInfo.processInfo.environment
        if env["FLOW_WHISPER_MODEL"]?.isEmpty == false {
            return WhisperShellTranscriber()
        }
        return NoopTranscriber()
    }

    static func printUsage() {
        print(
            """
            usage:
              flowctl doctor
              flowctl record [seconds]
              flowctl ptt
              flowctl transcribe <audio-file>
            """
        )
    }
}

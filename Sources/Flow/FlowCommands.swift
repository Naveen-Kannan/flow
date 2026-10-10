import Foundation
import os

private let flowLog = Logger(subsystem: "com.nkannan.flow", category: "dictation")

public struct FlowCommands {
    public let name = "flow"
    public let controller: FlowController
    public let commands: [String: () -> Void]

    public init(controller: FlowController = FlowController()) {
        let queue = DispatchQueue(label: "com.nkannan.flow.recording")
        if controller.onTranscript == nil {
            controller.onTranscript = { text in
                TextInjector.insert(text)
            }
        }
        if controller.onError == nil {
            controller.onError = { error in
                flowLog.error("dictation failed: \(String(describing: error), privacy: .public)")
            }
        }
        Task {
            do {
                try await controller.prepare()
                flowLog.notice("dictation transcriber ready")
            }
            catch { controller.onError?(error) }
        }
        self.controller = controller
        self.commands = [
            "flow.begin": {
                queue.async {
                    do { _ = try controller.begin() }
                    catch { controller.onError?(error) }
                }
            },
            "flow.commit": {
                queue.async {
                    guard controller.isRecording else { return }
                    do { _ = try controller.commit() }
                    catch { controller.onError?(error) }
                }
            },
            "flow.cancel": { queue.async { controller.cancel() } },
        ]
    }
}

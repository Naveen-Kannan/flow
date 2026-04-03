public struct FlowCommands {
    public let name = "flow"
    public let controller: FlowController
    public let commands: [String: () -> Void]

    public init(controller: FlowController = FlowController()) {
        if controller.onTranscript == nil {
            controller.onTranscript = { text in
                TextInjector.insert(text)
            }
        }
        self.controller = controller
        self.commands = [
            "flow.begin": { _ = try? controller.begin() },
            "flow.commit": { _ = try? controller.commit() },
            "flow.cancel": { controller.cancel() },
        ]
    }
}

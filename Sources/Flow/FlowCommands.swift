public struct FlowCommands {
    public let name = "flow"
    public let controller: FlowController
    public let commands: [String: () -> Void]

    public init(controller: FlowController = FlowController()) {
        self.controller = controller
        self.commands = [
            "flow.begin": { try? controller.begin() },
            "flow.commit": { try? controller.commit() },
            "flow.cancel": { controller.cancel() },
        ]
    }
}

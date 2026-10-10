import Foundation

public protocol RecordingPlayback: AnyObject {
    func pauseForRecording()
    func resumeAfterRecording()
}

public final class TunesRecordingPlayback: RecordingPlayback {
    private let baseURL: URL
    private let resumeDelay: TimeInterval
    private let session: URLSession
    private var token: String?
    private var resumeGeneration = 0
    private var heartbeat: DispatchSourceTimer?
    private let restoration = DispatchGroup()
    private let queue = DispatchQueue(label: "com.nkannan.flow.tunes")

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:47631/control/dictation")!,
        resumeDelay: TimeInterval = Double(ProcessInfo.processInfo.environment["FLOW_TUNES_RESUME_DELAY"] ?? "4.5") ?? 4.5,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
        self.resumeDelay = resumeDelay.isFinite ? max(0, min(resumeDelay, 10)) : 4.5
    }

    deinit { heartbeat?.cancel() }

    public func pauseForRecording() {
        queue.sync {
            resumeGeneration += 1
            guard token == nil else { return }
            let token = UUID().uuidString
            self.token = token
            restoration.enter()
            send("begin", token: token)
            let heartbeat = DispatchSource.makeTimerSource(queue: queue)
            heartbeat.schedule(deadline: .now() + 60, repeating: 60)
            heartbeat.setEventHandler { [weak self] in self?.send("begin", token: token) }
            self.heartbeat = heartbeat
            heartbeat.resume()
        }
    }

    public func resumeAfterRecording() {
        queue.sync {
            guard let token else { return }
            resumeGeneration += 1
            let generation = resumeGeneration
            // Keep the playback lease alive even if a short-lived CLI controller exits scope.
            queue.asyncAfter(deadline: .now() + resumeDelay) { [self] in
                guard self.resumeGeneration == generation, self.token == token else { return }
                self.token = nil
                self.heartbeat?.cancel()
                self.heartbeat = nil
                self.send("end", token: token)
                self.restoration.leave()
            }
        }
    }

    public func waitForResume() async {
        await withCheckedContinuation { continuation in
            restoration.notify(queue: queue) { continuation.resume() }
        }
    }

    private func send(_ action: String, token: String) {
        var components = URLComponents(url: baseURL.appendingPathComponent(action), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 0.8
        let done = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { _, _, _ in done.signal() }
        task.resume()
        if done.wait(timeout: .now() + 1) == .timedOut { task.cancel() }
    }
}

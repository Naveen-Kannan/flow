import AVFoundation
import Foundation

public enum MicrophonePermission {
    public static var granted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func requestIfNeeded() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            var allowed = false
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                allowed = granted
                semaphore.signal()
            }
            semaphore.wait()
            return allowed
        default:
            return false
        }
    }
}

import Foundation
import Testing
@testable import Flow

@Test func noopTranscriberIncludesFileName() async throws {
    let url = URL(fileURLWithPath: "/tmp/example.m4a")
    let text = try await NoopTranscriber().transcribe(url)
    #expect(text.contains("example.m4a"))
}

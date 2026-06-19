import Foundation

public protocol SpeechTranscriber: Sendable {
    func transcribe(audioURL: URL) async throws -> String
}

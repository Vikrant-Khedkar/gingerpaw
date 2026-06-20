import Foundation
import Settings

/// Picks WhisperKit or Moonshine per-transcription based on the live engine setting.
public actor RoutingTranscriber: SpeechTranscriber {
    private let whisperKit: any SpeechTranscriber
    private let moonshine: any SpeechTranscriber
    private let engineProvider: @Sendable () async -> TranscriptionEngine

    public init(
        whisperKit: any SpeechTranscriber,
        moonshine: any SpeechTranscriber,
        engineProvider: @escaping @Sendable () async -> TranscriptionEngine
    ) {
        self.whisperKit = whisperKit
        self.moonshine = moonshine
        self.engineProvider = engineProvider
    }

    public func transcribe(audioURL: URL) async throws -> String {
        switch await engineProvider() {
        case .whisperKit: try await whisperKit.transcribe(audioURL: audioURL)
        case .moonshine: try await moonshine.transcribe(audioURL: audioURL)
        }
    }
}

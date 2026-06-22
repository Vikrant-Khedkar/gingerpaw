import Foundation

/// Seam so AgentWorkspace can transcribe audio without depending on the heavy Transcription
/// (WhisperKit/MLX) target. AppCore sets this to the app's existing transcriber at launch.
public enum FeedbackTranscription {
    @MainActor public static var transcribe: (@Sendable (URL) async -> String?)?
}

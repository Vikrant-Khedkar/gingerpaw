import Foundation

/// Which speech-to-text engine to run. WhisperKit (native CoreML) vs Moonshine
/// (ONNX, shelled out to Python) — for internal A/B testing.
public enum TranscriptionEngine: String, CaseIterable, Sendable, Identifiable {
    case whisperKit
    case moonshine

    public var id: String { rawValue }
    public var display: String {
        switch self {
        case .whisperKit: "WhisperKit (Whisper)"
        case .moonshine: "Moonshine (ONNX)"
        }
    }
}

public enum MoonshineModel: String, CaseIterable, Sendable, Identifiable {
    case tiny = "moonshine/tiny"
    case base = "moonshine/base"

    public var id: String { rawValue }
    public var display: String {
        switch self {
        case .tiny: "Tiny"
        case .base: "Base"
        }
    }
}

import Foundation
import TextInsertion

public enum DictationState: Equatable, Sendable {
    case idle
    case recording(startedAt: Date)
    case processing
    case inserting
    case copied
    case failed(String)

    public var isBusy: Bool {
        switch self {
        case .recording, .processing, .inserting:
            true
        case .idle, .copied, .failed:
            false
        }
    }
}

public typealias InsertionOutcome = TextInsertion.InsertionOutcome

public struct DictationResult: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let transcript: String
    public let duration: TimeInterval
    public let modelID: String
    public let insertionOutcome: InsertionOutcome
    // A/B metrics
    public let engineLabel: String
    public let audioSeconds: TimeInterval
    public let transcribeSeconds: TimeInterval

    /// Real-time factor: audio length ÷ transcription time. >1 = faster than real time.
    public var realTimeFactor: Double {
        transcribeSeconds > 0 ? audioSeconds / transcribeSeconds : 0
    }

    public init(
        id: UUID = UUID(),
        transcript: String,
        duration: TimeInterval,
        modelID: String,
        insertionOutcome: InsertionOutcome,
        engineLabel: String = "",
        audioSeconds: TimeInterval = 0,
        transcribeSeconds: TimeInterval = 0
    ) {
        self.id = id
        self.transcript = transcript
        self.duration = duration
        self.modelID = modelID
        self.insertionOutcome = insertionOutcome
        self.engineLabel = engineLabel
        self.audioSeconds = audioSeconds
        self.transcribeSeconds = transcribeSeconds
    }
}

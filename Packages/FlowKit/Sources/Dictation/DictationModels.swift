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

public struct DictationResult: Equatable, Sendable {
    public let transcript: String
    public let duration: TimeInterval
    public let modelID: String
    public let insertionOutcome: InsertionOutcome

    public init(transcript: String, duration: TimeInterval, modelID: String, insertionOutcome: InsertionOutcome) {
        self.transcript = transcript
        self.duration = duration
        self.modelID = modelID
        self.insertionOutcome = insertionOutcome
    }
}

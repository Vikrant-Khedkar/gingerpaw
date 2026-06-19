import Foundation

public protocol TextInserter: Sendable {
    func insert(_ text: String, restoreClipboard: Bool) async -> InsertionOutcome
    func copy(_ text: String) async -> InsertionOutcome
}

public enum InsertionOutcome: Equatable, Sendable {
    case pasted
    case copied
    case failed
}

import Foundation

public protocol TextProcessor: Sendable {
    func format(_ text: String) async throws -> String
}

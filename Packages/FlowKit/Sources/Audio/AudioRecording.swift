import Foundation

@MainActor
public protocol AudioRecording: AnyObject {
    func start() throws
    func stop() throws -> URL
    func cancel()
}

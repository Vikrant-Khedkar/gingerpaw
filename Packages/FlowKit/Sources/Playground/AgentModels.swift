import Foundation

public enum AgentRunStatus: Equatable, Sendable {
    case idle
    case checking
    case running
    case succeeded
    case failed(String)
}

public struct AgentAvailability: Equatable, Sendable {
    public let isInstalled: Bool
    public let detail: String

    public init(isInstalled: Bool, detail: String) {
        self.isInstalled = isInstalled
        self.detail = detail
    }
}

public struct AgentRunRequest: Equatable, Sendable {
    public let prompt: String
    public let repositoryURL: URL?

    public init(prompt: String, repositoryURL: URL?) {
        self.prompt = prompt
        self.repositoryURL = repositoryURL
    }
}

public enum AgentRunEvent: Equatable, Sendable {
    case output(String)
    case finished(exitCode: Int32)
}

public struct AgentRun: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let prompt: String
    public let repositoryURL: URL?
    public let startedAt: Date
    public var endedAt: Date?
    public var status: AgentRunStatus
    public var output: String

    public init(
        id: UUID = UUID(),
        prompt: String,
        repositoryURL: URL?,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        status: AgentRunStatus,
        output: String = ""
    ) {
        self.id = id
        self.prompt = prompt
        self.repositoryURL = repositoryURL
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.output = output
    }
}

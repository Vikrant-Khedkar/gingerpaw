import Foundation

public protocol AgentRunning: Sendable {
    func checkAvailability() async -> AgentAvailability
    func run(_ request: AgentRunRequest) -> AsyncThrowingStream<AgentRunEvent, Error>
}

public final class ClaudeAgentRunner: AgentRunning, @unchecked Sendable {
    private let command: String

    // `claude-sgai` is a shell alias (CLAUDE_CONFIG_DIR=~/.claude-sgai command claude),
    // invisible to Process/env — so invoke the real `claude` binary and set the config dir below.
    public init(command: String = "claude") {
        self.command = command
    }

    public func checkAvailability() async -> AgentAvailability {
        await withCheckedContinuation { continuation in
            let process = makeProcess(arguments: [command, "--version"], repositoryURL: nil)
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output

            do {
                try process.run()
                process.waitUntilExit()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let detail = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: AgentAvailability(
                    isInstalled: process.terminationStatus == 0,
                    detail: detail?.isEmpty == false ? detail! : "claude-sgai found"
                ))
            } catch {
                continuation.resume(returning: AgentAvailability(
                    isInstalled: false,
                    detail: "Install claude-sgai to run playground tasks."
                ))
            }
        }
    }

    public func run(_ request: AgentRunRequest) -> AsyncThrowingStream<AgentRunEvent, Error> {
        AsyncThrowingStream { continuation in
            let process = makeProcess(
                arguments: [
                    command,
                    "-p",
                    request.prompt,
                    "--output-format",
                    "stream-json",
                    "--verbose",
                ],
                repositoryURL: request.repositoryURL
            )
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            let box = RunningProcess(process: process)
            let outputFormatter = ClaudeStreamFormatter()
            let emitOutput: @Sendable (FileHandle) -> Void = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                for text in outputFormatter.displayText(from: data) where !text.isEmpty {
                    continuation.yield(.output(text))
                }
            }
            let emitError: @Sendable (FileHandle) -> Void = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                continuation.yield(.output(text))
            }
            outputPipe.fileHandleForReading.readabilityHandler = emitOutput
            errorPipe.fileHandleForReading.readabilityHandler = emitError
            process.terminationHandler = { finishedProcess in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                continuation.yield(.finished(exitCode: finishedProcess.terminationStatus))
                continuation.finish()
            }
            continuation.onTermination = { _ in
                box.terminate()
            }

            do {
                try process.run()
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                continuation.finish(throwing: error)
            }
        }
    }

    private func makeProcess(arguments: [String], repositoryURL: URL?) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryURL
        process.environment = Self.environmentWithLocalCLIs()
        return process
    }

    private static func environmentWithLocalCLIs() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // replicate the `claude-sgai` alias: use the separate sgai config dir
        environment["CLAUDE_CONFIG_DIR"] = "\(home)/.claude-sgai"
        let additions = [
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]
        let currentPath = environment["PATH"] ?? ""
        environment["PATH"] = (additions + [currentPath])
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        return environment
    }
}

private final class RunningProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process

    init(process: Process) {
        self.process = process
    }

    func terminate() {
        lock.lock()
        defer { lock.unlock() }
        if process.isRunning {
            process.terminate()
        }
    }
}

private final class ClaudeStreamFormatter: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""

    func displayText(from data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        buffer += String(data: data, encoding: .utf8) ?? ""
        var lines = buffer.components(separatedBy: .newlines)
        buffer = lines.popLast() ?? ""
        return lines.compactMap(displayText(for:))
    }

    private func displayText(for line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else {
            return trimmed + "\n"
        }

        switch type {
        case "assistant":
            return assistantText(from: object)
        case "result":
            if let result = object["result"] as? String, !result.isEmpty {
                return "\nResult:\n\(result)\n"
            }
            return nil
        default:
            return nil
        }
    }

    private func assistantText(from object: [String: Any]) -> String? {
        guard let message = object["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]]
        else {
            return nil
        }

        let text = content.compactMap { item -> String? in
            guard item["type"] as? String == "text" else { return nil }
            return item["text"] as? String
        }.joined(separator: "\n")

        return text.isEmpty ? nil : text + "\n"
    }
}

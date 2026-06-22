import Foundation
import SwiftUI

public enum RunStatus: String, Sendable, Codable {
    case queued, running, verifying, succeeded, failed, cancelled

    var isTerminal: Bool { self == .succeeded || self == .failed || self == .cancelled }
    var occupiesSlot: Bool { self == .running || self == .verifying }
}

/// What to do with a run's branch once it goes green. Chosen per dispatch.
public enum MergeMode: String, Sendable, Codable { case none, pr, merge }

/// Result of the post-green action.
public enum MergeOutcome: String, Sendable, Codable { case none, prOpen, merged, conflict, failed }

/// One row in a run's activity feed.
struct RunEvent: Identifiable, Sendable {
    let id = UUID()
    let icon: String
    let text: String
}

/// Splits a byte stream into complete `\n`-terminated lines across `readabilityHandler`
/// invocations (chunks routinely split mid-line). Touched only from the pipe's serial
/// read callback, never concurrently.
private final class LineBuffer: @unchecked Sendable {
    private var data = Data()
    func feed(_ chunk: Data, onLine: (String) -> Void) {
        data.append(chunk)
        while let nl = data.firstIndex(of: 0x0a) {
            let line = data[data.startIndex..<nl]
            data.removeSubrange(data.startIndex...nl)
            if let s = String(data: line, encoding: .utf8) { onLine(s) }
        }
    }
}

/// A headless agent run: launches the agent in print/stream-json mode, parses its
/// NDJSON output into a live activity feed + status. No PTY. Reuses a standalone
/// `Workspace` for diff/commit/PR (not registered in `WorkspaceModel`).
@MainActor
@Observable
final class AgentRun: Identifiable {
    let id = UUID()
    let task: String
    let kind: AgentKind
    let branch: String
    let repoPath: String
    let worktreePath: String
    let startedAt: Date
    let workspace: Workspace
    let verifyCommand: String?
    let mergeMode: MergeMode
    let isPlanner: Bool
    let promptOverride: String?   // headless prompt to use instead of `task` (planner uses this)
    let resumeSessionID: String?  // when set, continue this Claude session (--resume)

    var status: RunStatus = .queued
    var activity: String = "Queued"
    var events: [RunEvent] = []
    var summary: String = ""
    var endedAt: Date?
    var mergeOutcome: MergeOutcome = .none
    var prURL: String?
    var jobID: UUID?
    var sessionID: String?   // captured from the stream; enables resume

    private var process: Process?
    private var doneWaiters: [CheckedContinuation<RunStatus, Never>] = []

    /// Suspend until the run reaches a terminal state (used to chain sequential jobs).
    func waitUntilDone() async -> RunStatus {
        if status.isTerminal { return status }
        return await withCheckedContinuation { doneWaiters.append($0) }
    }

    private func signalDone() {
        let s = status, waiters = doneWaiters
        doneWaiters = []
        waiters.forEach { $0.resume(returning: s) }
    }

    init(task: String, kind: AgentKind, branch: String, repoPath: String, worktreePath: String,
         startedAt: Date, verifyCommand: String? = nil, mergeMode: MergeMode = .none,
         isPlanner: Bool = false, promptOverride: String? = nil, resumeSessionID: String? = nil) {
        self.task = task
        self.kind = kind
        self.branch = branch
        self.repoPath = repoPath
        self.worktreePath = worktreePath
        self.startedAt = startedAt
        self.verifyCommand = verifyCommand
        self.mergeMode = mergeMode
        self.isPlanner = isPlanner
        self.promptOverride = promptOverride
        self.resumeSessionID = resumeSessionID
        self.workspace = Workspace(repoPath: repoPath, branch: branch, worktreePath: worktreePath)
    }

    private var followUpPrompt: String?

    /// Continue THIS run in place: re-run the same Claude session (`--resume`) with a follow-up,
    /// appending to the same feed. Used by feedback so it doesn't spawn a cold new run.
    func continueWith(_ followUp: String) {
        guard status.isTerminal, let sid = sessionID, !sid.isEmpty else { return }
        _ = sid
        followUpPrompt = followUp
        endedAt = nil
        events.append(RunEvent(icon: "arrowshape.turn.up.right", text: "Continuing with your feedback…"))
        status = .queued
        start()
    }

    var canContinue: Bool { status.isTerminal && (sessionID?.isEmpty == false) }

    func start() {
        guard status == .queued else { return }
        status = .running
        activity = "Starting…"
        let prompt = followUpPrompt ?? promptOverride ?? task
        let resumeSid = followUpPrompt != nil ? sessionID : resumeSessionID
        followUpPrompt = nil
        guard let command = kind.headlessCommand(task: prompt, resumeSessionID: resumeSid) else {
            fail("\(kind.title) can't run headless yet"); return
        }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env = ProcessInfo.processInfo.environment
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", command]
        process.environment = env
        process.currentDirectoryURL = URL(fileURLWithPath: worktreePath)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()   // discard agent's stderr noise; stdout is the protocol

        let buffer = LineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            buffer.feed(chunk) { line in
                Task { @MainActor in self.ingest(line) }
            }
        }
        process.terminationHandler = { proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            let code = proc.terminationStatus
            Task { @MainActor in self.agentFinished(exitCode: code) }
        }

        self.process = process
        do { try process.run() } catch { fail("Couldn't launch \(kind.binary): \(error.localizedDescription)") }
    }

    func cancel() {
        guard status == .queued || status == .running || status == .verifying else { return }
        status = .cancelled
        activity = "Cancelled"
        endedAt = Date()
        process?.terminate()
        signalDone()
        RunsModel.shared.recordFinished(self)
        RunsModel.shared.pump()
    }

    var elapsed: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt) }

    // MARK: Stream ingestion

    private func ingest(_ line: String) {
        guard status == .running, let ev = StreamEvent.decode(line: line) else { return }
        if sessionID == nil, let sid = ev.sessionId, !sid.isEmpty { sessionID = sid }
        switch ev.type {
        case "assistant":
            for block in ev.message?.content ?? [] {
                if block.type == "tool_use" {
                    let a = Self.activityLine(tool: block.name, input: block.input)
                    activity = a
                    events.append(RunEvent(icon: Self.icon(tool: block.name), text: a))
                } else if block.type == "text" {
                    let t = Self.clean(block.text ?? "")
                    if !t.isEmpty { events.append(RunEvent(icon: "text.alignleft", text: t)) }
                }
            }
        case "result":
            let r = Self.clean(ev.result ?? "")
            if !r.isEmpty { summary = r }
        default:
            break
        }
    }

    /// Agent process exited. Show its summary, then either gate on verify or finalize.
    private func agentFinished(exitCode: Int32) {
        guard status == .running else { return }
        let ok = exitCode == 0
        // The result event usually repeats the agent's final message — only add a card when new.
        let lastText = events.last?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty, summary != lastText {
            events.append(RunEvent(icon: ok ? "checkmark.seal.fill" : "xmark.octagon.fill", text: summary))
        }
        guard ok else { finalize(.failed); return }
        if let cmd = verifyCommand?.trimmingCharacters(in: .whitespaces), !cmd.isEmpty { runVerify(cmd) }
        else { finalize(.succeeded) }
    }

    /// The Janitor: run the verify command in the worktree; green → succeeded, red → failed.
    private func runVerify(_ cmd: String) {
        status = .verifying
        activity = "Verifying…"
        events.append(RunEvent(icon: "checkmark.shield", text: "Verifying: \(cmd)"))
        let path = worktreePath
        Task {
            let (code, tail) = await Self.runToCompletion(cmd, cwd: path)
            if code == 0 {
                events.append(RunEvent(icon: "checkmark.shield.fill", text: "Verification passed"))
                finalize(.succeeded)
            } else {
                let suffix = tail.isEmpty ? "" : "\n\(tail)"
                events.append(RunEvent(icon: "xmark.shield.fill", text: "Verification failed (exit \(code))\(suffix)"))
                finalize(.failed)
            }
        }
    }

    private func finalize(_ newStatus: RunStatus) {
        guard status == .running || status == .verifying else { return }
        status = newStatus
        endedAt = Date()
        activity = newStatus == .succeeded ? "Done" : "Failed"
        signalDone()
        Task {
            await workspace.refreshDiffAndWait()
            if isPlanner { RunsModel.shared.plannerFinished(self) }
            else if newStatus == .succeeded { await RunsModel.shared.onRunSucceeded(self) }
            RunsModel.shared.recordFinished(self)
            RunsModel.shared.pump()
        }
    }

    private func fail(_ message: String) {
        status = .failed
        activity = "Failed"
        endedAt = Date()
        events.append(RunEvent(icon: "xmark.octagon.fill", text: message))
        if summary.isEmpty { summary = message }
        signalDone()
        RunsModel.shared.recordFinished(self)
        RunsModel.shared.pump()
    }

    /// Run a shell command to completion in `cwd`; returns (exit code, last ~15 lines of output).
    nonisolated static func runToCompletion(_ command: String, cwd: String) async -> (Int32, String) {
        await Task.detached {
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            let p = Process()
            p.executableURL = URL(fileURLWithPath: shell)
            p.arguments = ["-lc", command]
            p.currentDirectoryURL = URL(fileURLWithPath: cwd)
            let pipe = Pipe()
            p.standardOutput = pipe; p.standardError = pipe
            guard (try? p.run()) != nil else { return (Int32(127), "couldn't launch verify command") }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()   // drain before wait to avoid deadlock
            p.waitUntilExit()
            let out = String(data: data, encoding: .utf8) ?? ""
            let tail = out.split(separator: "\n", omittingEmptySubsequences: false).suffix(15).joined(separator: "\n")
            return (p.terminationStatus, tail.trimmingCharacters(in: .whitespacesAndNewlines))
        }.value
    }

    // MARK: Activity rendering

    nonisolated static func activityLine(tool: String?, input: ToolInput?) -> String {
        let name = tool ?? "tool"
        let file = (input?.filePath ?? input?.path).map { ($0 as NSString).lastPathComponent }
        switch name {
        case "Edit", "Write", "MultiEdit", "NotebookEdit":
            return file.map { "Editing \($0)" } ?? "Editing files"
        case "Read":
            return file.map { "Reading \($0)" } ?? "Reading files"
        case "Bash":
            return input?.command.map { "Running \($0.prefix(48))" } ?? "Running a command"
        case "Grep", "Glob":
            return input?.pattern.map { "Searching \"\($0)\"" } ?? "Searching"
        case "Task":
            return input?.description.map { "Subagent: \($0)" } ?? "Spawning a subagent"
        case "TodoWrite":
            return "Planning tasks"
        case "WebFetch", "WebSearch":
            return "Browsing the web"
        default:
            return file.map { "\(name): \($0)" } ?? name
        }
    }

    /// Drop the `<say>…</say>` spoken-summary line GingerPaw asks agents to emit.
    nonisolated static func clean(_ s: String) -> String {
        var out = s
        while let open = out.range(of: "<say>"), let close = out.range(of: "</say>"), close.upperBound >= open.lowerBound {
            out.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func icon(tool: String?) -> String {
        switch tool {
        case "Edit", "Write", "MultiEdit", "NotebookEdit": return "pencil"
        case "Read": return "doc.text"
        case "Bash": return "terminal"
        case "Grep", "Glob": return "magnifyingglass"
        case "Task": return "sparkles"
        case "TodoWrite": return "checklist"
        case "WebFetch", "WebSearch": return "globe"
        default: return "wrench.and.screwdriver"
        }
    }
}

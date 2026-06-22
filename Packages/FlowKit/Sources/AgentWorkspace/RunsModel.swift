import Foundation
import SwiftUI

/// Persisted summary of a finished (or in-flight, last-known) run. The live activity
/// feed is in-memory only; this is what survives relaunch. Added fields are optional
/// so older persisted records still decode.
struct RunRecord: Codable, Identifiable, Sendable {
    var id: UUID
    var task: String
    var agent: String
    var branch: String
    var repoPath: String
    var worktreePath: String
    var status: RunStatus
    var summary: String
    var insertions: Int
    var deletions: Int
    var files: Int
    var startedAt: Date
    var endedAt: Date?
    var verifyCommand: String?
    var mergeMode: MergeMode?
    var mergeOutcome: MergeOutcome?
    var prURL: String?
    var jobID: UUID?
    var sessionID: String?

    var repoName: String { (repoPath as NSString).lastPathComponent }
    var worktreeExists: Bool { FileManager.default.fileExists(atPath: worktreePath) }
    var canResume: Bool { (sessionID?.isEmpty == false) && worktreeExists }
}

/// Tunables that persist across launches.
struct FactoryConfig: Codable, Sendable {
    var maxConcurrent: Int = 3
    var verifyByRepo: [String: String] = [:]
    var defaultMergeMode: MergeMode = .none
    var previewByRepo: [String: String]?      // start command per repo
    var previewPortByRepo: [String: Int]?     // dev-server port per repo
}

/// Owns headless runs: dispatch (worktree + agent), a concurrency-throttled scheduler,
/// the post-green merge queue, and a persisted history.
@MainActor
@Observable
final class RunsModel {
    static let shared = RunsModel()

    var runs: [AgentRun] = []          // live this session (newest first)
    var history: [RunRecord] = []      // persisted, includes finished runs from prior sessions
    var jobs: [Job] = []               // live goals (planner + children), newest first
    var jobHistory: [JobRecord] = []   // persisted jobs
    var selectedRunID: AgentRun.ID?
    var config = FactoryConfig()

    private let storeKey = "agentRuns"
    private let configKey = "factoryConfig"
    private let jobsKey = "factoryJobs"

    init() { load() }

    // MARK: Config

    var maxConcurrent: Int {
        get { config.maxConcurrent }
        set { config.maxConcurrent = max(1, min(newValue, 12)); saveConfig(); pump() }
    }
    var defaultMergeMode: MergeMode {
        get { config.defaultMergeMode }
        set { config.defaultMergeMode = newValue; saveConfig() }
    }
    func verifyCommand(for repo: String) -> String { config.verifyByRepo[repo] ?? "" }
    func previewCommand(for repo: String) -> String { config.previewByRepo?[repo] ?? "" }
    func previewPort(for repo: String) -> Int { config.previewPortByRepo?[repo] ?? 3000 }
    func savePreview(repo: String, command: String, port: Int) {
        if config.previewByRepo == nil { config.previewByRepo = [:] }
        if config.previewPortByRepo == nil { config.previewPortByRepo = [:] }
        config.previewByRepo?[repo] = command
        config.previewPortByRepo?[repo] = port
        saveConfig()
    }

    // MARK: Dispatch + scheduler

    /// Queue a task: create an isolated worktree on a fresh branch, then let the scheduler
    /// start it when a slot is free. Parallelism is throttled by `maxConcurrent`.
    @discardableResult
    func dispatch(repoPath: String, task: String, kind: AgentKind = .claude,
                  verifyCommand: String? = nil, mergeMode: MergeMode = .none,
                  jobID: UUID? = nil, isPlanner: Bool = false, promptOverride: String? = nil,
                  branchSeed: String? = nil, base: String = "HEAD") async throws -> AgentRun {
        AgentWorkspaceWindow.show()
        let branch = uniqueBranch(for: branchSeed ?? task)
        let startedAt = Date()
        let path = try await Task.detached { try GitWorktrees.create(repoPath: repoPath, branch: branch, base: base) }.value
        MCPConfig.wireWorktree(path)
        if let v = verifyCommand?.trimmingCharacters(in: .whitespaces), !v.isEmpty {
            config.verifyByRepo[repoPath] = v; saveConfig()
        }
        let run = AgentRun(task: task, kind: kind, branch: branch, repoPath: repoPath, worktreePath: path,
                           startedAt: startedAt, verifyCommand: verifyCommand, mergeMode: mergeMode,
                           isPlanner: isPlanner, promptOverride: promptOverride)
        run.jobID = jobID
        runs.insert(run, at: 0)
        selectedRunID = run.id
        pump()
        return run
    }

    // MARK: Jobs (Mayor)

    /// Create a goal and kick off its planner run. When the planner finishes, the job goes
    /// `.ready` with parsed subtasks for the user to confirm.
    @discardableResult
    func createJob(repoPath: String, goal: String, verifyCommand: String?, mergeMode: MergeMode) async throws -> Job {
        let job = Job(goal: goal, repoPath: repoPath, verifyCommand: verifyCommand, mergeMode: mergeMode, createdAt: Date())
        jobs.insert(job, at: 0)
        if let v = verifyCommand?.trimmingCharacters(in: .whitespaces), !v.isEmpty {
            config.verifyByRepo[repoPath] = v; saveConfig()
        }
        let run = try await dispatch(repoPath: repoPath, task: "Plan: \(goal)", verifyCommand: nil,
                                     mergeMode: .none, jobID: job.id, isPlanner: true,
                                     promptOverride: Planner.prompt(goal: goal), branchSeed: "plan-\(goal)")
        job.plannerRunID = run.id
        persistJobs()
        return job
    }

    func plannerFinished(_ run: AgentRun) {
        guard let jobID = run.jobID, let job = jobs.first(where: { $0.id == jobID }) else { return }
        if run.status == .succeeded {
            let plan = Planner.parsePlan(run.summary)
            job.mode = plan.mode
            job.subtasks = plan.subtasks
            job.status = plan.subtasks.isEmpty ? .failed : .ready
        } else {
            job.status = .failed
        }
        persistJobs()
    }

    /// User confirmed the (possibly edited) subtask list — run them per the job's mode.
    func dispatchJob(_ job: Job, subtasks: [String]) {
        job.subtasks = subtasks
        job.status = .running
        persistJobs()
        switch job.mode {
        case .parallel: dispatchParallel(job, subtasks)
        case .sequential: dispatchSequential(job, subtasks)
        }
    }

    /// Independent subtasks — fan out, each its own worktree off base, each its own on-green.
    private func dispatchParallel(_ job: Job, _ subtasks: [String]) {
        let repo = job.repoPath, verify = job.verifyCommand, mode = job.mergeMode, jid = job.id
        Task {
            for task in subtasks {
                if let run = try? await dispatch(repoPath: repo, task: task, verifyCommand: verify,
                                                 mergeMode: mode, jobID: jid) {
                    job.childRunIDs.append(run.id)
                }
            }
            persistJobs()
        }
    }

    /// Cohesive subtasks — run in order, each branching off the previous (so context
    /// accumulates), committing between steps. Only the LAST step does the on-green action,
    /// so the whole chain lands as ONE PR/merge. A failed step aborts the chain.
    private func dispatchSequential(_ job: Job, _ subtasks: [String]) {
        let repo = job.repoPath, verify = job.verifyCommand, finalMode = job.mergeMode, jid = job.id
        Task {
            var base = "HEAD"
            for (i, task) in subtasks.enumerated() {
                let isLast = i == subtasks.count - 1
                guard let run = try? await dispatch(repoPath: repo, task: task, verifyCommand: verify,
                                                    mergeMode: isLast ? finalMode : .none,
                                                    jobID: jid, base: base) else { break }
                job.childRunIDs.append(run.id)
                let result = await run.waitUntilDone()
                guard result == .succeeded else { job.status = .failed; persistJobs(); return }
                // Commit intermediate steps so the next run branches off the accumulated work.
                if !isLast { await commitWork(run) }
                base = run.branch
            }
            persistJobs()
        }
    }

    func removeJob(_ id: Job.ID) {
        guard let job = jobs.first(where: { $0.id == id }) else {
            jobHistory.removeAll { $0.id == id }; persistJobs(); return
        }
        let ids = [job.plannerRunID].compactMap { $0 } + job.childRunIDs
        for rid in ids { removeRun(rid) }
        jobs.removeAll { $0.id == id }
        jobHistory.removeAll { $0.id == id }
        persistJobs()
    }

    func job(for run: AgentRun) -> Job? {
        guard let jid = run.jobID else { return nil }
        return jobs.first { $0.id == jid }
    }

    // MARK: Resume

    /// Continue a finished run/record: re-run Claude with `--resume <sessionID>` in the SAME
    /// worktree, with a follow-up instruction. Adds more commits to the same branch.
    @discardableResult
    func resume(repoPath: String, branch: String, worktreePath: String, sessionID: String,
                followUp: String, jobID: UUID?) -> AgentRun? {
        guard FileManager.default.fileExists(atPath: worktreePath) else { return nil }
        AgentWorkspaceWindow.show()
        MCPConfig.wireWorktree(worktreePath)
        let run = AgentRun(task: followUp, kind: .claude, branch: branch, repoPath: repoPath,
                           worktreePath: worktreePath, startedAt: Date(), verifyCommand: nil,
                           mergeMode: .none, resumeSessionID: sessionID)
        run.jobID = jobID
        runs.insert(run, at: 0)
        selectedRunID = run.id
        pump()
        return run
    }

    /// Run an agent in an EXISTING worktree (no new branch) — used for feedback-driven fixes.
    @discardableResult
    func runInWorktree(repoPath: String, branch: String, worktreePath: String,
                       task: String, promptOverride: String) -> AgentRun {
        AgentWorkspaceWindow.show()
        MCPConfig.wireWorktree(worktreePath)
        let run = AgentRun(task: task, kind: .claude, branch: branch, repoPath: repoPath,
                           worktreePath: worktreePath, startedAt: Date(), mergeMode: .none,
                           promptOverride: promptOverride)
        runs.insert(run, at: 0)
        selectedRunID = run.id
        pump()
        return run
    }

    // MARK: History detail (rebuild worktree-backed workspace for old runs)

    private(set) var historyWorkspaces: [UUID: Workspace] = [:]

    /// Build (and cache) a Workspace from a finished record's on-disk worktree so the
    /// DiffPanel/Review/PR work on an old run. Call from selection, not during render.
    func prepareHistoryWorkspace(_ rec: RunRecord) {
        guard rec.worktreeExists, historyWorkspaces[rec.id] == nil else { return }
        let ws = Workspace(repoPath: rec.repoPath, branch: rec.branch, worktreePath: rec.worktreePath)
        historyWorkspaces[rec.id] = ws
        ws.refreshDiff()
    }

    // MARK: Unified run lookup (live run or history record)

    struct RunView: Identifiable, Sendable {
        let id: UUID
        let task: String
        let branch: String
        let status: RunStatus
        let insertions: Int
        let deletions: Int
        let isLive: Bool
    }

    func runView(_ id: UUID) -> RunView? {
        if let r = runs.first(where: { $0.id == id }) {
            return RunView(id: id, task: r.task, branch: r.branch, status: r.status,
                           insertions: r.workspace.diff.insertions, deletions: r.workspace.diff.deletions, isLive: true)
        }
        if let rec = history.first(where: { $0.id == id }) {
            return RunView(id: id, task: rec.task, branch: rec.branch, status: rec.status,
                           insertions: rec.insertions, deletions: rec.deletions, isLive: false)
        }
        return nil
    }

    func childViews(of job: Job) -> [RunView] { job.childRunIDs.compactMap { runView($0) } }

    /// Start as many queued runs as free slots allow (oldest first).
    func pump() {
        var free = config.maxConcurrent - runs.filter { $0.status.occupiesSlot }.count
        guard free > 0 else { return }
        for run in runs.reversed() where run.status == .queued {
            run.start()
            free -= 1
            if free == 0 { break }
        }
    }

    /// Post-green hook — P2 (merge queue) fills this in.
    func onRunSucceeded(_ run: AgentRun) async {
        switch run.mergeMode {
        case .none:
            break   // leave the worktree dirty for manual review + Commit
        case .pr:
            await commitWork(run); await openPR(run)
        case .merge:
            await commitWork(run); enqueueMerge(run)
        }
    }

    /// PR/merge need a real commit — agents only leave uncommitted working-tree changes.
    private func commitWork(_ run: AgentRun) async {
        let path = run.worktreePath
        let msg = String(run.task.prefix(72))
        let didCommit = await Task.detached { () -> Bool in
            guard !GitWorktrees.changedFiles(path).isEmpty else { return false }
            try? GitWorktrees.commit(path, message: msg)
            return true
        }.value
        if didCommit { run.events.append(RunEvent(icon: "checkmark.circle", text: "Committed changes")) }
        else { run.events.append(RunEvent(icon: "exclamationmark.circle", text: "No changes to commit")) }
    }

    // MARK: History

    func recordFinished(_ run: AgentRun) {
        let rec = RunRecord(id: run.id, task: run.task, agent: run.kind.rawValue, branch: run.branch,
                            repoPath: run.repoPath, worktreePath: run.worktreePath, status: run.status,
                            summary: run.summary, insertions: run.workspace.diff.insertions,
                            deletions: run.workspace.diff.deletions, files: run.workspace.diff.files,
                            startedAt: run.startedAt, endedAt: run.endedAt, verifyCommand: run.verifyCommand,
                            mergeMode: run.mergeMode, mergeOutcome: run.mergeOutcome, prURL: run.prURL,
                            jobID: run.jobID, sessionID: run.sessionID)
        if let idx = history.firstIndex(where: { $0.id == run.id }) { history[idx] = rec }
        else { history.insert(rec, at: 0) }
        persist()
        updateJobStatus(run.jobID)
    }

    /// A job is done once all its child runs have reached a terminal state.
    private func updateJobStatus(_ jobID: UUID?) {
        guard let jobID, let job = jobs.first(where: { $0.id == jobID }), job.status == .running,
              !job.childRunIDs.isEmpty else { return }
        let children = job.childRunIDs.compactMap { id in runs.first { $0.id == id }?.status ?? history.first { $0.id == id }?.status }
        if children.count == job.childRunIDs.count, children.allSatisfy({ $0.isTerminal }) {
            job.status = .done
            persistJobs()
        }
    }

    func removeRun(_ id: AgentRun.ID) {
        if let run = runs.first(where: { $0.id == id }) {
            run.cancel()
            let repo = run.repoPath, path = run.worktreePath
            if path != repo { Task.detached { GitWorktrees.remove(repoPath: repo, worktreePath: path) } }
            runs.removeAll { $0.id == id }
        } else if let rec = history.first(where: { $0.id == id }) {
            if rec.worktreePath != rec.repoPath {
                let repo = rec.repoPath, path = rec.worktreePath
                Task.detached { GitWorktrees.remove(repoPath: repo, worktreePath: path) }
            }
        }
        history.removeAll { $0.id == id }
        if selectedRunID == id { selectedRunID = runs.first?.id }
        persist()
        pump()
    }

    var historyOnly: [RunRecord] {
        let live = Set(runs.map(\.id))
        let inJobs = Set(jobs.flatMap { $0.childRunIDs } + jobs.compactMap { $0.plannerRunID })
        return history.filter { !live.contains($0.id) && !inJobs.contains($0.id) }
    }

    // MARK: Post-green actions (Refinery)

    func openPR(_ run: AgentRun) async {
        run.activity = "Opening PR…"
        run.events.append(RunEvent(icon: "arrow.triangle.pull.request", text: "Opening pull request…"))
        let path = run.worktreePath, branch = run.branch
        do {
            let out = try await Task.detached { try GitWorktrees.createPR(path, branch: branch) }.value
            let url = out.split(separator: "\n").last.map(String.init) ?? out
            run.prURL = url
            run.mergeOutcome = .prOpen
            run.events.append(RunEvent(icon: "checkmark.circle.fill", text: "PR opened: \(url)"))
        } catch {
            run.mergeOutcome = .failed
            run.events.append(RunEvent(icon: "exclamationmark.triangle", text: "PR failed: \(error)"))
        }
        recordFinished(run)
    }

    private var mergePending: [AgentRun.ID] = []
    private var merging = false

    func enqueueMerge(_ run: AgentRun) {
        mergePending.append(run.id)
        drainMergeQueue()
    }

    /// Serial merge — green branches merge into base one at a time so they never collide.
    private func drainMergeQueue() {
        guard !merging, let id = mergePending.first else { return }
        guard let run = runs.first(where: { $0.id == id }) else {
            mergePending.removeFirst(); drainMergeQueue(); return
        }
        merging = true
        run.activity = "Merging…"
        run.events.append(RunEvent(icon: "arrow.triangle.merge", text: "Merging into base branch…"))
        let repo = run.repoPath, branch = run.branch
        Task {
            let base = await Task.detached { GitWorktrees.defaultBranch(repo) }.value
            let result = await Task.detached { GitWorktrees.mergeIntoBase(repoPath: repo, branch: branch, base: base) }.value
            switch result {
            case .merged:
                run.mergeOutcome = .merged
                run.events.append(RunEvent(icon: "checkmark.circle.fill", text: "Merged into \(base)"))
            case .conflict:
                run.mergeOutcome = .conflict
                run.events.append(RunEvent(icon: "exclamationmark.triangle.fill", text: "Merge conflict with \(base) — needs attention"))
            case .failed(let msg):
                run.mergeOutcome = .failed
                run.events.append(RunEvent(icon: "xmark.octagon.fill", text: "Merge failed: \(msg)"))
            }
            recordFinished(run)
            mergePending.removeFirst()
            merging = false
            drainMergeQueue()
        }
    }

    // MARK: Branch naming

    private func uniqueBranch(for task: String) -> String {
        let base = "agent/" + GitWorktrees.sanitizeBranch(slug(task))
        let taken = Set(runs.map(\.branch) + history.map(\.branch))
        if !taken.contains(base) { return base }
        var n = 2
        while taken.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    private func slug(_ task: String) -> String {
        let words = task.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let joined = words.prefix(6).joined(separator: "-")
        return joined.isEmpty ? "run" : String(joined.prefix(40))
    }

    // MARK: Persistence

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let items = try? JSONDecoder().decode([RunRecord].self, from: data) { history = items }
        if let data = UserDefaults.standard.data(forKey: configKey),
           let cfg = try? JSONDecoder().decode(FactoryConfig.self, from: data) { config = cfg }
        if let data = UserDefaults.standard.data(forKey: jobsKey),
           let items = try? JSONDecoder().decode([JobRecord].self, from: data) {
            jobHistory = items
            // Rebuild live Jobs so old jobs group + link their children (a fresh id is fine —
            // children are found via childRunIDs, not a parent-id match).
            jobs = items.map { rec in
                let j = Job(goal: rec.goal, repoPath: rec.repoPath, verifyCommand: nil, mergeMode: .none, createdAt: rec.createdAt)
                j.status = rec.status; j.mode = rec.mode ?? .parallel
                j.subtasks = rec.subtasks; j.childRunIDs = rec.childRunIDs
                return j
            }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(history) { UserDefaults.standard.set(data, forKey: storeKey) }
    }

    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) { UserDefaults.standard.set(data, forKey: configKey) }
    }

    private func persistJobs() {
        let recs = jobs.map { JobRecord(id: $0.id, goal: $0.goal, repoPath: $0.repoPath, status: $0.status,
                                        subtasks: $0.subtasks, childRunIDs: $0.childRunIDs, createdAt: $0.createdAt, mode: $0.mode) }
        // keep prior-session job records that aren't live anymore
        let liveIDs = Set(jobs.map(\.id))
        let merged = recs + jobHistory.filter { !liveIDs.contains($0.id) }
        jobHistory = merged
        if let data = try? JSONEncoder().encode(merged) { UserDefaults.standard.set(data, forKey: jobsKey) }
    }
}

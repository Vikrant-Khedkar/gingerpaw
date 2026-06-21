import Foundation

public struct DiffStat: Sendable, Equatable {
    public var files: Int
    public var insertions: Int
    public var deletions: Int
    public static let zero = DiffStat(files: 0, insertions: 0, deletions: 0)
    public var isEmpty: Bool { files == 0 && insertions == 0 && deletions == 0 }
}

public struct FileChange: Sendable, Identifiable, Equatable {
    public var path: String
    public var insertions: Int
    public var deletions: Int
    public var status: String   // M, A, D, R, ? …
    public var id: String { path }
    public var dir: String { (path as NSString).deletingLastPathComponent }
    public var name: String { (path as NSString).lastPathComponent }
    public var isUntracked: Bool { status == "?" }
}

enum GitError: Error { case failed(String) }

/// Git worktree management — mirrors Superset's model: each workspace is a worktree
/// on its own branch, kept outside the main checkout under ~/.gingerpaw/worktrees.
enum GitWorktrees {
    static func root() -> String { NSHomeDirectory() + "/.gingerpaw/worktrees" }

    static func isGitRepo(_ path: String) -> Bool {
        ((try? run(["-C", path, "rev-parse", "--is-inside-work-tree"])) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    /// Best-effort scrub of a user-typed branch name into a legal-ish git ref:
    /// keep word chars + - _ . /, turn everything else into '-', collapse repeats,
    /// strip leading/trailing separators.
    static func sanitizeBranch(_ raw: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./")
        var s = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).map { allowed.contains($0) ? $0 : "-" })
        for pair in ["..": ".", "--": "-", "//": "/"] {
            while s.contains(pair.key) { s = s.replacingOccurrences(of: pair.key, with: pair.value) }
        }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "-/."))
    }

    /// Creates (or adopts) a worktree for `branch` off `repoPath`. Returns its path.
    static func create(repoPath: String, branch rawBranch: String) throws -> String {
        let branch = sanitizeBranch(rawBranch)
        guard !branch.isEmpty else { throw GitError.failed("Invalid branch name") }
        let repoName = (repoPath as NSString).lastPathComponent
        let projectRoot = (root() as NSString).appendingPathComponent(repoName)
        let dir = (projectRoot as NSString).appendingPathComponent(branch)
        // path-traversal guard
        guard URL(fileURLWithPath: dir).standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: projectRoot).standardizedFileURL.path) else {
            throw GitError.failed("Invalid branch path")
        }

        // Already a worktree on disk (e.g. from a prior unsaved session) — adopt it.
        if FileManager.default.fileExists(atPath: dir), isGitRepo(dir) { return dir }

        try? FileManager.default.createDirectory(
            atPath: (dir as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        _ = try? run(["-C", repoPath, "worktree", "prune"])

        let branchExists = (try? run(["-C", repoPath, "rev-parse", "--verify", "--quiet", branch])) != nil
        if branchExists {
            try run(["-C", repoPath, "worktree", "add", dir, branch])
        } else {
            try run(["-C", repoPath, "worktree", "add", "--no-track", "-b", branch, dir, "HEAD"])
        }
        return dir
    }

    static func remove(repoPath: String, worktreePath: String) {
        _ = try? run(["-C", repoPath, "worktree", "remove", "--force", worktreePath])
        _ = try? run(["-C", repoPath, "worktree", "prune"])
    }

    /// Changes vs HEAD in the worktree (tracked + staged). Drives the sidebar badge.
    static func diffStat(_ worktreePath: String) -> DiffStat {
        guard let out = try? run(["-C", worktreePath, "diff", "--shortstat", "HEAD"]) else { return .zero }
        // "3 files changed, 12 insertions(+), 4 deletions(-)"
        func num(_ suffix: String) -> Int {
            for part in out.components(separatedBy: ",") where part.contains(suffix) {
                let digits = part.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
            return 0
        }
        return DiffStat(files: num("file"), insertions: num("insertion"), deletions: num("deletion"))
    }

    /// Changed files vs HEAD (tracked, with +/− counts) plus untracked files.
    static func changedFiles(_ worktreePath: String) -> [FileChange] {
        var map: [String: FileChange] = [:]
        let numstat = runRaw(["-C", worktreePath, "diff", "--numstat", "HEAD"])
        for line in numstat.split(separator: "\n") {
            let cols = line.components(separatedBy: "\t")
            guard cols.count == 3 else { continue }
            map[cols[2]] = FileChange(path: cols[2], insertions: Int(cols[0]) ?? 0, deletions: Int(cols[1]) ?? 0, status: "M")
        }
        let status = runRaw(["-C", worktreePath, "status", "--porcelain"])
        for line in status.split(separator: "\n") {
            let s = String(line)
            guard s.count >= 3 else { continue }
            let code = String(s.prefix(2))
            let path = String(s.dropFirst(3))
            if code == "??" {
                map[path] = FileChange(path: path, insertions: untrackedLineCount(worktreePath, path), deletions: 0, status: "?")
            } else {
                let letter = code.replacingOccurrences(of: " ", with: "").first.map(String.init) ?? "M"
                if var existing = map[path] { existing.status = letter; map[path] = existing }
                else { map[path] = FileChange(path: path, insertions: 0, deletions: 0, status: letter) }
            }
        }
        return map.values.sorted { $0.path < $1.path }
    }

    private static func untrackedLineCount(_ worktreePath: String, _ path: String) -> Int {
        let full = (worktreePath as NSString).appendingPathComponent(path)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: full),
              let size = attrs[.size] as? Int, size > 0, size < 2_000_000,
              let content = try? String(contentsOfFile: full, encoding: .utf8), !content.isEmpty
        else { return 0 }
        return content.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    static func commit(_ worktreePath: String, message: String) throws {
        try run(["-C", worktreePath, "add", "-A"])
        try run(["-C", worktreePath, "commit", "-m", message])
    }

    static func fileDiff(_ worktreePath: String, file: FileChange) -> String {
        file.isUntracked
            ? runRaw(["-C", worktreePath, "diff", "--no-index", "--", "/dev/null", file.path])
            : runRaw(["-C", worktreePath, "diff", "HEAD", "--", file.path])
    }

    /// Like `run` but returns stdout regardless of exit code — `git diff` exits 1
    /// when there ARE differences, which isn't an error for our purposes.
    static func runRaw(_ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return "" }
        process.waitUntilExit()
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    @discardableResult
    static func run(_ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw GitError.failed(stderr.isEmpty ? "git \(args.joined(separator: " ")) failed" : stderr)
        }
        return stdout
    }
}

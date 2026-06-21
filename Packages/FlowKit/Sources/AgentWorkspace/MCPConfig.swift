import Foundation

/// Wires a worktree so agents launched inside it can reach GingerPaw's MCP server.
enum MCPConfig {
    static var cliPath: String {
        Bundle.main.url(forAuxiliaryExecutable: "gingerpaw-cli")?.path
            ?? (NSHomeDirectory() + "/.local/bin/gingerpaw-cli")
    }

    static func wireWorktree(_ worktreePath: String) {
        let cli = cliPath
        let json = """
        {
          "mcpServers": {
            "gingerpaw": { "command": "\(cli)", "args": ["mcp"] }
          }
        }
        """
        let dotMcp = (worktreePath as NSString).appendingPathComponent(".mcp.json")
        try? json.write(toFile: dotMcp, atomically: true, encoding: .utf8)
        addToExclude(worktreePath)
        ensureCodexConfig(cli: cli)
    }

    /// Keep .mcp.json out of the agent's diff / PR via git's exclude file
    /// (resolved correctly for linked worktrees via --git-path).
    private static func addToExclude(_ worktreePath: String) {
        var p = GitWorktrees.runRaw(["-C", worktreePath, "rev-parse", "--git-path", "info/exclude"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        if !p.hasPrefix("/") { p = (worktreePath as NSString).appendingPathComponent(p) }
        let existing = (try? String(contentsOfFile: p, encoding: .utf8)) ?? ""
        guard !existing.contains(".mcp.json") else { return }
        try? FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? (existing + (existing.isEmpty ? "" : "\n") + ".mcp.json\n").write(toFile: p, atomically: true, encoding: .utf8)
    }

    /// Codex is global-config, not per-project — register once in ~/.codex/config.toml.
    private static func ensureCodexConfig(cli: String) {
        let dir = NSHomeDirectory() + "/.codex"
        let path = dir + "/config.toml"
        let existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        guard !existing.contains("[mcp_servers.gingerpaw]") else { return }
        let block = "[mcp_servers.gingerpaw]\ncommand = \"\(cli)\"\nargs = [\"mcp\"]\n"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? (existing.isEmpty ? block : existing + "\n" + block).write(toFile: path, atomically: true, encoding: .utf8)
    }
}

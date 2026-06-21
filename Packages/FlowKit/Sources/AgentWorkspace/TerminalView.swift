import AppKit
import SwiftTerm
import SwiftUI

/// Embeds a real interactive terminal (a SwiftTerm PTY) running a login shell in
/// `directory`. Optionally `exec`s a command (e.g. an agent CLI) instead of the
/// shell. This is the linchpin of the agent-workspace feature — if `claude` runs
/// in here, everything else is layout on top.
public struct TerminalView: NSViewRepresentable {
    let directory: String
    let command: String?

    public init(directory: String, command: String? = nil) {
        self.directory = directory
        self.command = command
    }

    public func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        let envArray = env.map { "\($0.key)=\($0.value)" }

        // Outer login shell cd's into the worktree, then exec's the target so the
        // session has the user's full PATH (npm/brew installed agents resolve).
        let target = (command?.isEmpty == false) ? command! : "\(shell) -il"
        let line = "cd \(Self.quote(directory)) 2>/dev/null; exec \(target)"
        view.startProcess(executable: shell, args: ["-l", "-c", line], environment: envArray)
        return view
    }

    public func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}

    private static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

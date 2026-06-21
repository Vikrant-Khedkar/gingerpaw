import AppKit
import SwiftTerm
import SwiftUI

/// Creates a SwiftTerm PTY terminal running a login shell in `directory`, optionally
/// `exec`ing a command (an agent CLI). The login shell gives the session the user's
/// full PATH so npm/brew-installed agents resolve.
@MainActor
func makeTerminal(directory: String, command: String?) -> LocalProcessTerminalView {
    let view = LocalProcessTerminalView(frame: .zero)
    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

    var env = ProcessInfo.processInfo.environment
    env["TERM"] = "xterm-256color"
    if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
    let envArray = env.map { "\($0.key)=\($0.value)" }

    let args: [String] = (command?.isEmpty == false)
        ? ["-l", "-c", "exec \(command!)"]
        : ["-il"]
    view.startProcess(executable: shell, args: args, environment: envArray, currentDirectory: directory)
    return view
}

/// Hosts an already-created terminal so the PTY survives tab switches.
struct TerminalHostView: NSViewRepresentable {
    let terminal: LocalProcessTerminalView
    func makeNSView(context: Context) -> LocalProcessTerminalView { terminal }
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}

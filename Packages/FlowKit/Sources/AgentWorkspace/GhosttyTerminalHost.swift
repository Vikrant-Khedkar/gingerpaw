import AppKit
import GhosttyTerminal
import SwiftUI

// SPIKE: a Ghostty-backed terminal (GPU rendering) as a drop-in alternative to SwiftTerm's
// LocalProcessTerminalView. Uses the .exec backend (Ghostty spawns the shell in the worktree),
// then types the agent command. Text read for handoff/feedback → readSelection().

@MainActor
func makeGhosttyTerminal(directory: String, command: String?) -> TerminalView {
    let tv = TerminalView(frame: .zero)
    let controller = TerminalController { builder in
        builder.withBackgroundOpacity(0)
    }
    tv.controller = controller
    tv.configuration = TerminalSurfaceOptions(backend: .exec, workingDirectory: directory)
    if let c = command, !c.isEmpty {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            tv.sendText("exec \(c)\r")
        }
    }
    return tv
}

struct GhosttyHostView: NSViewRepresentable {
    let terminal: TerminalView
    var isSelected: Bool = true

    func makeNSView(context: Context) -> TerminalView { terminal }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        nsView.fitToSize()
        guard isSelected else { return }
        // Auto-focus the selected terminal so typing lands without a click.
        DispatchQueue.main.async {
            guard let window = nsView.window, window.firstResponder !== nsView else { return }
            window.makeFirstResponder(nsView)
        }
    }
}

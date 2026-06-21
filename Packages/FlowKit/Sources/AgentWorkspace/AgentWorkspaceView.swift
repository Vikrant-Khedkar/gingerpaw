import SwiftUI

/// Phase 0 spike: a single embedded terminal in the home directory. Type `claude`,
/// `codex`, `gemini`, or `cursor-agent` to prove agents run in-app. Tabs, worktrees,
/// and the diff panel come in later phases.
public struct AgentWorkspaceView: View {
    private let directory: String

    public init(directory: String? = nil) {
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser.path
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                Text("Agent Workspace").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(directory).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.background.secondary)

            TerminalView(directory: directory)
        }
        .frame(minWidth: 520, minHeight: 340)
    }
}

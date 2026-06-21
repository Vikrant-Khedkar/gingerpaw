import AppKit
import SwiftUI

/// The Agent Workspace window: a sidebar of workspaces (each a git worktree on its
/// own branch, with a live diff badge) and, for the selected one, a tab bar of agent
/// sessions running inside its isolated worktree.
struct WorkspaceRootView: View {
    @State private var model = WorkspaceModel()
    @State private var showingNew = false
    @State private var newRepoPath = ""
    @State private var newBranch = "agent/work"
    @State private var newAgent: AgentKind = .claude
    @State private var creating = false
    @State private var errorMessage: String?
    @State private var showDiff = true

    private let diffTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 200, idealWidth: 230, maxWidth: 300)
            main.frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, minHeight: 520)
        .onAppear { model.refreshInstalled() }
        .onReceive(diffTimer) { _ in model.selectedWorkspace?.refreshDiff() }
        .sheet(isPresented: $showingNew) { newSheet }
        .alert("Couldn't create workspace",
               isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Workspaces").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    newRepoPath = ""
                    newBranch = "agent/work-\(model.workspaces.count + 1)"
                    newAgent = AgentKind.allCases.first { model.installed.contains($0) } ?? .claude
                    showingNew = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            Divider()

            if model.workspaces.isEmpty {
                VStack(spacing: 6) {
                    Text("No workspaces").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("Create one with  +").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(get: { model.selectedWorkspaceID },
                                        set: { model.selectedWorkspaceID = $0 })) {
                    ForEach(model.workspaces) { ws in
                        workspaceRow(ws)
                            .tag(ws.id)
                            .contextMenu {
                                Button("Remove Workspace", role: .destructive) { model.removeWorkspace(ws.id) }
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .background(.background.secondary)
    }

    private func workspaceRow(_ ws: Workspace) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ws.repoName).font(.system(size: 13, weight: .medium)).lineLimit(1)
            HStack(spacing: 6) {
                Text(ws.branch).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if !ws.diff.isEmpty {
                    Text("+\(ws.diff.insertions)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.green)
                    Text("−\(ws.diff.deletions)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Main

    @ViewBuilder private var main: some View {
        if let ws = model.selectedWorkspace {
            HSplitView {
                VStack(spacing: 0) {
                    tabBar(ws)
                    Divider()
                    terminalArea(ws)
                }
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)

                if showDiff {
                    DiffPanel(workspace: ws)
                        .frame(minWidth: 260, idealWidth: 320, maxWidth: 480)
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "square.split.2x1").font(.system(size: 38)).foregroundStyle(.secondary)
                Text("Create a workspace to start").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func tabBar(_ ws: Workspace) -> some View {
        HStack(spacing: 6) {
            ForEach(ws.sessions) { sessionTab(ws, $0) }
            addMenu(ws)
            Spacer()
            Button { showDiff.toggle() } label: {
                Image(systemName: "sidebar.right")
                    .foregroundStyle(showDiff ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help(showDiff ? "Hide changes panel" : "Show changes panel")
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(.background.secondary)
    }

    private func sessionTab(_ ws: Workspace, _ session: AgentSession) -> some View {
        let selected = ws.selectedSessionID == session.id
        return HStack(spacing: 6) {
            Image(session.kind.logo).resizable().frame(width: 14, height: 14)
            Text(session.kind.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            Button { ws.closeSession(session.id) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(selected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { ws.selectedSessionID = session.id }
    }

    private func addMenu(_ ws: Workspace) -> some View {
        Menu {
            ForEach(AgentKind.allCases) { kind in
                let installed = model.installed.contains(kind)
                Button { ws.openSession(kind) } label: {
                    Label {
                        Text(installed ? kind.title : "\(kind.title) — not installed")
                    } icon: {
                        Self.agentIcon(kind)
                    }
                }
                .disabled(!installed)
            }
        } label: {
            Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    @ViewBuilder private func terminalArea(_ ws: Workspace) -> some View {
        if ws.sessions.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "terminal").font(.system(size: 38)).foregroundStyle(.secondary)
                Text("Open an agent session with  +").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                ForEach(ws.sessions) { session in
                    TerminalHostView(terminal: session.terminal)
                        .opacity(session.id == ws.selectedSessionID ? 1 : 0)
                        .allowsHitTesting(session.id == ws.selectedSessionID)
                }
            }
        }
    }

    // MARK: New workspace sheet

    private var newSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Workspace").font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Repository").font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    Text(newRepoPath.isEmpty ? "Choose a git repo…" : newRepoPath)
                        .font(.system(size: 12))
                        .foregroundStyle(newRepoPath.isEmpty ? .secondary : .primary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Browse…") { if let p = pickRepo() { newRepoPath = p } }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Branch").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("agent/work", text: $newBranch).textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Agent").font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(AgentKind.allCases) { kind in
                        let installed = model.installed.contains(kind)
                        Button { newAgent = kind } label: {
                            HStack(spacing: 6) {
                                Image(kind.logo).resizable().frame(width: 16, height: 16)
                                Text(kind.title).font(.system(size: 12))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(newAgent == kind ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 6))
                            .opacity(installed ? 1 : 0.4)
                        }
                        .buttonStyle(.plain)
                        .disabled(!installed)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { showingNew = false }
                Button(creating ? "Creating…" : "Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newRepoPath.isEmpty
                        || newBranch.trimmingCharacters(in: .whitespaces).isEmpty
                        || !model.installed.contains(newAgent)
                        || creating)
            }
        }
        .padding(20).frame(width: 460)
    }

    private func create() {
        creating = true
        let repo = newRepoPath, branch = newBranch
        let agent = newAgent
        Task {
            do {
                try await model.createWorkspace(repoPath: repo, branch: branch)
                model.selectedWorkspace?.openSession(agent)
                creating = false
                showingNew = false
            } catch {
                creating = false
                errorMessage = "\(error)"
            }
        }
    }

    /// Asset logos render at native (huge) size inside a SwiftUI Menu unless the
    /// NSImage carries an explicit point size — so hand the menu a resized copy.
    static func agentIcon(_ kind: AgentKind) -> Image {
        guard let base = NSImage(named: kind.logo), let copy = base.copy() as? NSImage else {
            return Image(systemName: "terminal")
        }
        copy.size = NSSize(width: 16, height: 16)
        return Image(nsImage: copy)
    }

    private func pickRepo() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "Select Repo"
        guard panel.runModal() == .OK, let path = panel.url?.path else { return nil }
        guard GitWorktrees.isGitRepo(path) else { errorMessage = "Not a git repository:\n\(path)"; return nil }
        return path
    }
}

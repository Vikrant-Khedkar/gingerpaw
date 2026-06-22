import AppKit
import SwiftUI

enum WorkspaceSection { case workspaces, runs }

/// Agent Workspace — "Trail" layout: icon rail · workspaces sidebar · tabbed
/// terminal + status bar · docked Files/Diff panel.
struct WorkspaceRootView: View {
    @State private var model = WorkspaceModel.shared
    @State private var section: WorkspaceSection = .workspaces
    @State private var showingNew = false
    @State private var newRepoPath = ""
    @State private var newBranch = "agent/work"
    @State private var newAgent: AgentKind = .claude
    @State private var newRepoCurrentBranch = ""
    @State private var newPlain = false
    @State private var creating = false
    @State private var errorMessage: String?
    @State private var showDiff = true
    @State private var hoveredWorkspaceID: Workspace.ID?
    @State private var pendingRemoval: Workspace?
    @State private var showingHandoff = false
    @State private var handoffSize = 0
    @State private var handoffLastSize = -1
    @State private var handoffReady = false
    @State private var pendingHandoff: PendingHandoff?
    @State private var handoffWaited = 0
    @State private var handoffHover = false

    enum PendingHandoff: Equatable { case spawn(AgentKind); case copy(Bool) }

    private let diffTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()
    private let handoffTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            HStack(spacing: 0) {
                iconRail
                switch section {
                case .workspaces:
                    HSplitView {
                        sidebar.frame(minWidth: 210, idealWidth: 248, maxWidth: 300)
                        main.frame(minWidth: 440, maxWidth: .infinity)
                        if showDiff, let ws = model.selectedWorkspace {
                            DiffPanel(workspace: ws).frame(minWidth: 280, idealWidth: 320, maxWidth: 480)
                        }
                    }
                case .runs:
                    RunsView()
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 900, minHeight: 560)
        .background(WS.bg)
        .background { keyboardShortcuts }
        .preferredColorScheme(.dark)
        .onAppear { model.refreshInstalled() }
        .onReceive(diffTimer) { _ in model.selectedWorkspace?.refreshDiff() }
        .onReceive(handoffTimer) { _ in if showingHandoff { pollHandoff() } }
        .sheet(isPresented: $showingNew) { newSheet }
        .sheet(isPresented: $showingHandoff) { handoffSheet }
        .alert("Something went wrong",
               isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .alert("Remove workspace?",
               isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
               presenting: pendingRemoval) { ws in
            Button("Remove", role: .destructive) { model.removeWorkspace(ws.id); pendingRemoval = nil }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { ws in
            Text(ws.isMainCheckout
                 ? "Removes “\(ws.repoName)” from the sidebar. Its sessions close; your repo and branch stay untouched."
                 : "Closes all sessions and deletes the worktree for “\(ws.repoName)” (\(ws.branch)). Uncommitted changes there will be lost.")
        }
    }

    // MARK: Titlebar

    private var titleBar: some View {
        ZStack {
            HStack(spacing: 8) {
                Image(systemName: "pawprint.fill").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: 0x1a1208))
                    .frame(width: 20, height: 20)
                    .background(LinearGradient(colors: [WS.accent, Color(hex: 0xd96a2a)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 6))
                Text("gingerpaw").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0xe9e9ec))
            }
            HStack {
                Spacer()
                Button { showDiff.toggle() } label: {
                    Image(systemName: "sidebar.right").font(.system(size: 14))
                        .foregroundStyle(showDiff ? WS.accent : WS.textSecondary)
                        .frame(width: 26, height: 24)
                        .background(showDiff ? WS.accentSubtle : .clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain).padding(.trailing, 14)
            }
        }
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .background(WS.titlebar)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.4)).frame(height: 1) }
    }

    // MARK: Icon rail

    private var iconRail: some View {
        VStack(spacing: 4) {
            railIcon("rectangle.stack", active: section == .workspaces) { section = .workspaces }
            railIcon("bolt.horizontal.fill", active: section == .runs) { section = .runs }
            Spacer()
            railIcon("gearshape", active: false) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
        .padding(.vertical, 12)
        .frame(width: 52)
        .frame(maxHeight: .infinity)
        .background(WS.rail)
        .overlay(alignment: .trailing) { Rectangle().fill(WS.border).frame(width: 1) }
    }

    /// Rail icon — the selected one gets the ShaderGlow plasma behind it.
    private func railIcon(_ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(active ? .white : WS.textTertiary)
                .shadow(color: active ? .black.opacity(0.45) : .clear, radius: 1.5, y: 0.5)
                .frame(width: 36, height: 36)
                .background {
                    if active {
                        ShaderGlow()
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.18)))
                    }
                }
                .overlay(alignment: .leading) {
                    if active { Capsule().fill(WS.accent).frame(width: 3, height: 18).offset(x: -8) }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("WORKSPACES").font(.system(size: 10.5, weight: .bold)).tracking(1.4).foregroundStyle(WS.label)
                Spacer()
                Button { openNewWorkspace() } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .semibold)).foregroundStyle(WS.textSecondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

            if model.workspaces.isEmpty {
                VStack(spacing: 4) {
                    Text("No workspaces yet").font(.system(size: 13)).foregroundStyle(WS.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.workspaces) { workspaceRow($0) }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(WS.panel)
        .overlay(alignment: .trailing) { Rectangle().fill(WS.border).frame(width: 1) }
    }

    private func workspaceRow(_ ws: Workspace) -> some View {
        let selected = model.selectedWorkspaceID == ws.id
        let hovered = hoveredWorkspaceID == ws.id
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(ws.repoName).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? WS.textPrimary : Color(hex: 0xd7d8db)).lineLimit(1)
                Spacer(minLength: 6)
                if hovered {
                    Button { pendingRemoval = ws } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(WS.textSecondary)
                            .frame(width: 17, height: 17).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain).help("Remove workspace")
                } else if !ws.sessions.isEmpty {
                    Circle().fill(WS.accent).frame(width: 7, height: 7)
                        .overlay(Circle().stroke(WS.accent.opacity(0.25), lineWidth: 3))
                }
            }
            HStack(spacing: 6) {
                Text(ws.branch).font(WS.mono(11)).foregroundStyle(selected ? WS.textSecondary : WS.textTertiary).lineLimit(1)
                Spacer(minLength: 6)
                diffBadge(ws.diff)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(selected ? WS.rowSelected : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture { model.selectedWorkspaceID = ws.id }
        .onHover { hoveredWorkspaceID = $0 ? ws.id : (hoveredWorkspaceID == ws.id ? nil : hoveredWorkspaceID) }
        .contextMenu {
            Button("Remove Workspace", role: .destructive) { pendingRemoval = ws }
        }
    }

    @ViewBuilder private func diffBadge(_ d: DiffStat) -> some View {
        if d.isEmpty {
            Text("clean").font(.system(size: 10.5)).foregroundStyle(WS.textDim)
        } else {
            HStack(spacing: 4) {
                Text("+\(d.insertions)").foregroundStyle(WS.add)
                Text("−\(d.deletions)").foregroundStyle(d.deletions > 0 ? WS.del : WS.textTertiary)
            }.font(WS.mono(10.5))
        }
    }

    // MARK: Main column

    @ViewBuilder private var main: some View {
        if let ws = model.selectedWorkspace {
            VStack(spacing: 0) {
                tabBar(ws)
                if ws.sessions.isEmpty { noSession(ws) } else { terminalArea(ws) }
                statusBar(ws)
            }
            .background(WS.bg)
        } else {
            firstRun
        }
    }

    private func tabBar(_ ws: Workspace) -> some View {
        HStack(spacing: 0) {
            ForEach(ws.sessions) { sessionTab(ws, $0) }
            addMenu(ws)
            Spacer()
            if currentSession(ws) != nil {
                Button { openHandoff() } label: {
                    HStack(spacing: 5) {
                        ZStack {
                            Image("two-hands").renderingMode(.template).resizable().frame(width: 13, height: 13)
                                .foregroundStyle(WS.textSecondary).opacity(handoffHover ? 0 : 1)
                            if handoffHover {
                                ShaderGlow().frame(width: 13, height: 13)
                                    .mask(Image("two-hands").renderingMode(.template).resizable().frame(width: 13, height: 13))
                            }
                        }
                        .frame(width: 13, height: 13)
                        Text("Handoff").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(WS.textSecondary)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain).help("Hand off this session's context to another agent").padding(.trailing, 4)
                .onHover { handoffHover = $0 }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(WS.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(WS.border).frame(height: 1) }
    }

    private func sessionTab(_ ws: Workspace, _ session: AgentSession) -> some View {
        let selected = ws.selectedSessionID == session.id
        return HStack(spacing: 8) {
            Group {
                if let logo = session.kind?.logo {
                    Image(logo).resizable().frame(width: 14, height: 14)
                } else {
                    Image(systemName: "terminal").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WS.textSecondary).frame(width: 14, height: 14)
                }
            }
            .padding(2).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
            Text(session.title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? WS.textPrimary : WS.textSecondary).lineLimit(1)
            Button { ws.closeSession(session.id) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(WS.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .overlay(alignment: .bottom) {
            if selected { Rectangle().fill(WS.accent).frame(height: 2) }
        }
        .contentShape(Rectangle())
        .onTapGesture { ws.selectedSessionID = session.id }
    }

    private func addMenu(_ ws: Workspace) -> some View {
        Menu {
            ForEach(AgentKind.allCases) { kind in
                let installed = model.installed.contains(kind)
                Button { ws.openSession(kind) } label: {
                    Label { Text(installed ? kind.title : "\(kind.title) — not installed") } icon: { Self.agentIcon(kind) }
                }
                .disabled(!installed)
            }
            Divider()
            ForEach(AgentKind.allCases.filter { $0.continueCommand != nil }) { kind in
                Button { ws.resumeSession(kind) } label: {
                    Label { Text("Resume \(kind.title)") } icon: { Image(systemName: "arrow.clockwise") }
                }
                .disabled(!model.installed.contains(kind))
            }
            Button { ws.openTerminal() } label: {
                Label { Text("Terminal") } icon: { Image(systemName: "terminal") }
            }
        } label: {
            Image(systemName: "plus").font(.system(size: 14, weight: .semibold)).foregroundStyle(WS.textSecondary)
                .frame(width: 26, height: 26).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    private func terminalArea(_ ws: Workspace) -> some View {
        ZStack {
            ForEach(ws.sessions) { session in
                TerminalHostView(terminal: session.terminal)
                    .opacity(session.id == ws.selectedSessionID ? 1 : 0)
                    .allowsHitTesting(session.id == ws.selectedSessionID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusBar(_ ws: Workspace) -> some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(ws.branches, id: \.self) { b in
                    Button { ws.switchBranch(b) } label: {
                        if b == ws.currentBranch { Label(b, systemImage: "checkmark") } else { Text(b) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 10))
                    Text(ws.currentBranch).font(WS.mono(11))
                }
                .foregroundStyle(WS.textSecondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            diffBadge(ws.diff)
            ForEach(ws.ports, id: \.self) { port in
                HStack(spacing: 5) {
                    Circle().fill(WS.add).frame(width: 6, height: 6)
                    Text(":\(port)").font(WS.mono(11)).foregroundStyle(WS.textSecondary)
                }
            }
            Spacer()
            if ws.ahead > 0 || ws.behind > 0 {
                Text("↑\(ws.ahead) ↓\(ws.behind)").font(WS.mono(11)).foregroundStyle(WS.textTertiary)
            }
            Button { createPR(ws) } label: {
                HStack(spacing: 5) {
                    if ws.creatingPR { ProgressView().controlSize(.mini) }
                    else { Image(systemName: "arrow.triangle.branch").font(.system(size: 10, weight: .semibold)) }
                    Text(ws.creatingPR ? "Creating…" : "Create PR").font(WS.mono(11))
                }
                .foregroundStyle(WS.accent)
                .padding(.horizontal, 9).padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(WS.accent.opacity(0.45)))
            }
            .buttonStyle(.plain).disabled(ws.creatingPR)
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(WS.bar)
        .overlay(alignment: .top) { Rectangle().fill(WS.border).frame(height: 1) }
    }

    private func createPR(_ ws: Workspace) {
        Task {
            switch await ws.createPR() {
            case .success(let url):
                if let u = URL(string: url.split(separator: "\n").last.map(String.init) ?? url) { NSWorkspace.shared.open(u) }
            case .failure(let err):
                errorMessage = "Couldn't create PR:\n\(err)"
            }
        }
    }

    private func noSession(_ ws: Workspace) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "terminal").font(.system(size: 26))
                .foregroundStyle(Color(hex: 0x3f4148))
                .frame(width: 54, height: 54).background(Color(hex: 0x17181c), in: RoundedRectangle(cornerRadius: 14))
                .padding(.bottom, 8)
            Text("No agent session yet").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(hex: 0xd7d8db))
            Text("Sessions share this workspace's worktree. Resume your last conversation, or start fresh.")
                .font(.system(size: 12.5)).foregroundStyle(WS.textTertiary).multilineTextAlignment(.center).frame(maxWidth: 300)

            ForEach(AgentKind.allCases.filter { $0.continueCommand != nil && model.installed.contains($0) }) { kind in
                Button { ws.resumeSession(kind) } label: {
                    Label("Resume \(kind.title)", systemImage: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(PrimaryButtonStyle()).padding(.top, 10)
            }

            Text("START FRESH").font(.system(size: 9.5, weight: .bold)).tracking(1.2).foregroundStyle(WS.textDim).padding(.top, 6)
            HStack(spacing: 8) {
                ForEach(AgentKind.allCases.filter { model.installed.contains($0) }) { kind in
                    Button { ws.openSession(kind) } label: {
                        Image(kind.logo).resizable().frame(width: 15, height: 15)
                            .padding(8).background(Color(hex: 0x1a1b1f), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain).help("New \(kind.title) session")
                }
                Button { ws.openTerminal() } label: {
                    Image(systemName: "terminal").font(.system(size: 14)).foregroundStyle(WS.textSecondary)
                        .frame(width: 31, height: 31).background(Color(hex: 0x1a1b1f), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1)))
                }
                .buttonStyle(.plain).help("Plain terminal")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var firstRun: some View {
        VStack(spacing: 6) {
            Image(systemName: "pawprint.fill").font(.system(size: 30))
                .foregroundStyle(Color(hex: 0x1a1208))
                .frame(width: 60, height: 60)
                .background(LinearGradient(colors: [WS.accent, Color(hex: 0xd96a2a)], startPoint: .topLeading, endPoint: .bottomTrailing),
                           in: RoundedRectangle(cornerRadius: 16))
                .padding(.bottom, 10)
            Text("Create your first workspace").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color(hex: 0xe9e9ec))
            Text("Pick a repo and a branch — gingerpaw spins up an isolated git worktree, then launches your chosen agent inside it.")
                .font(.system(size: 13)).foregroundStyle(WS.textTertiary).multilineTextAlignment(.center).frame(maxWidth: 360)
            Button { openNewWorkspace() } label: {
                Label("New Workspace", systemImage: "plus").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(PrimaryButtonStyle()).padding(.top, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WS.bg)
    }

    // MARK: New workspace sheet

    private var newSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(WS.accent)
                    .frame(width: 26, height: 26).background(WS.accentSubtle, in: RoundedRectangle(cornerRadius: 8))
                Text("New Workspace").font(.system(size: 15, weight: .semibold)).foregroundStyle(WS.textPrimary)
            }

            field("Mode") {
                HStack(spacing: 8) {
                    modeSegment("New branch", subtitle: "isolated worktree", icon: "arrow.triangle.branch", selected: !newPlain) { newPlain = false }
                    modeSegment("This folder", subtitle: "work in place", icon: "folder", selected: newPlain) { newPlain = true }
                }
                Text(newPlain
                     ? "Runs the agent directly in the chosen folder — no worktree, no branch. Use for a root with sub-repos or to edit a repo in place."
                     : "Creates an isolated git worktree on a new branch. Requires a git repo.")
                    .font(.system(size: 11)).foregroundStyle(WS.textDim)
            }

            field(newPlain ? "Folder" : "Repository") {
                HStack(spacing: 8) {
                    Text(newRepoPath.isEmpty ? (newPlain ? "Choose a folder…" : "Choose a git repo…") : newRepoPath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(WS.mono(12)).foregroundStyle(newRepoPath.isEmpty ? WS.textTertiary : Color(hex: 0xd7d8db))
                        .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9).background(Color(hex: 0x1a1b1f), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1)))
                    Button("Browse…") {
                        if let p = pickRepo(requireGit: !newPlain) { newRepoPath = p; newRepoCurrentBranch = GitWorktrees.currentBranch(p) }
                    }.buttonStyle(SecondaryButtonStyle())
                }
            }

            if !newPlain {
                field("Branch") {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("agent/work", text: $newBranch)
                            .textFieldStyle(.plain).font(WS.mono(12)).foregroundStyle(WS.textPrimary)
                            .padding(9).background(Color(hex: 0x1a1b1f), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(WS.accent.opacity(0.5)))
                        if !newRepoCurrentBranch.isEmpty && newBranch != newRepoCurrentBranch {
                            Button { newBranch = newRepoCurrentBranch } label: {
                                Text("↩ use current branch (\(newRepoCurrentBranch)) — work in the repo directly")
                                    .font(.system(size: 11)).foregroundStyle(WS.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            field("Agent") {
                HStack(spacing: 8) {
                    ForEach(AgentKind.allCases) { kind in
                        let installed = model.installed.contains(kind)
                        Button { newAgent = kind } label: {
                            HStack(spacing: 7) {
                                Image(kind.logo).resizable().frame(width: 14, height: 14)
                                Text(kind.title).font(.system(size: 12.5))
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .foregroundStyle(newAgent == kind ? WS.textPrimary : Color(hex: 0xd7d8db))
                            .background(newAgent == kind ? WS.accentSubtle : Color(hex: 0x1a1b1f), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(newAgent == kind ? WS.accent.opacity(0.6) : .white.opacity(0.1)))
                            .opacity(installed ? 1 : 0.4)
                        }
                        .buttonStyle(.plain).disabled(!installed)
                    }
                }
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { showingNew = false }.buttonStyle(.plain).foregroundStyle(Color(hex: 0xd7d8db))
                Button(creating ? "Creating…" : "Create") { create() }
                    .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                    .disabled(newRepoPath.isEmpty || (!newPlain && newBranch.trimmingCharacters(in: .whitespaces).isEmpty) || !model.installed.contains(newAgent) || creating)
            }
            .padding(.top, 4)
        }
        .padding(22).frame(width: 460).background(Color(hex: 0x26272d))
    }

    private func modeSegment(_ title: String, subtitle: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(selected ? WS.accent : WS.textTertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(selected ? WS.textPrimary : Color(hex: 0xd7d8db))
                    Text(subtitle).font(.system(size: 10.5)).foregroundStyle(WS.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? WS.accentSubtle : Color(hex: 0x1a1b1f), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? WS.accent.opacity(0.6) : .white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    private func field<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(WS.textSecondary)
            content()
        }
    }

    private func openNewWorkspace() {
        newRepoPath = ""
        newRepoCurrentBranch = ""
        newPlain = false
        newBranch = "agent/work-\(model.workspaces.count + 1)"
        newAgent = AgentKind.allCases.first { model.installed.contains($0) } ?? .claude
        showingNew = true
    }

    private var keyboardShortcuts: some View {
        Group {
            Button("") { openNewWorkspace() }.keyboardShortcut("n", modifiers: .command)
            Button("") {
                if let ws = model.selectedWorkspace, let a = AgentKind.allCases.first(where: { model.installed.contains($0) }) {
                    ws.openSession(a)
                }
            }.keyboardShortcut("t", modifiers: .command)
        }
        .frame(width: 0, height: 0).opacity(0)
    }

    private func create() {
        creating = true
        let repo = newRepoPath, branch = newBranch, agent = newAgent, plain = newPlain
        Task {
            do {
                try await model.createWorkspace(repoPath: repo, branch: branch, plain: plain)
                model.selectedWorkspace?.openSession(agent)
                creating = false; showingNew = false
            } catch { creating = false; errorMessage = "\(error)" }
        }
    }

    // MARK: Handoff

    private func currentSession(_ ws: Workspace) -> AgentSession? {
        ws.sessions.first { $0.id == ws.selectedSessionID }
    }

    private func openHandoff() {
        handoffSize = 0; handoffLastSize = -1; handoffReady = false; pendingHandoff = nil
        showingHandoff = true
    }

    /// Begin a handoff: clear any old file, ask the current agent to write a fresh one,
    /// and remember what to do once it lands. Polling (every 1.5s) finishes the job.
    private func startHandoff(_ action: PendingHandoff) {
        guard let ws = model.selectedWorkspace, let session = currentSession(ws) else { return }
        try? FileManager.default.removeItem(atPath: Handoff.path(ws.worktreePath))
        handoffReady = false; handoffLastSize = -1; handoffSize = 0; handoffWaited = 0
        pendingHandoff = action
        session.sendPrompt(Handoff.authorPrompt)
    }

    private func pollHandoff() {
        guard let ws = model.selectedWorkspace else { return }
        if pendingHandoff != nil { handoffWaited += 1 }
        let s = Handoff.status(ws.worktreePath)
        handoffSize = s.size
        if s.exists, s.size > 0, s.size == handoffLastSize { handoffReady = true }
        handoffLastSize = s.size

        if handoffReady, let action = pendingHandoff {
            pendingHandoff = nil
            switch action {
            case .spawn(let kind): ws.openSession(kind, prompt: Handoff.continuePrompt)
            case .copy(let diff): copyHandoff(ws, withDiff: diff)
            }
            showingHandoff = false
        }
    }

    private func copyHandoff(_ ws: Workspace, withDiff: Bool) {
        guard let content = Handoff.read(ws.worktreePath) else { return }
        var text = "Continue this work. Context from the previous agent:\n\n" + content
        if withDiff { text += "\n\n## Current diff\n```diff\n" + GitWorktrees.fullDiff(ws.worktreePath) + "\n```" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @ViewBuilder private var handoffSheet: some View {
        if let ws = model.selectedWorkspace, let session = currentSession(ws) {
            let working = pendingHandoff != nil
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 9) {
                    Image("two-hands").renderingMode(.template).resizable().frame(width: 15, height: 15).foregroundStyle(WS.accent)
                        .frame(width: 26, height: 26).background(WS.accentSubtle, in: RoundedRectangle(cornerRadius: 8))
                    Text("Hand off \(session.title)").font(.system(size: 15, weight: .semibold)).foregroundStyle(WS.textPrimary)
                }
                Text("The next agent shares this worktree, so it already has the code. \(session.title) writes the intent to HANDOFF.md, then the chosen agent picks it up — automatically.")
                    .font(.system(size: 11.5)).foregroundStyle(WS.textTertiary)

                field("Continue in") {
                    HStack(spacing: 8) {
                        ForEach(AgentKind.allCases) { kind in
                            Button { startHandoff(.spawn(kind)) } label: {
                                HStack(spacing: 6) { Image(kind.logo).resizable().frame(width: 13, height: 13); Text(kind.title).font(.system(size: 12)) }
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Color(hex: 0x1a1b1f), in: RoundedRectangle(cornerRadius: 7))
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.1)))
                            }
                            .buttonStyle(.plain).disabled(working || !model.installed.contains(kind))
                            .opacity(!working && model.installed.contains(kind) ? 1 : 0.4)
                        }
                    }
                }

                if working {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text("Asking \(session.title) to write HANDOFF.md…").font(.system(size: 11.5)).foregroundStyle(WS.textTertiary)
                        }
                        if handoffWaited > 8 {
                            Text("If the prompt is sitting unsent in the terminal, press Enter to submit it.")
                                .font(.system(size: 11)).foregroundStyle(WS.del)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button("Copy") { startHandoff(.copy(false)) }.buttonStyle(SecondaryButtonStyle()).disabled(working)
                    Button("Copy + diff") { startHandoff(.copy(true)) }.buttonStyle(SecondaryButtonStyle()).disabled(working)
                    Text("to paste into a Claude open elsewhere").font(.system(size: 10.5)).foregroundStyle(WS.textDim)
                    Spacer()
                    Button(working ? "Cancel" : "Done") { pendingHandoff = nil; showingHandoff = false }
                        .buttonStyle(.plain).foregroundStyle(Color(hex: 0xd7d8db))
                }
            }
            .padding(22).frame(width: 500).background(Color(hex: 0x26272d))
        }
    }

    static func agentIcon(_ kind: AgentKind) -> Image {
        guard let base = NSImage(named: kind.logo), let copy = base.copy() as? NSImage else { return Image(systemName: "terminal") }
        copy.size = NSSize(width: 16, height: 16)
        return Image(nsImage: copy)
    }

    private func pickRepo(requireGit: Bool = true) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "Select"
        guard panel.runModal() == .OK, let path = panel.url?.path else { return nil }
        if requireGit, !GitWorktrees.isGitRepo(path) { errorMessage = "Not a git repository:\n\(path)"; return nil }
        return path
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(configuration.isPressed ? WS.accentBtnHover : WS.accentBtn, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5)).foregroundStyle(Color(hex: 0xe9e9ec))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color(hex: configuration.isPressed ? 0x3d3e46 : 0x34353c), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1)))
    }
}

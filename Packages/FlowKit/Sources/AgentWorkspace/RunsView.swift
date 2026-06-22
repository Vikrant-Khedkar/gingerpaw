import AppKit
import SwiftUI

/// The dedicated Runs section: a dispatch dashboard (left), the selected run's live
/// activity feed (center), and its diff for review/PR (right). Headless agents only.
struct RunsView: View {
    @State private var runs = RunsModel.shared
    @State private var model = WorkspaceModel.shared
    @State private var selectedID: UUID?
    @State private var showingNew = false
    @State private var newRepoPath = ""
    @State private var newTask = ""
    @State private var newVerify = ""
    @State private var newMergeMode: MergeMode = .none
    @State private var creating = false
    @State private var errorMessage: String?
    @State private var hoveredID: UUID?
    @State private var pendingRemoval: UUID?
    @State private var selectedJobID: UUID?
    @State private var showingNewJob = false
    @State private var newGoal = ""
    @State private var pendingJobRemoval: UUID?
    @State private var resumeTarget: ResumeTarget?
    @State private var followUp = ""

    struct ResumeTarget: Identifiable {
        let id = UUID()
        let repoPath: String, branch: String, worktreePath: String, sessionID: String, jobID: UUID?
    }

    var body: some View {
        HSplitView {
            dashboard.frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
            detail.frame(minWidth: 520, maxWidth: .infinity)
        }
        .background(WS.bg)
        .onAppear { model.refreshInstalled(); if selectedID == nil { selectedID = runs.runs.first?.id } }
        .onChange(of: selectedID) {
            if let id = selectedID, let rec = runs.history.first(where: { $0.id == id }) {
                runs.prepareHistoryWorkspace(rec)
            }
        }
        .sheet(isPresented: $showingNew) { newSheet }
        .sheet(isPresented: $showingNewJob) { newJobSheet }
        .sheet(item: $resumeTarget) { target in resumeSheet(target) }
        .alert("Remove job?",
               isPresented: Binding(get: { pendingJobRemoval != nil }, set: { if !$0 { pendingJobRemoval = nil } })) {
            Button("Remove", role: .destructive) { if let id = pendingJobRemoval { runs.removeJob(id); if selectedJobID == id { selectedJobID = nil }; pendingJobRemoval = nil } }
            Button("Cancel", role: .cancel) { pendingJobRemoval = nil }
        } message: {
            Text("Removes the goal and all its runs, deleting their worktrees.")
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .alert("Remove run?",
               isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("Remove", role: .destructive) { if let id = pendingRemoval { runs.removeRun(id); pendingRemoval = nil } }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Stops the run if it's still going and deletes its worktree. Uncommitted changes there are lost.")
        }
    }

    // MARK: Dashboard (left)

    private var dashboard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("RUNS").font(.system(size: 10.5, weight: .bold)).tracking(1.4).foregroundStyle(WS.label)
                Spacer()
                concurrencyStepper
                Menu {
                    Button { openNew() } label: { Label("New Run", systemImage: "bolt.horizontal") }
                    Button { openNewJob() } label: { Label("New Job (goal → subtasks)", systemImage: "square.stack.3d.down.right") }
                } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .semibold)).foregroundStyle(WS.textSecondary)
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

            let standalone = runs.runs.filter { $0.jobID == nil }
            if runs.jobs.isEmpty && standalone.isEmpty && runs.historyOnly.isEmpty {
                emptyDashboard
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(runs.jobs) { jobRow($0) }
                        ForEach(standalone) { liveRow($0) }
                        if !runs.historyOnly.isEmpty {
                            sectionLabel("HISTORY")
                            ForEach(runs.historyOnly) { recordRow($0) }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(WS.panel)
        .overlay(alignment: .trailing) { Rectangle().fill(WS.border).frame(width: 1) }
    }

    private var emptyDashboard: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.horizontal").font(.system(size: 24)).foregroundStyle(WS.textDim)
            Text("No runs yet").font(.system(size: 13)).foregroundStyle(WS.textTertiary)
            Button { openNew() } label: { Label("New Run", systemImage: "plus").font(.system(size: 12.5, weight: .semibold)) }
                .buttonStyle(PrimaryButtonStyle()).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func liveRow(_ run: AgentRun) -> some View {
        row(id: run.id, agent: run.kind, branch: run.branch, status: run.status,
            line: run.activity, ins: run.workspace.diff.insertions, del: run.workspace.diff.deletions,
            dimmed: false)
    }

    private func recordRow(_ rec: RunRecord) -> some View {
        let agent = AgentKind(rawValue: rec.agent) ?? .claude
        let line = rec.summary.split(whereSeparator: \.isNewline).first.map(String.init) ?? rec.task
        return row(id: rec.id, agent: agent, branch: rec.branch, status: rec.status,
                   line: line, ins: rec.insertions, del: rec.deletions, dimmed: true)
    }

    private func row(id: UUID, agent: AgentKind, branch: String, status: RunStatus,
                     line: String, ins: Int, del: Int, dimmed: Bool) -> some View {
        let selected = selectedID == id
        let hovered = hoveredID == id
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                statusDot(status)
                Image(agent.logo).resizable().frame(width: 13, height: 13).opacity(dimmed ? 0.6 : 1)
                Text(branch).font(WS.mono(11.5)).foregroundStyle(selected ? WS.textPrimary : Color(hex: 0xd7d8db))
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 6)
                if hovered {
                    Button { pendingRemoval = id } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(WS.textSecondary)
                            .frame(width: 17, height: 17).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain).help("Remove run")
                } else {
                    diffBadge(ins, del)
                }
            }
            Text(line.isEmpty ? "—" : line)
                .font(.system(size: 11.5)).foregroundStyle(status == .running ? WS.textSecondary : WS.textTertiary)
                .lineLimit(1).truncationMode(.tail)
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(selected ? WS.rowSelected : .clear, in: RoundedRectangle(cornerRadius: 7))
        .opacity(dimmed ? 0.78 : 1)
        .contentShape(Rectangle())
        .onTapGesture { selectedID = id; selectedJobID = nil }
        .onHover { hoveredID = $0 ? id : (hoveredID == id ? nil : hoveredID) }
    }

    private func sectionLabel(_ text: String) -> some View {
        HStack {
            Text(text).font(.system(size: 9.5, weight: .bold)).tracking(1.2).foregroundStyle(WS.textDim)
            Spacer()
        }.padding(.horizontal, 11).padding(.top, 14).padding(.bottom, 4)
    }

    private func jobRow(_ job: Job) -> some View {
        let selected = selectedJobID == job.id
        let hovered = hoveredID == job.id
        let children = runs.childViews(of: job)
        let doneCount = children.filter { $0.status.isTerminal }.count
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.down.right.fill").font(.system(size: 11)).foregroundStyle(WS.accent)
                Text(job.goal).font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(selected ? WS.textPrimary : Color(hex: 0xd7d8db)).lineLimit(1)
                Spacer(minLength: 6)
                if hovered {
                    Button { pendingJobRemoval = job.id } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(WS.textSecondary)
                            .frame(width: 17, height: 17).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                    }.buttonStyle(.plain).help("Remove job")
                }
            }
            Text(jobSubtitle(job, done: doneCount, total: job.childRunIDs.count))
                .font(.system(size: 11)).foregroundStyle(WS.textTertiary).lineLimit(1)
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(selected ? WS.rowSelected : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture { selectedJobID = job.id; selectedID = nil }
        .onHover { hoveredID = $0 ? job.id : (hoveredID == job.id ? nil : hoveredID) }
    }

    private func jobSubtitle(_ job: Job, done: Int, total: Int) -> String {
        switch job.status {
        case .planning: return "Planning…"
        case .ready: return "\(job.subtasks.count) subtasks — review & dispatch"
        case .running: return "Running \(done)/\(total)"
        case .done: return "Done · \(total) subtasks"
        case .failed: return "Planning failed"
        }
    }

    private func statusDot(_ s: RunStatus) -> some View {
        let c = statusColor(s)
        return Circle().fill(c).frame(width: 7, height: 7)
            .overlay(Circle().stroke(c.opacity(0.25), lineWidth: 3))
    }

    private func statusColor(_ s: RunStatus) -> Color {
        switch s {
        case .queued: WS.textTertiary
        case .running: WS.running
        case .verifying: WS.accent
        case .succeeded: WS.add
        case .failed: WS.del
        case .cancelled: WS.textTertiary
        }
    }

    @ViewBuilder private func diffBadge(_ ins: Int, _ del: Int) -> some View {
        if ins == 0 && del == 0 {
            Text("clean").font(.system(size: 10.5)).foregroundStyle(WS.textDim)
        } else {
            HStack(spacing: 4) {
                Text("+\(ins)").foregroundStyle(WS.add)
                Text("−\(del)").foregroundStyle(del > 0 ? WS.del : WS.textTertiary)
            }.font(WS.mono(10.5))
        }
    }

    // MARK: Detail (center + right)

    @ViewBuilder private var detail: some View {
        if let job = runs.jobs.first(where: { $0.id == selectedJobID }) {
            jobDetail(job)
        } else if let run = runs.runs.first(where: { $0.id == selectedID }) {
            HSplitView {
                VSplitView {
                    runFeed(run).frame(minWidth: 320, maxWidth: .infinity, minHeight: 200)
                    PreviewPanel(worktreePath: run.worktreePath, repoPath: run.repoPath, run: run).frame(minHeight: 160)
                }
                DiffPanel(workspace: run.workspace).frame(minWidth: 280, idealWidth: 340, maxWidth: 520)
            }
        } else if let rec = runs.history.first(where: { $0.id == selectedID }) {
            recordDetail(rec)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "bolt.horizontal.circle").font(.system(size: 28)).foregroundStyle(Color(hex: 0x3f4148))
                Text("Dispatch a task").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(hex: 0xd7d8db))
                Text("Pick a repo and describe a task — an agent runs it headless in its own worktree while you watch here.")
                    .font(.system(size: 12.5)).foregroundStyle(WS.textTertiary).multilineTextAlignment(.center).frame(maxWidth: 300)
                Button { openNew() } label: { Label("New Run", systemImage: "plus").font(.system(size: 13, weight: .semibold)) }
                    .buttonStyle(PrimaryButtonStyle()).padding(.top, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(WS.bg)
        }
    }

    // MARK: Job detail

    @ViewBuilder private func jobDetail(_ job: Job) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.down.right.fill").font(.system(size: 12)).foregroundStyle(WS.accent)
                    Text(jobStatusText(job)).font(.system(size: 12, weight: .semibold)).foregroundStyle(WS.textSecondary)
                    Spacer()
                    Text(job.repoName).font(WS.mono(11)).foregroundStyle(WS.textTertiary)
                }
                Text(job.goal).font(.system(size: 14, weight: .semibold)).foregroundStyle(WS.textPrimary)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(WS.bar).overlay(alignment: .bottom) { Rectangle().fill(WS.border).frame(height: 1) }

            switch job.status {
            case .planning:
                if let planner = runs.runs.first(where: { $0.id == job.plannerRunID }) {
                    runFeed(planner)
                } else {
                    centerNote("Planning…")
                }
            case .ready:
                subtaskEditor(job)
            case .running, .done, .failed:
                VSplitView {
                    childList(job).frame(minHeight: 120, idealHeight: 160, maxHeight: 240)
                    if let last = job.childRunIDs.last, let cr = runs.runs.first(where: { $0.id == last }) {
                        PreviewPanel(worktreePath: cr.worktreePath, repoPath: cr.repoPath, run: cr).frame(minHeight: 200)
                    } else {
                        centerNote("No worktree to preview yet.")
                    }
                }
            }
        }
        .background(WS.bg)
    }

    private func jobStatusText(_ job: Job) -> String {
        switch job.status {
        case .planning: "Planning"; case .ready: "Ready to dispatch"
        case .running: "Running"; case .done: "Done"; case .failed: "Failed"
        }
    }

    private func subtaskEditor(_ job: Job) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: job.mode == .sequential ? "arrow.down.to.line.compact" : "arrow.left.and.right")
                            .font(.system(size: 10)).foregroundStyle(WS.accent)
                        Text(job.mode == .sequential
                             ? "Sequential — runs in order on one shared branch, lands as one PR."
                             : "Parallel — independent, each in its own branch.")
                            .font(.system(size: 11.5)).foregroundStyle(WS.accent)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(WS.accentSubtle, in: RoundedRectangle(cornerRadius: 6))
                    Text("Review the plan — edit, remove, or add subtasks, then dispatch.")
                        .font(.system(size: 12)).foregroundStyle(WS.textTertiary)
                    ForEach(Array(job.subtasks.enumerated()), id: \.offset) { idx, _ in
                        HStack(spacing: 8) {
                            Text("\(idx + 1)").font(WS.mono(11)).foregroundStyle(WS.textDim).frame(width: 18)
                            TextField("Subtask", text: Binding(
                                get: { idx < job.subtasks.count ? job.subtasks[idx] : "" },
                                set: { if idx < job.subtasks.count { job.subtasks[idx] = $0 } }), axis: .vertical)
                                .textFieldStyle(.plain).font(.system(size: 12.5)).foregroundStyle(WS.textPrimary)
                                .padding(8).background(Color(hex: 0x1a1b1f), in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.08)))
                            Button { job.subtasks.remove(at: idx) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(WS.textDim)
                            }.buttonStyle(.plain)
                        }
                    }
                    Button { job.subtasks.append("") } label: {
                        Label("Add subtask", systemImage: "plus").font(.system(size: 12))
                    }.buttonStyle(.plain).foregroundStyle(WS.accent).padding(.top, 2)
                }
                .padding(16)
            }
            HStack {
                Spacer()
                Button(job.mode == .sequential ? "Dispatch chain (\(cleanSubtasks(job).count) steps)" : "Dispatch \(cleanSubtasks(job).count) runs") {
                    runs.dispatchJob(job, subtasks: cleanSubtasks(job))
                }
                .buttonStyle(PrimaryButtonStyle()).disabled(cleanSubtasks(job).isEmpty)
            }
            .padding(.horizontal, 16).frame(height: 52)
            .overlay(alignment: .top) { Rectangle().fill(WS.border).frame(height: 1) }
        }
    }

    private func cleanSubtasks(_ job: Job) -> [String] {
        job.subtasks.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func childList(_ job: Job) -> some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(runs.childViews(of: job)) { rv in
                    HStack(spacing: 8) {
                        statusDot(rv.status)
                        Text(rv.task).font(.system(size: 12.5)).foregroundStyle(Color(hex: 0xd7d8db)).lineLimit(1)
                        Spacer(minLength: 6)
                        diffBadge(rv.insertions, rv.deletions)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(WS.rowSelected.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                    .onTapGesture { selectedID = rv.id; selectedJobID = nil }
                }
            }
            .padding(12)
        }
    }

    private func centerNote(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(WS.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func runFeed(_ run: AgentRun) -> some View {
        VStack(spacing: 0) {
            feedHeader(task: run.task, branch: run.branch, status: run.status, elapsed: run.elapsed, live: run.status == .running) {
                run.cancel()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if run.events.isEmpty {
                            Text(run.activity).font(WS.mono(12)).foregroundStyle(WS.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        }
                        ForEach(run.events) { feedRow($0) }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.vertical, 6)
                }
                .onChange(of: run.events.count) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            mergeBanner(run)
            if run.status.isTerminal, let sid = run.sessionID, !sid.isEmpty {
                continueBar {
                    openResume(repoPath: run.repoPath, branch: run.branch, worktreePath: run.worktreePath, sessionID: sid, jobID: run.jobID)
                }
            }
        }
        .background(WS.bg)
    }

    private func continueBar(action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.forward.circle").font(.system(size: 12)).foregroundStyle(WS.accent)
            Text("Resume this session with a follow-up").font(.system(size: 12)).foregroundStyle(WS.textSecondary)
            Spacer()
            Button("Continue…") { action() }.buttonStyle(.plain).foregroundStyle(WS.accent).font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 16).frame(height: 36)
        .background(WS.accent.opacity(0.08))
        .overlay(alignment: .top) { Rectangle().fill(WS.border).frame(height: 1) }
    }

    private func openResume(repoPath: String, branch: String, worktreePath: String, sessionID: String, jobID: UUID?) {
        followUp = ""
        resumeTarget = ResumeTarget(repoPath: repoPath, branch: branch, worktreePath: worktreePath, sessionID: sessionID, jobID: jobID)
    }

    private func resumeSheet(_ t: ResumeTarget) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "arrow.uturn.forward.circle").font(.system(size: 13, weight: .bold)).foregroundStyle(WS.accent)
                    .frame(width: 26, height: 26).background(WS.accentSubtle, in: RoundedRectangle(cornerRadius: 8))
                Text("Continue session").font(.system(size: 15, weight: .semibold)).foregroundStyle(WS.textPrimary)
            }
            Text(t.branch).font(WS.mono(11)).foregroundStyle(WS.textTertiary)
            TextField("What should the agent do next?", text: $followUp, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(WS.textPrimary).lineLimit(3...8)
                .padding(10).background(Color(hex: 0x1a1b1f), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(WS.accent.opacity(0.5)))
            HStack {
                Spacer()
                Button("Cancel") { resumeTarget = nil }.buttonStyle(.plain).foregroundStyle(Color(hex: 0xd7d8db))
                Button("Resume") {
                    let run = runs.resume(repoPath: t.repoPath, branch: t.branch, worktreePath: t.worktreePath,
                                          sessionID: t.sessionID, followUp: followUp, jobID: t.jobID)
                    selectedID = run?.id; selectedJobID = nil; resumeTarget = nil
                }
                .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                .disabled(followUp.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22).frame(width: 460).background(Color(hex: 0x26272d))
    }

    @ViewBuilder private func mergeBanner(_ run: AgentRun) -> some View {
        switch run.mergeOutcome {
        case .none: EmptyView()
        case .prOpen:
            banner(icon: "arrow.triangle.pull.request", tint: WS.accent, text: "Pull request open") {
                if let u = run.prURL, let url = URL(string: u) {
                    Button("Open PR ↗") { NSWorkspace.shared.open(url) }.buttonStyle(.plain).foregroundStyle(WS.accent).font(.system(size: 11, weight: .semibold))
                }
            }
        case .merged:
            banner(icon: "checkmark.circle.fill", tint: WS.add, text: "Merged into base branch") { EmptyView() }
        case .conflict:
            banner(icon: "exclamationmark.triangle.fill", tint: WS.del, text: "Merge conflict — needs attention") { EmptyView() }
        case .failed:
            banner(icon: "xmark.octagon.fill", tint: WS.del, text: "Post-merge action failed") { EmptyView() }
        }
    }

    private func banner<T: View>(icon: String, tint: Color, text: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(tint)
            Text(text).font(.system(size: 12)).foregroundStyle(WS.textSecondary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16).frame(height: 36)
        .background(tint.opacity(0.10))
        .overlay(alignment: .top) { Rectangle().fill(WS.border).frame(height: 1) }
    }

    private func feedRow(_ ev: RunEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ev.icon).font(.system(size: 11)).foregroundStyle(WS.accent)
                .frame(width: 16, height: 16).padding(.top, 1)
            Text(ev.text).font(.system(size: 12.5)).foregroundStyle(Color(hex: 0xc9cace))
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 5)
    }

    private func feedHeader(task: String, branch: String, status: RunStatus, elapsed: TimeInterval, live: Bool, cancel: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                statusDot(status)
                Text(status.rawValue.capitalized).font(.system(size: 12, weight: .semibold)).foregroundStyle(statusColor(status))
                Text(branch).font(WS.mono(11)).foregroundStyle(WS.textTertiary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(elapsedText(elapsed)).font(WS.mono(11)).foregroundStyle(WS.textTertiary)
                if live {
                    Button { cancel() } label: {
                        Text("Stop").font(.system(size: 11, weight: .semibold)).foregroundStyle(WS.del)
                            .padding(.horizontal, 9).padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(WS.del.opacity(0.45)))
                    }.buttonStyle(.plain)
                }
            }
            Text(task).font(.system(size: 13)).foregroundStyle(Color(hex: 0xd7d8db)).lineLimit(2)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WS.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(WS.border).frame(height: 1) }
    }

    @ViewBuilder private func recordDetail(_ rec: RunRecord) -> some View {
        let ws = runs.historyWorkspaces[rec.id]
        VStack(alignment: .leading, spacing: 0) {
            feedHeader(task: rec.task, branch: rec.branch, status: rec.status,
                       elapsed: (rec.endedAt ?? rec.startedAt).timeIntervalSince(rec.startedAt), live: false) {}
            if let ws {
                HSplitView {
                    recordSummary(rec).frame(minWidth: 280, maxWidth: .infinity)
                    DiffPanel(workspace: ws).frame(minWidth: 280, idealWidth: 340, maxWidth: 520)
                }
            } else {
                recordSummary(rec)
            }
            if rec.canResume, let sid = rec.sessionID {
                continueBar {
                    openResume(repoPath: rec.repoPath, branch: rec.branch, worktreePath: rec.worktreePath, sessionID: sid, jobID: rec.jobID)
                }
            }
        }
        .background(WS.bg)
    }

    private func recordSummary(_ rec: RunRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text(rec.repoName).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(WS.textSecondary)
                    diffBadge(rec.insertions, rec.deletions)
                    if (rec.mergeOutcome ?? .none) == .prOpen, let u = rec.prURL, let url = URL(string: u) {
                        Button("Open PR ↗") { NSWorkspace.shared.open(url) }.buttonStyle(.plain).foregroundStyle(WS.accent).font(.system(size: 11, weight: .semibold))
                    }
                    Spacer()
                }
                if !rec.summary.isEmpty {
                    Text(rec.summary).font(.system(size: 12.5)).foregroundStyle(Color(hex: 0xc9cace)).textSelection(.enabled)
                } else {
                    Text("No summary recorded.").font(.system(size: 12)).foregroundStyle(WS.textTertiary)
                }
                if !rec.worktreeExists {
                    Text("Worktree was removed — diff and resume unavailable.").font(.system(size: 11)).foregroundStyle(WS.del)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func elapsedText(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s < 60 ? "\(s)s" : "\(s / 60)m \(s % 60)s"
    }

    // MARK: New Run sheet

    private var newSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: "bolt.horizontal").font(.system(size: 13, weight: .bold)).foregroundStyle(WS.accent)
                    .frame(width: 26, height: 26).background(WS.accentSubtle, in: RoundedRectangle(cornerRadius: 8))
                Text("New Run").font(.system(size: 15, weight: .semibold)).foregroundStyle(WS.textPrimary)
            }

            field("Repository") {
                HStack(spacing: 8) {
                    Text(newRepoPath.isEmpty ? "Choose a git repo…" : newRepoPath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(WS.mono(12)).foregroundStyle(newRepoPath.isEmpty ? WS.textTertiary : Color(hex: 0xd7d8db))
                        .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9).background(Color(hex: 0x1a1b1f), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1)))
                    Button("Browse…") { if let p = pickRepo() { newRepoPath = p; if newVerify.isEmpty { newVerify = runs.verifyCommand(for: p) } } }.buttonStyle(SecondaryButtonStyle())
                }
            }

            field("Task") {
                TextField("Describe the task for the agent…", text: $newTask, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(WS.textPrimary).lineLimit(3...8)
                    .padding(10).background(Color(hex: 0x1a1b1f), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(WS.accent.opacity(0.5)))
            }

            HStack(alignment: .top, spacing: 12) {
                field("Verify command — optional") {
                    TextField("e.g. swift test", text: $newVerify)
                        .textFieldStyle(.plain).font(WS.mono(12)).foregroundStyle(WS.textPrimary)
                        .padding(9).background(Color(hex: 0x1a1b1f), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1)))
                }
                field("On green") {
                    Picker("", selection: $newMergeMode) {
                        Text("Nothing").tag(MergeMode.none)
                        Text("Open PR").tag(MergeMode.pr)
                        Text("Auto-merge").tag(MergeMode.merge)
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 130)
                }
            }
            Text("Verify runs after the agent; the run only goes green if it exits 0. \"On green\" then opens a PR or merges into the base branch.")
                .font(.system(size: 11)).foregroundStyle(WS.textDim)

            HStack(spacing: 7) {
                Image(AgentKind.claude.logo).resizable().frame(width: 14, height: 14)
                Text("Runs headless with Claude Code").font(.system(size: 11.5)).foregroundStyle(WS.textTertiary)
                if !model.installed.contains(.claude) {
                    Text("· not installed").font(.system(size: 11.5)).foregroundStyle(WS.del)
                }
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { showingNew = false }.buttonStyle(.plain).foregroundStyle(Color(hex: 0xd7d8db))
                Button(creating ? "Dispatching…" : "Run") { dispatch() }
                    .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                    .disabled(newRepoPath.isEmpty || newTask.trimmingCharacters(in: .whitespaces).isEmpty
                              || !model.installed.contains(.claude) || creating)
            }
            .padding(.top, 4)
        }
        .padding(22).frame(width: 480).background(Color(hex: 0x26272d))
    }

    private func field<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(WS.textSecondary)
            content()
        }
    }

    private var concurrencyStepper: some View {
        HStack(spacing: 3) {
            Image(systemName: "square.stack.3d.up").font(.system(size: 10)).foregroundStyle(WS.textTertiary)
            Stepper(value: Binding(get: { runs.maxConcurrent }, set: { runs.maxConcurrent = $0 }), in: 1...12) {
                Text("\(runs.maxConcurrent)").font(WS.mono(11)).foregroundStyle(WS.textSecondary)
            }
            .labelsHidden().controlSize(.mini)
        }
        .help("Max runs executing at once")
    }

    private var newJobSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: "square.stack.3d.down.right").font(.system(size: 13, weight: .bold)).foregroundStyle(WS.accent)
                    .frame(width: 26, height: 26).background(WS.accentSubtle, in: RoundedRectangle(cornerRadius: 8))
                Text("New Job").font(.system(size: 15, weight: .semibold)).foregroundStyle(WS.textPrimary)
            }

            field("Repository") {
                HStack(spacing: 8) {
                    Text(newRepoPath.isEmpty ? "Choose a git repo…" : newRepoPath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(WS.mono(12)).foregroundStyle(newRepoPath.isEmpty ? WS.textTertiary : Color(hex: 0xd7d8db))
                        .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9).background(Color(hex: 0x1a1b1f), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1)))
                    Button("Browse…") { if let p = pickRepo() { newRepoPath = p; if newVerify.isEmpty { newVerify = runs.verifyCommand(for: p) } } }.buttonStyle(SecondaryButtonStyle())
                }
            }

            field("Goal") {
                TextField("A high-level goal — the planner breaks it into subtasks…", text: $newGoal, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(WS.textPrimary).lineLimit(2...6)
                    .padding(10).background(Color(hex: 0x1a1b1f), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(WS.accent.opacity(0.5)))
            }

            HStack(alignment: .top, spacing: 12) {
                field("Verify (each subtask)") {
                    TextField("e.g. swift test", text: $newVerify)
                        .textFieldStyle(.plain).font(WS.mono(12)).foregroundStyle(WS.textPrimary)
                        .padding(9).background(Color(hex: 0x1a1b1f), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1)))
                }
                field("On green") {
                    Picker("", selection: $newMergeMode) {
                        Text("Nothing").tag(MergeMode.none); Text("Open PR").tag(MergeMode.pr); Text("Auto-merge").tag(MergeMode.merge)
                    }.labelsHidden().pickerStyle(.menu).frame(width: 130)
                }
            }
            Text("The planner proposes subtasks; you review and edit them before anything runs.")
                .font(.system(size: 11)).foregroundStyle(WS.textDim)

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { showingNewJob = false }.buttonStyle(.plain).foregroundStyle(Color(hex: 0xd7d8db))
                Button(creating ? "Planning…" : "Plan") { planJob() }
                    .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                    .disabled(newRepoPath.isEmpty || newGoal.trimmingCharacters(in: .whitespaces).isEmpty
                              || !model.installed.contains(.claude) || creating)
            }
            .padding(.top, 4)
        }
        .padding(22).frame(width: 480).background(Color(hex: 0x26272d))
    }

    private func openNew() {
        newRepoPath = model.selectedWorkspace?.repoPath ?? ""
        newTask = ""
        newVerify = runs.verifyCommand(for: newRepoPath)
        newMergeMode = runs.defaultMergeMode
        showingNew = true
    }

    private func openNewJob() {
        newRepoPath = model.selectedWorkspace?.repoPath ?? ""
        newGoal = ""
        newVerify = runs.verifyCommand(for: newRepoPath)
        newMergeMode = runs.defaultMergeMode
        showingNewJob = true
    }

    private func planJob() {
        creating = true
        let repo = newRepoPath, goal = newGoal
        let verify = newVerify.trimmingCharacters(in: .whitespaces)
        let mode = newMergeMode
        Task {
            do {
                let job = try await runs.createJob(repoPath: repo, goal: goal,
                                                   verifyCommand: verify.isEmpty ? nil : verify, mergeMode: mode)
                selectedJobID = job.id; selectedID = nil
                creating = false; showingNewJob = false
            } catch { creating = false; errorMessage = "\(error)" }
        }
    }

    private func dispatch() {
        creating = true
        let repo = newRepoPath, task = newTask
        let verify = newVerify.trimmingCharacters(in: .whitespaces)
        let mode = newMergeMode
        Task {
            do {
                let run = try await runs.dispatch(repoPath: repo, task: task,
                                                  verifyCommand: verify.isEmpty ? nil : verify, mergeMode: mode)
                selectedID = run.id
                creating = false; showingNew = false
            } catch { creating = false; errorMessage = "\(error)" }
        }
    }

    private func pickRepo() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "Select Repo"
        guard panel.runModal() == .OK, let path = panel.url?.path else { return nil }
        guard GitWorktrees.isGitRepo(path) else { errorMessage = "Not a git repository:\n\(path)"; return nil }
        return path
    }
}

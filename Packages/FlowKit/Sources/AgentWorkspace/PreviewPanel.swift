import AppKit
import SwiftUI

/// Embedded browser that runs the app built in `worktreePath` and (P2) records feedback.
struct PreviewPanel: View {
    let worktreePath: String
    let repoPath: String
    var run: AgentRun?   // the run whose worktree this is — feedback continues its session

    @State private var runs = RunsModel.shared
    @State private var server = PreviewServer()
    @State private var controller = WebPreviewController()
    @State private var recorder = FeedbackRecorder()
    @State private var command = ""
    @State private var portText = "3000"
    @State private var processing = false
    @State private var pendingFeedback: (dir: String, md: String)?
    @State private var micDenied = false

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(WS.bg)
        .overlay(alignment: .top) { Rectangle().fill(WS.border).frame(height: 1) }
        .onAppear {
            command = runs.previewCommand(for: repoPath)
            portText = "\(runs.previewPort(for: repoPath))"
        }
        .onDisappear { server.stop() }
        .onChange(of: server.state) {
            if case .running(let url) = server.state { controller.load(url) }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "safari").font(.system(size: 11)).foregroundStyle(WS.textSecondary)
            Text("PREVIEW").font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(WS.label)
            Spacer()
            switch server.state {
            case .running(let url):
                Text(url.absoluteString).font(WS.mono(10.5)).foregroundStyle(WS.textTertiary).lineLimit(1)
                if recorder.isRecording {
                    HStack(spacing: 5) {
                        Circle().fill(WS.del).frame(width: 7, height: 7)
                        Text("REC · \(recorder.clickCount) clicks").font(WS.mono(10)).foregroundStyle(WS.del)
                    }
                    Button("Stop") { stopFeedback() }.buttonStyle(.plain).foregroundStyle(WS.del).font(.system(size: 11, weight: .semibold))
                } else {
                    Button { startFeedback() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "mic.circle.fill").font(.system(size: 12))
                            Text("Feedback").font(.system(size: 11, weight: .medium))
                        }.foregroundStyle(WS.accent)
                    }.buttonStyle(.plain).help("Record voice + click feedback for the agent")
                }
                iconButton("arrow.clockwise", "Reload") { controller.reload() }
                iconButton("stop.circle", "Stop server") { server.stop() }
            case .starting:
                ProgressView().controlSize(.mini)
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 12).frame(height: 32).background(WS.bar)
    }

    @ViewBuilder private var content: some View {
        switch server.state {
        case .idle:
            setup(error: nil)
        case .failed(let msg):
            setup(error: msg)
        case .starting:
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Starting the app…").font(.system(size: 12)).foregroundStyle(WS.textTertiary)
                if !server.log.isEmpty {
                    Text(String(server.log.suffix(300))).font(WS.mono(10)).foregroundStyle(WS.textDim)
                        .lineLimit(4).padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .running:
            VStack(spacing: 0) {
                WebPreviewView(controller: controller).frame(maxWidth: .infinity, maxHeight: .infinity)
                if processing {
                    feedbackBar { HStack(spacing: 7) { ProgressView().controlSize(.small); Text("Processing feedback (transcribing)…").font(.system(size: 11.5)).foregroundStyle(WS.textTertiary) } }
                } else if let fb = pendingFeedback {
                    feedbackBar {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(WS.add).font(.system(size: 12))
                            Text("Feedback captured.").font(.system(size: 11.5)).foregroundStyle(WS.textSecondary)
                            Spacer()
                            Button("Review understanding") { dispatchFeedback(fb, fix: false); }.buttonStyle(SecondaryButtonStyle())
                            Button("Fix now") { dispatchFeedback(fb, fix: true); pendingFeedback = nil }.buttonStyle(PrimaryButtonStyle())
                            Button { pendingFeedback = nil } label: { Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(WS.textTertiary) }.buttonStyle(.plain)
                        }
                    }
                } else if micDenied {
                    feedbackBar { Text("Microphone access denied — enable it in System Settings to record feedback.").font(.system(size: 11)).foregroundStyle(WS.del) }
                }
            }
        }
    }

    private func feedbackBar<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(.horizontal, 14).frame(height: 40).frame(maxWidth: .infinity)
            .background(WS.bar).overlay(alignment: .top) { Rectangle().fill(WS.border).frame(height: 1) }
    }

    private func setup(error: String?) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "safari").font(.system(size: 24)).foregroundStyle(WS.textDim)
            Text("Run the app to preview it").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0xd7d8db))
            HStack(spacing: 8) {
                TextField("start command — e.g. cd web && npm run dev", text: $command)
                    .textFieldStyle(.plain).font(WS.mono(12)).foregroundStyle(WS.textPrimary)
                    .padding(8).frame(width: 320).background(Color(hex: 0x1a1b1f), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.1)))
                TextField("port", text: $portText)
                    .textFieldStyle(.plain).font(WS.mono(12)).foregroundStyle(WS.textPrimary).frame(width: 56)
                    .padding(8).background(Color(hex: 0x1a1b1f), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.1)))
                Button("Run app") { runApp() }.buttonStyle(PrimaryButtonStyle())
                    .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let error {
                Text(error).font(WS.mono(10.5)).foregroundStyle(WS.del).lineLimit(5)
                    .frame(maxWidth: 420).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func iconButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(WS.textSecondary).frame(width: 22, height: 22)
        }
        .buttonStyle(.plain).help(help)
    }

    private func runApp() {
        let port = Int(portText) ?? 3000
        runs.savePreview(repo: repoPath, command: command, port: port)
        server.start(command: command, port: port, cwd: worktreePath)
    }

    private func startFeedback() {
        micDenied = false; pendingFeedback = nil
        Task {
            let ok = await recorder.start(controller: controller, worktreePath: worktreePath)
            if !ok { micDenied = true }
        }
    }

    private func stopFeedback() {
        processing = true
        Task {
            let result = await recorder.finish()
            processing = false
            if let r = result { pendingFeedback = (r.dir, r.mdRelToWorktree) }
        }
    }

    private func dispatchFeedback(_ fb: (dir: String, md: String), fix: Bool) {
        let prompt = fix
            ? "I just recorded feedback on the app you built (running now). Read \(fb.md) — my spoken transcript, an interaction log, and screenshots in its frames/ folder (open the PNGs to see what I saw). Implement the fixes I asked for. Keep the dev server working."
            : "I just recorded feedback on the app you built. Read \(fb.md) — my transcript, interaction log, and screenshots in its frames/ folder (open the PNGs). Do NOT edit any code yet. Reply with a numbered list of the concrete, actionable changes you understood from my feedback so I can confirm."
        // Continue the SAME session so the agent keeps full context — no cold new run.
        if let run, run.canContinue {
            run.continueWith(prompt)
        } else {
            let task = fix ? "Fix from feedback" : "Understand feedback"
            runs.runInWorktree(repoPath: repoPath, branch: GitWorktrees.currentBranch(worktreePath),
                               worktreePath: worktreePath, task: task, promptOverride: prompt)
        }
    }
}

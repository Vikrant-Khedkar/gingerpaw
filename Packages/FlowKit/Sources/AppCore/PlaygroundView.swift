import AppKit
import Dictation
import Playground
import SwiftUI

struct PlaygroundView: View {
    @Bindable var playground: PlaygroundController
    @Bindable var coordinator: DictationCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Playground", subtitle: "Turn dictated tasks into claude-sgai runs.")

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    promptCard
                    runCard
                }
                .frame(minWidth: 360)

                VStack(alignment: .leading, spacing: 12) {
                    outputCard
                    historyCard
                }
                .frame(minWidth: 280)
            }
        }
        .onAppear {
            if case .idle = playground.status {
                playground.checkClaude()
            }
        }
    }

    private var promptCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionTitle("Task")
                    Spacer()
                    if let transcript = coordinator.lastResult?.transcript {
                        Button {
                            playground.useTranscript(transcript)
                        } label: {
                            Label("Use Last", systemImage: "arrow.down.doc")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Brand.accent)
                    }
                }

                TextEditor(text: $playground.rawPrompt)
                    .font(.system(size: 13))
                    .frame(minHeight: 88)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5))

                HStack {
                    Button {
                        playground.refinePrompt()
                    } label: {
                        Label("Polish", systemImage: "wand.and.stars")
                    }
                    .disabled(playground.rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()
                }

                TextEditor(text: $playground.refinedPrompt)
                    .font(.system(size: 13))
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5))
            }
        }
    }

    private var runCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionTitle("claude-sgai")
                    Spacer()
                    StatusPill(text: playground.status.label, color: playground.status.tint)
                }

                HStack(spacing: 8) {
                    Image(systemName: playground.availability.isInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(playground.availability.isInstalled ? .green : .orange)
                    Text(playground.availability.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        playground.checkClaude()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Check claude-sgai")
                }

                HStack(spacing: 8) {
                    Button {
                        chooseRepository()
                    } label: {
                        Label("Choose Repo", systemImage: "folder")
                    }

                    Text(playground.repositoryURL?.lastPathComponent ?? "No repository selected")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(spacing: 10) {
                    Button {
                        playground.run()
                    } label: {
                        Label("Run claude-sgai", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!playground.canRun)

                    Button {
                        playground.cancel()
                    } label: {
                        Label("Cancel", systemImage: "stop.fill")
                    }
                    .disabled(playground.status != .running)
                }
            }
        }
    }

    private var outputCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Output")
                ScrollView {
                    Text(playground.output.isEmpty ? "claude-sgai output will appear here." : playground.output)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(playground.output.isEmpty ? .tertiary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
                }
                .frame(minHeight: 230)
                .padding(10)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5))
            }
        }
    }

    private var historyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Runs")
                if playground.runs.isEmpty {
                    Text("No claude-sgai runs yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(playground.runs.prefix(4)) { run in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(run.startedAt, style: .time)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                StatusPill(text: run.status.label, color: run.status.tint)
                            }
                            Text(run.prompt)
                                .font(.system(size: 12))
                                .lineLimit(2)
                        }
                        Divider()
                    }
                }
            }
        }
    }

    private func chooseRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK {
            playground.repositoryURL = panel.url
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }
}

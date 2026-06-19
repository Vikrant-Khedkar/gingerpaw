import AppKit
import Dictation
import Settings
import SwiftUI

struct DictateView: View {
    @Bindable var coordinator: DictationCoordinator
    @Bindable var settings: FlowSettings
    let hotkeyReady: Bool

    @State private var pressing = false

    private var isRecording: Bool {
        if case .recording = coordinator.state { return true }
        return false
    }

    private var isBusy: Bool { coordinator.state.isBusy }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(title: "Dictate", subtitle: "Hold \(settings.hotkeyDisplay) to talk. Release to paste.")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Last transcription")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let result = coordinator.lastResult {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(result.transcript, forType: .string)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Brand.accent)
                    }
                }

                Card {
                    if let result = coordinator.lastResult {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(result.transcript)
                                .font(.system(size: 14))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 12) {
                                Label(String(format: "%.1fs", result.duration), systemImage: "clock")
                                Label(result.insertionOutcome == .pasted ? "Pasted" : "Copied",
                                      systemImage: result.insertionOutcome == .pasted ? "arrow.down.doc" : "doc.on.clipboard")
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Nothing dictated yet. Hold \(settings.hotkeyDisplay) and speak.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 12) {
                holdButton
                Text("Press and hold, or use the \(settings.hotkeyDisplay) hotkey")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
    }

    private var holdButton: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill").font(.system(size: 16))
            Text(isRecording ? "Listening… release to paste" : "Hold to dictate")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(isRecording ? Color.red : Brand.accent, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        .opacity(isBusy && !isRecording ? 0.4 : 1)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressing else { return }
                    pressing = true
                    coordinator.startRecording()
                }
                .onEnded { _ in
                    pressing = false
                    coordinator.stopRecordingAndProcess()
                }
        )
    }
}

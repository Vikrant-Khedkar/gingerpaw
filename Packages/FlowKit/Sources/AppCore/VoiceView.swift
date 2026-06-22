import AVFoundation
import AgentNotifications
import SwiftUI

struct VoiceView: View {
    @State private var store = VoiceSettingsStore()
    @State private var hookInstalled = HookInstaller.isInstalled(in: HookInstaller.sgaiDir)
    @State private var error: String?
    @State private var speaker = VoiceSpeaker()

    private let voices: [String] = AVSpeechSynthesisVoice.speechVoices()
        .filter { $0.language.hasPrefix("en") }
        .map(\.name)
        .reduce(into: [String]()) { acc, name in if !acc.contains(name) { acc.append(name) } }
        .sorted()

    private let kokoroVoices = ["af_bella", "af_sarah", "af_nicole", "af_sky",
                                "am_adam", "am_michael",
                                "bf_emma", "bf_isabella", "bm_george", "bm_lewis"]
    @State private var kokoroInstalled = KokoroSynthesizer.isAvailable
    @State private var kokoroInstalling = false
    @State private var kokoroProgress = ""

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(title: "Voice", subtitle: "Speak a notification when Claude Code finishes or needs you.")

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Notifications")
                    Toggle("Enable voice notifications", isOn: $store.enabled)
                    Toggle("Speak when Claude finishes", isOn: $store.speakOnStop)
                        .disabled(!store.enabled)
                    Toggle("Speak when Claude needs you", isOn: $store.speakOnNotification)
                        .disabled(!store.enabled)
                    Text("Claude can choose its own line by ending a turn with <say>…</say>; otherwise GingerPaw says \"Claude finished in <project>\".")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Voice")
                    Picker("Engine", selection: $store.ttsEngine) {
                        Text("System").tag("say")
                        Text(kokoroInstalled ? "Kokoro — neural" : "Kokoro (not installed)").tag("kokoro")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    if store.ttsEngine == "kokoro" {
                        Picker("Kokoro voice", selection: $store.kokoroVoice) {
                            ForEach(kokoroVoices, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        HStack(spacing: 10) {
                            Text("Speed").font(.system(size: 13)).foregroundStyle(.secondary)
                            Slider(value: $store.kokoroSpeed, in: 0.7 ... 1.5)
                            Text(String(format: "%.2fx", store.kokoroSpeed)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        if !kokoroInstalled {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Kokoro isn't installed — GingerPaw uses the system voice until it is. Setup downloads ~200MB (needs python3).")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                Button {
                                    installKokoro()
                                } label: {
                                    Label(kokoroInstalling ? "Installing…" : "Install Kokoro voice", systemImage: "arrow.down.circle")
                                }
                                .disabled(kokoroInstalling)
                                if !kokoroProgress.isEmpty {
                                    HStack(spacing: 6) {
                                        if kokoroInstalling { ProgressView().controlSize(.small) }
                                        Text(kokoroProgress).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                    } else {
                        Picker("Voice", selection: $store.voice) {
                            Text("System default").tag("")
                            ForEach(voices, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        HStack(spacing: 10) {
                            Text("Speed").font(.system(size: 13)).foregroundStyle(.secondary)
                            Slider(
                                value: Binding(
                                    get: { Double(store.rate == 0 ? 175 : store.rate) },
                                    set: { store.rate = Int($0) }
                                ),
                                in: 130 ... 260
                            )
                            Text("\(store.rate == 0 ? 175 : store.rate)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        speaker.speak(text: "Claude finished in GingerPaw.", voiceName: store.voice, rate: store.rate)
                    } label: {
                        Label("Test voice", systemImage: "play.circle")
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Claude Code Hook")
                    HStack(spacing: 8) {
                        Image(systemName: hookInstalled ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(hookInstalled ? .green : .secondary)
                        Text(hookInstalled ? "Installed in ~/.claude-sgai" : "Not installed")
                            .font(.system(size: 13))
                        Spacer()
                        Button(hookInstalled ? "Remove" : "Install hook") {
                            do {
                                if hookInstalled { try HookInstaller.remove(in: HookInstaller.sgaiDir) }
                                else { try HookInstaller.install(in: HookInstaller.sgaiDir) }
                                hookInstalled = HookInstaller.isInstalled(in: HookInstaller.sgaiDir)
                                error = nil
                            } catch let err { error = String(describing: err) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if let error {
                        Text(error).font(.system(size: 11)).foregroundStyle(.red)
                    }
                    Text("Adds Stop + Notification hooks to ~/.claude-sgai/settings.json (backed up first). Restart Claude sessions to pick it up.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    private func installKokoro() {
        kokoroInstalling = true
        kokoroProgress = "Starting…"
        Task {
            do {
                try await KokoroInstaller.install { kokoroProgress = $0 }
                kokoroInstalled = KokoroSynthesizer.isAvailable
                kokoroProgress = kokoroInstalled ? "Installed ✓" : "Finished, but model not found"
            } catch {
                kokoroProgress = "Failed: \(error.localizedDescription)"
            }
            kokoroInstalling = false
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }
}

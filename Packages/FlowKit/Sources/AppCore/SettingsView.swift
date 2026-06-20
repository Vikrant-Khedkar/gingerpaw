import Settings
import SwiftUI

public struct SettingsView: View {
    @Bindable private var settings: FlowSettings

    public init(settings: FlowSettings) {
        self.settings = settings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(title: "Settings", subtitle: "Tune the model and how dictated text lands.")

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Model")
                    Picker("Whisper model", selection: $settings.modelID) {
                        Text("Base — fast, recommended").tag("openai_whisper-base")
                        Text("Small — more accurate").tag("openai_whisper-small")
                        Text("Large v3 Turbo — best, slow").tag("openai_whisper-large-v3_turbo")
                    }
                    .labelsHidden()
                    Text("Models download once to ~/Documents/huggingface and run on-device.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Output")
                    Toggle("Auto-paste into focused app", isOn: $settings.autoPaste)
                    Toggle("Restore previous clipboard after paste", isOn: $settings.restoreClipboard)
                        .disabled(!settings.autoPaste)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("AI Formatting")
                    Toggle("Structure dictation with on-device AI", isOn: $settings.formatEnabled)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Hotkey")
                    Picker("Push-to-talk key", selection: $settings.hotkey) {
                        ForEach(Hotkey.allCases) { key in
                            Text(key.display).tag(key)
                        }
                    }
                    .labelsHidden()
                    Text("Hold this key to dictate. Right Option or Fn recommended — they don't clash with typing.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Appearance")
                    Toggle("Show floating recording pill", isOn: $settings.showPill)
                }
            }

            Spacer()
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }
}

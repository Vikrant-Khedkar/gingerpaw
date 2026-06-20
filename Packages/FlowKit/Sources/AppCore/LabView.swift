import Dictation
import Settings
import SwiftUI

/// Internal A/B testing: switch transcription engine and compare per-dictation metrics.
struct LabView: View {
    @Bindable var coordinator: DictationCoordinator
    @Bindable var settings: FlowSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(title: "Lab", subtitle: "Compare transcription engines. Internal testing only.")

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Engine")
                    Picker("Engine", selection: $settings.engine) {
                        ForEach(TranscriptionEngine.allCases) { Text($0.display).tag($0) }
                    }
                    .labelsHidden()

                    if settings.engine == .moonshine {
                        Picker("Moonshine model", selection: $settings.moonshineModel) {
                            ForEach(MoonshineModel.allCases) { Text($0.display).tag($0) }
                        }
                        .labelsHidden()
                        Text("Requires `pip install useful-moonshine-onnx`. Shells out to Python; first run downloads the model and is slow.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    } else {
                        Text("WhisperKit model is set in Settings (\(settings.modelID)).")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text("Active: \(settings.engineLabel)")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.accent)
                }
            }

            Text("Runs")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)

            if coordinator.history.isEmpty {
                Card {
                    Text("Dictate something to populate metrics. Each run records engine, audio length, transcribe time, and real-time factor.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            } else {
                Card {
                    VStack(spacing: 0) {
                        header
                        Divider().padding(.vertical, 6)
                        ForEach(coordinator.history) { run in
                            row(run)
                            if run.id != coordinator.history.last?.id {
                                Divider().padding(.vertical, 6)
                            }
                        }
                    }
                }
            }
            Spacer()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("ENGINE").frame(width: 150, alignment: .leading)
            Text("AUDIO").frame(width: 52, alignment: .trailing)
            Text("INFER").frame(width: 56, alignment: .trailing)
            Text("RTF").frame(width: 48, alignment: .trailing)
            Text("TEXT").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
    }

    private func row(_ run: DictationResult) -> some View {
        HStack(spacing: 8) {
            Text(run.engineLabel).frame(width: 150, alignment: .leading).lineLimit(1)
            Text(String(format: "%.1fs", run.audioSeconds)).frame(width: 52, alignment: .trailing)
            Text(String(format: "%.2fs", run.transcribeSeconds)).frame(width: 56, alignment: .trailing)
            Text(String(format: "%.1f×", run.realTimeFactor))
                .frame(width: 48, alignment: .trailing)
                .foregroundStyle(run.realTimeFactor >= 1 ? .green : .orange)
            Text(run.transcript).frame(maxWidth: .infinity, alignment: .leading).lineLimit(2)
        }
        .font(.system(size: 11, design: .monospaced))
        .textSelection(.enabled)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }
}

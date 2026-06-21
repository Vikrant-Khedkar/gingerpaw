import AgentWorkspace
import Foundation

@MainActor
public final class AppRuntime {
    public static let shared = AppRuntime()
    public let services: AppServices
    private let voiceSpeaker = VoiceSpeaker()
    private var didStart = false

    private init() {
        services = AppComposition.make()
    }

    public func start() {
        guard !didStart else { return }
        didStart = true

        // The flowoss CLI posts this when Claude speaks — the app does the TTS so the
        // cat + caption stay in exact sync with the audio.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("app.gingerpaw.speak"), object: nil, queue: .main
        ) { [voiceSpeaker] note in
            let text = note.userInfo?["text"] as? String ?? "Claude finished."
            let voice = note.userInfo?["voice"] as? String ?? ""
            let rate = Int(note.userInfo?["rate"] as? String ?? "0") ?? 0
            MainActor.assumeIsolated { voiceSpeaker.speak(text: text, voiceName: voice, rate: rate) }
        }
        services.coordinator.onStateChange = { [settings = services.settings, overlay = services.overlay, statusBar = services.statusBar] state in
            overlay.update(state: state, visible: settings.showPill)
            statusBar.update(state: state)
        }
        services.statusBar.update(state: services.coordinator.state)
        services.hotkeyMonitor.onPress = { [coordinator = services.coordinator] in
            coordinator.startRecording()
        }
        services.hotkeyMonitor.onRelease = { [coordinator = services.coordinator] in
            coordinator.stopRecordingAndProcess()
        }
        services.hotkeyMonitor.start()

        // Loopback IPC server so agents inside workspaces can drive the cockpit via MCP.
        MCPBridgeServer.shared.start()
    }
}

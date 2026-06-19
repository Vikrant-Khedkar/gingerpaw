import Foundation

@MainActor
public final class AppRuntime {
    public static let shared = AppRuntime()
    public let services: AppServices
    private var didStart = false

    private init() {
        services = AppComposition.make()
    }

    public func start() {
        guard !didStart else { return }
        didStart = true
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
    }
}

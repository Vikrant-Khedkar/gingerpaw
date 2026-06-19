import Dictation
import AppKit
import Settings
import SwiftUI

public struct MenuBarContent: View {
    @Bindable private var coordinator: DictationCoordinator
    @Bindable private var settings: FlowSettings

    public init(coordinator: DictationCoordinator, settings: FlowSettings) {
        self.coordinator = coordinator
        self.settings = settings
    }

    public var body: some View {
        Text(statusText)
        Divider()
        Text("Hold \(settings.hotkeyDisplay)")
        Text("Hotkey: \(settings.hotkeyDisplay)")
        Text("Model: \(settings.modelID)")
        Divider()
        SettingsLink()
        Button("Quit FlowOSS") {
            NSApplication.shared.terminate(nil)
        }
    }

    private var statusText: String {
        switch coordinator.state {
        case .idle:
            "Ready"
        case .recording:
            "Recording"
        case .processing:
            "Processing"
        case .inserting:
            "Pasting"
        case .copied:
            "Copied"
        case let .failed(message):
            "Failed: \(message)"
        }
    }
}

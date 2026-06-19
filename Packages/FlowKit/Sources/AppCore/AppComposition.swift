import Audio
import Dictation
import Hotkeys
import Overlay
import Permissions
import Settings
import TextInsertion
import TextProcessing
import Transcription

@MainActor
public struct AppServices {
    public let settings: FlowSettings
    public let permissions: PermissionCenter
    public let coordinator: DictationCoordinator
    public let hotkeyMonitor: RightOptionHotkeyMonitor
    public let overlay: DictationOverlayController
    public let statusBar: StatusBarController
}

@MainActor
public enum AppComposition {
    public static func make() -> AppServices {
        let settings = FlowSettings()
        let coordinator = DictationCoordinator(
            recorder: AudioRecorder(),
            transcriber: WhisperKitTranscriber {
                await MainActor.run { settings.modelID }
            },
            inserter: ClipboardTextInserter(),
            settings: settings,
            processor: MLXTextProcessor()
        )
        return AppServices(
            settings: settings,
            permissions: PermissionCenter(),
            coordinator: coordinator,
            hotkeyMonitor: RightOptionHotkeyMonitor(),
            overlay: DictationOverlayController(),
            statusBar: StatusBarController(coordinator: coordinator, settings: settings)
        )
    }
}

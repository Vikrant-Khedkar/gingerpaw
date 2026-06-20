import AppCore
import SwiftUI

@main
struct FlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var runtime = AppRuntime.shared

    var body: some Scene {
        WindowGroup {
            AppShellView(
                coordinator: runtime.services.coordinator,
                hotkeyMonitor: runtime.services.hotkeyMonitor,
                playground: runtime.services.playground,
                settings: runtime.services.settings,
                permissions: runtime.services.permissions
            )
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(settings: runtime.services.settings)
                .padding(28)
                .frame(width: 460, height: 420)
        }
    }
}

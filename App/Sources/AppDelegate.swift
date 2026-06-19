import AppCore
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        // swift-transformers' Hub flags VPN/constrained paths as "offline" and refuses to
        // download models. This env var disables that detection so model downloads work.
        setenv("CI_DISABLE_NETWORK_MONITOR", "1", 1)
        NSApp.setActivationPolicy(.regular)
        AppRuntime.shared.start()
    }
}

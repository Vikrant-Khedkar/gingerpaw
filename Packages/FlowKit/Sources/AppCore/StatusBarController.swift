import AppKit
import Dictation
import Settings

@MainActor
public final class StatusBarController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let coordinator: DictationCoordinator
    private let settings: FlowSettings
    private let statusMenuItem = NSMenuItem(title: "GingerPaw Ready", action: nil, keyEquivalent: "")

    public init(coordinator: DictationCoordinator, settings: FlowSettings) {
        self.coordinator = coordinator
        self.settings = settings
        configure()
    }

    public func update(state: DictationState) {
        item.button?.title = state.isBusy ? "Flow ●" : "Flow"
        item.button?.image = NSImage(systemSymbolName: state.isBusy ? "mic.fill" : "mic", accessibilityDescription: "GingerPaw")
        statusMenuItem.title = statusTitle(for: state)
    }

    private func configure() {
        item.button?.title = "Flow"
        item.button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "GingerPaw")
        item.button?.imagePosition = .imageLeading
        item.button?.toolTip = "GingerPaw"

        let menu = NSMenu()
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open GingerPaw", action: #selector(openApp), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Hotkey: \(settings.hotkeyDisplay)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Model: \(settings.modelID)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Enable Hotkey", action: #selector(requestInputMonitoring), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Request Accessibility", action: #selector(requestAccessibility), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit GingerPaw", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }
        self.item.menu = menu
    }

    @objc private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    @objc private func requestInputMonitoring() {
        CGRequestListenEventAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    @objc private func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func statusTitle(for state: DictationState) -> String {
        switch state {
        case .idle:
            "GingerPaw Ready"
        case .recording:
            "GingerPaw Recording"
        case .processing:
            "GingerPaw Processing"
        case .inserting:
            "GingerPaw Pasting"
        case .copied:
            "GingerPaw Copied"
        case let .failed(message):
            "GingerPaw Failed: \(message)"
        }
    }
}

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
        item.button?.image = Self.pawImage(tint: Self.tint(for: state))
        statusMenuItem.title = statusTitle(for: state)
    }

    private func configure() {
        item.button?.title = ""
        item.button?.image = Self.pawImage(tint: nil)
        item.button?.imagePosition = .imageOnly
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

    private static func tint(for state: DictationState) -> NSColor? {
        switch state {
        case .recording, .failed:
            NSColor(srgbRed: 0xFF / 255, green: 0x3B / 255, blue: 0x30 / 255, alpha: 1)
        case .processing, .inserting:
            NSColor(srgbRed: 0xFF / 255, green: 0x95 / 255, blue: 0, alpha: 1)
        case .copied:
            NSColor(srgbRed: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255, alpha: 1)
        case .idle:
            nil // template — adapts to light/dark menu bar
        }
    }

    /// The ginger paw, drawn for the menu bar. Template (adaptive) when tint is nil, else solid-colored.
    private static func pawImage(tint: NSColor?) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            (tint ?? .black).setFill()
            let s = 18.0 / 24.0
            let t = NSAffineTransform()
            t.scale(by: s)
            t.concat()

            let pad = NSBezierPath()
            pad.move(to: NSPoint(x: 12, y: 12.5))
            pad.curve(to: NSPoint(x: 18.6, y: 17.7), controlPoint1: NSPoint(x: 16.2, y: 12.5), controlPoint2: NSPoint(x: 18.6, y: 15.1))
            pad.curve(to: NSPoint(x: 14.7, y: 20.1), controlPoint1: NSPoint(x: 18.6, y: 19.8), controlPoint2: NSPoint(x: 16.5, y: 20.8))
            pad.curve(to: NSPoint(x: 9.3, y: 20.1), controlPoint1: NSPoint(x: 13.0, y: 19.4), controlPoint2: NSPoint(x: 11.0, y: 19.4))
            pad.curve(to: NSPoint(x: 5.4, y: 17.7), controlPoint1: NSPoint(x: 7.5, y: 20.8), controlPoint2: NSPoint(x: 5.4, y: 19.8))
            pad.curve(to: NSPoint(x: 12, y: 12.5), controlPoint1: NSPoint(x: 5.4, y: 15.1), controlPoint2: NSPoint(x: 7.8, y: 12.5))
            pad.close()
            pad.fill()

            for (cx, cy, rx, ry) in [(6.4, 11.0, 1.9, 2.5), (10.3, 8.2, 2.0, 2.7), (14.0, 8.2, 2.0, 2.7), (17.7, 11.0, 1.9, 2.5)] {
                NSBezierPath(ovalIn: NSRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)).fill()
            }
            return true
        }
        image.isTemplate = (tint == nil)
        return image
    }
}

import AppKit
import SwiftUI

/// Opens (or re-focuses) the standalone Agent Workspace window.
@MainActor
public enum AgentWorkspaceWindow {
    private static var controller: NSWindowController?

    public static func show() {
        if let window = controller?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: WorkspaceRootView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Agent Workspace"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1000, height: 640))
        window.center()
        controller = NSWindowController(window: window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

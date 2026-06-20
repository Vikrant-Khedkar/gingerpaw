import AppKit
import ApplicationServices
import Foundation

public struct ClipboardSnapshot: Sendable {
    let string: String?
}

public final class ClipboardTextInserter: TextInserter, @unchecked Sendable {
    private let pasteboard: NSPasteboard
    private let pasteDelay: Duration

    public init(pasteboard: NSPasteboard = .general, pasteDelay: Duration = .milliseconds(150)) {
        self.pasteboard = pasteboard
        self.pasteDelay = pasteDelay
    }

    public func insert(_ text: String, restoreClipboard: Bool) async -> InsertionOutcome {
        // No editable text field focused? Don't paste into nothing — leave it on the
        // clipboard so the user can paste it themselves, and report .copied.
        guard Self.focusedElementIsEditable() else {
            setClipboard(text)
            return .copied
        }
        let snapshot = snapshot()
        setClipboard(text)
        let pasted = sendPaste()
        if restoreClipboard {
            try? await Task.sleep(for: pasteDelay)
            restore(snapshot)
        }
        return pasted ? .pasted : .copied
    }

    /// Whether the system-wide focused UI element accepts typed text (so ⌘V will land).
    private static func focusedElementIsEditable() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID()
        else { return false }
        let el = element as! AXUIElement

        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
        let editableRoles: Set<String> = [
            kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String,
        ]
        if let roleString = role as? String, editableRoles.contains(roleString) {
            return true
        }

        // Fallback for custom/editable views: is the value attribute writable?
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(el, kAXValueAttribute as CFString, &settable) == .success {
            return settable.boolValue
        }
        return false
    }

    public func copy(_ text: String) async -> InsertionOutcome {
        setClipboard(text)
        return .copied
    }

    private func snapshot() -> ClipboardSnapshot {
        ClipboardSnapshot(string: pasteboard.string(forType: .string))
    }

    private func restore(_ snapshot: ClipboardSnapshot) {
        pasteboard.clearContents()
        if let string = snapshot.string {
            pasteboard.setString(string, forType: .string)
        }
    }

    private func setClipboard(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func sendPaste() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}

import AppKit
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
        let snapshot = snapshot()
        setClipboard(text)
        let pasted = sendPaste()
        if restoreClipboard {
            try? await Task.sleep(for: pasteDelay)
            restore(snapshot)
        }
        return pasted ? .pasted : .copied
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

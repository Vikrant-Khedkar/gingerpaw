import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class RightOptionHotkeyMonitor {
    public var onPress: (() -> Void)?
    public var onRelease: (() -> Void)?
    public private(set) var statusText = "Starting hotkey monitor"
    public private(set) var lastEventText = "No hotkey event seen"

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?
    private var isPressed = false

    public init() {}

    public func start() {
        installEventTap()
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.installEventTap()
            }
        }
    }

    public func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        removeEventTap()
    }

    private func installEventTap() {
        guard eventTap == nil else {
            statusText = "Listening"
            return
        }

        guard CGPreflightListenEventAccess() else {
            statusText = "Waiting for Input Monitoring"
            CGRequestListenEventAccess()
            return
        }

        let mask = (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<RightOptionHotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in
                monitor.handle(event, type: type)
            }
            return Unmanaged.passUnretained(event)
        }

        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let tap else {
            statusText = "Event tap failed, retrying"
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        statusText = "Listening"
    }

    private func removeEventTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
        isPressed = false
    }

    private func handle(_ event: CGEvent, type: CGEventType) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            statusText = "Listening"
            return
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let isOptionEvent = keyCode == 58 || keyCode == 61
        let isFnEvent = keyCode == 63 || flags.contains(.maskSecondaryFn)
        guard isOptionEvent || isFnEvent else { return }

        let pressed = isOptionEvent ? flags.contains(.maskAlternate) : flags.contains(.maskSecondaryFn)
        lastEventText = "\(isOptionEvent ? "Option" : "Fn") \(pressed ? "down" : "up")"
        if pressed, !isPressed {
            isPressed = true
            onPress?()
        } else if !pressed, isPressed {
            isPressed = false
            onRelease?()
        }
    }
}

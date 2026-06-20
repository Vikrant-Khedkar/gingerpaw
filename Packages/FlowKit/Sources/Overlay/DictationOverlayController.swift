import AppKit
import Dictation

@MainActor
public final class DictationOverlayController {
    private var panel: NSPanel?
    private let container = NSView()   // transparent wrapper with margin so the purr scale never clips
    private let pill = NSView()        // the dark capsule itself
    private let iconView = NSImageView()
    private let pawView = PawView()
    private let titleField = NSTextField(labelWithString: "")
    private var stack: NSStackView!
    private let margin: CGFloat = 8

    public init() {}

    public func update(state: DictationState, visible: Bool) {
        guard visible, state.isBusy || state == .copied else {
            panel?.orderOut(nil)
            return
        }
        let panel = panel ?? makePanel()
        apply(state)
        position(panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        container.wantsLayer = true
        container.layer?.masksToBounds = false

        pill.wantsLayer = true
        pill.layer?.cornerRadius = 22
        pill.layer?.masksToBounds = true
        pill.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(pill)

        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        iconView.contentTintColor = .white
        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.textColor = .white

        stack = NSStackView(views: [iconView, pawView, titleField])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(stack)

        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            pill.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            pill.heightAnchor.constraint(equalToConstant: 44),
            stack.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -18),
            stack.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 19),
            iconView.heightAnchor.constraint(equalToConstant: 19),
            pawView.widthAnchor.constraint(equalToConstant: 19),
            pawView.heightAnchor.constraint(equalToConstant: 19),
        ])

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = container
        return panel
    }

    private func apply(_ state: DictationState) {
        let recording: Bool = { if case .recording = state { return true } else { return false } }()

        pawView.isHidden = !recording
        iconView.isHidden = recording
        iconView.removeAllSymbolEffects()
        if !recording {
            iconView.image = NSImage(systemSymbolName: icon(for: state), accessibilityDescription: title(for: state))
            switch state {
            case .processing, .inserting:
                // living waveform — bars light up sequentially while transcribing/pasting
                iconView.addSymbolEffect(.variableColor.iterative.nonReversing, options: .repeating)
            case .copied:
                iconView.addSymbolEffect(.bounce, options: .nonRepeating)
            default:
                break
            }
        }
        titleField.stringValue = title(for: state)
        pill.layer?.backgroundColor = color(for: state).cgColor

        setPurr(recording)

        // size the window to the pill + margin so the purr scale never clips at the edges
        if let panel {
            stack.layoutSubtreeIfNeeded()
            let pillWidth = stack.fittingSize.width + 36
            panel.setContentSize(NSSize(width: pillWidth + margin * 2, height: 44 + margin * 2))
            pill.layer?.cornerRadius = 22
        }
    }

    private func setPurr(_ on: Bool) {
        let key = "purr"
        guard let layer = pill.layer else { return }
        layer.removeAnimation(forKey: key)
        guard on else { return }
        let purr = CABasicAnimation(keyPath: "transform.scale")
        purr.fromValue = 1.0
        purr.toValue = 1.02
        purr.duration = 0.5
        purr.autoreverses = true
        purr.repeatCount = .infinity
        purr.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.anchorPoint = NSPoint(x: 0.5, y: 0.5)
        layer.add(purr, forKey: key)
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let w = panel.frame.width
        panel.setFrameOrigin(NSPoint(x: frame.midX - w / 2, y: frame.minY + 32))
    }

    private func title(for state: DictationState) -> String {
        switch state {
        case .recording: "Recording"
        case .processing: "Transcribing"
        case .inserting: "Pasting"
        case .copied: "Copied to clipboard"
        case .failed: "Failed"
        case .idle: "Ready"
        }
    }

    private func icon(for state: DictationState) -> String {
        switch state {
        case .recording: "mic.fill"
        case .processing: "waveform"
        case .inserting: "arrow.down.doc"
        case .copied: "checkmark"
        case .failed: "exclamationmark.triangle.fill"
        case .idle: "mic"
        }
    }

    private func color(for state: DictationState) -> NSColor {
        switch state {
        case .recording, .failed:
            NSColor(srgbRed: 0xFF / 255, green: 0x3B / 255, blue: 0x30 / 255, alpha: 1)
        default:
            NSColor(srgbRed: 20 / 255, green: 18 / 255, blue: 30 / 255, alpha: 0.88)
        }
    }
}

/// The ginger paw print shown inside the pill while recording.
private final class PawView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let ginger = NSColor(srgbRed: 0xF4 / 255, green: 0xC8 / 255, blue: 0x9B / 255, alpha: 1)
        ginger.setFill()

        let s = min(bounds.width, bounds.height) / 24.0
        let t = NSAffineTransform()
        t.scale(by: s)
        t.concat()

        // main pad
        let pad = NSBezierPath()
        pad.move(to: NSPoint(x: 12, y: 12.5))
        pad.curve(to: NSPoint(x: 18.6, y: 17.7), controlPoint1: NSPoint(x: 16.2, y: 12.5), controlPoint2: NSPoint(x: 18.6, y: 15.1))
        pad.curve(to: NSPoint(x: 14.7, y: 20.1), controlPoint1: NSPoint(x: 18.6, y: 19.8), controlPoint2: NSPoint(x: 16.5, y: 20.8))
        pad.curve(to: NSPoint(x: 9.3, y: 20.1), controlPoint1: NSPoint(x: 13.0, y: 19.4), controlPoint2: NSPoint(x: 11.0, y: 19.4))
        pad.curve(to: NSPoint(x: 5.4, y: 17.7), controlPoint1: NSPoint(x: 7.5, y: 20.8), controlPoint2: NSPoint(x: 5.4, y: 19.8))
        pad.curve(to: NSPoint(x: 12, y: 12.5), controlPoint1: NSPoint(x: 5.4, y: 15.1), controlPoint2: NSPoint(x: 7.8, y: 12.5))
        pad.close()
        pad.fill()

        // toes
        for (cx, cy, rx, ry) in [(6.4, 11.0, 1.9, 2.5), (10.3, 8.2, 2.0, 2.7), (14.0, 8.2, 2.0, 2.7), (17.7, 11.0, 1.9, 2.5)] {
            NSBezierPath(ovalIn: NSRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)).fill()
        }
    }
}

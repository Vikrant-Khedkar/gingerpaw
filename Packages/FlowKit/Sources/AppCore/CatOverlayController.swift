import AppKit

/// Talking-cat overlay shown when Claude Code speaks. A transparent ginger cat
/// (animated mouth) with a compact pill above it whose caption scrolls
/// marquee-style. Floats bottom-center for the duration of the speech.
@MainActor
public final class CatOverlayController {
    private var panel: NSPanel?
    private let catView = NSImageView()
    private let pill = NSView()
    private let clip = NSView()
    private let label = NSTextField(labelWithString: "")
    private var mouthTimer: Timer?
    private var scrollTimer: Timer?

    private let openImage = NSImage(named: "cat-open")
    private let closedImage = NSImage(named: "cat-closed")
    private var mouthOpen = false

    public init() {}

    public func begin(text: String) {
        let panel = panel ?? makePanel()
        self.panel = panel
        label.stringValue = text
        catView.image = closedImage

        sizeAndPosition(panel)
        panel.contentView?.layoutSubtreeIfNeeded()
        setupMarquee()

        panel.alphaValue = 1
        panel.orderFrontRegardless()
        startMouth()
    }

    public func finish() {
        mouthTimer?.invalidate(); mouthTimer = nil
        scrollTimer?.invalidate(); scrollTimer = nil
        catView.image = closedImage
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 }) {
            panel.orderOut(nil)
        }
    }

    private func setupMarquee() {
        label.sizeToFit()
        let clipW = clip.bounds.width
        let clipH = clip.bounds.height
        var f = label.frame
        f.origin.y = (clipH - f.height) / 2
        scrollTimer?.invalidate(); scrollTimer = nil
        if f.width <= clipW {
            f.origin.x = (clipW - f.width) / 2     // fits — center, no scroll
            label.frame = f
        } else {
            f.origin.x = clipW                      // start just off the right edge
            label.frame = f
            startScroll(clipW: clipW)
        }
    }

    private func startScroll(clipW: CGFloat) {
        let speed: CGFloat = 80
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                var f = label.frame
                f.origin.x -= speed * 0.016
                if f.maxX < 0 { f.origin.x = clipW } // loop
                label.frame = f
            }
        }
    }

    private func startMouth() {
        mouthTimer?.invalidate(); mouthOpen = false
        mouthTimer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: true) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                mouthOpen.toggle()
                catView.image = mouthOpen ? openImage : closedImage
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 192),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let container = NSView()

        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        pill.layer?.cornerRadius = 18
        pill.layer?.borderWidth = 0.5
        pill.layer?.borderColor = NSColor.separatorColor.cgColor
        pill.layer?.shadowColor = NSColor.black.cgColor
        pill.layer?.shadowOpacity = 0.18
        pill.layer?.shadowRadius = 8
        pill.layer?.shadowOffset = CGSize(width: 0, height: -2)
        pill.translatesAutoresizingMaskIntoConstraints = false

        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(clip)

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byClipping
        label.translatesAutoresizingMaskIntoConstraints = true
        label.autoresizingMask = []
        clip.addSubview(label) // positioned with manual frame for scrolling

        catView.imageScaling = .scaleProportionallyUpOrDown
        catView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(pill)
        container.addSubview(catView)

        NSLayoutConstraint.activate([
            pill.topAnchor.constraint(equalTo: container.topAnchor),
            pill.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            pill.widthAnchor.constraint(equalToConstant: 300),
            pill.heightAnchor.constraint(equalToConstant: 36),
            pill.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            pill.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),

            clip.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 16),
            clip.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -16),
            clip.topAnchor.constraint(equalTo: pill.topAnchor),
            clip.bottomAnchor.constraint(equalTo: pill.bottomAnchor),

            catView.topAnchor.constraint(equalTo: pill.bottomAnchor, constant: 4),
            catView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            catView.widthAnchor.constraint(equalToConstant: 150),
            catView.heightAnchor.constraint(equalToConstant: 150),
            catView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            catView.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            catView.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
        ])

        panel.contentView = container
        return panel
    }

    private func sizeAndPosition(_ panel: NSPanel) {
        guard let container = panel.contentView else { return }
        container.layoutSubtreeIfNeeded()
        let size = container.fittingSize
        panel.setContentSize(size)
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 36))
        }
    }
}

import AppKit

/// The talking-cat overlay shown when Claude Code speaks. Transparent ginger cat
/// (mouth alternates open/closed) with a speech bubble that reveals text in sync
/// with the speech. Cat is bottom-anchored so it never shifts as the bubble fills.
@MainActor
public final class CatOverlayController {
    private var panel: NSPanel?
    private let catView = NSImageView()
    private let bubble = NSView()
    private let bubbleText = NSTextField(wrappingLabelWithString: "")
    private var frameTimer: Timer?

    private let openImage = NSImage(named: "cat-open")
    private let closedImage = NSImage(named: "cat-closed")
    private var mouthOpen = false
    private var fullText = ""

    public init() {}

    /// Show the cat sized for `text`, starting empty; speech then drives `reveal`/`finish`.
    public func begin(text: String) {
        fullText = text
        let panel = panel ?? makePanel()
        self.panel = panel

        bubbleText.stringValue = text          // size for the full caption
        panel.contentView?.layoutSubtreeIfNeeded()
        sizeAndPosition(panel)
        bubbleText.stringValue = ""            // then reveal progressively

        catView.image = closedImage
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        startMouth()
    }

    /// Caption up to the currently-spoken character.
    public func reveal(upTo length: Int) {
        let clamped = max(0, min(length, fullText.count))
        bubbleText.stringValue = String(fullText.prefix(clamped))
    }

    public func finish() {
        bubbleText.stringValue = fullText
        frameTimer?.invalidate(); frameTimer = nil
        catView.image = closedImage
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        } completionHandler: { panel.orderOut(nil) }
    }

    private func startMouth() {
        frameTimer?.invalidate()
        mouthOpen = false
        frameTimer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: true) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                mouthOpen.toggle()
                catView.image = mouthOpen ? openImage : closedImage
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 230),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let container = NSView()

        bubble.wantsLayer = true
        bubble.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        bubble.layer?.cornerRadius = 14
        bubble.layer?.borderWidth = 0.5
        bubble.layer?.borderColor = NSColor.separatorColor.cgColor
        bubble.translatesAutoresizingMaskIntoConstraints = false

        bubbleText.font = .systemFont(ofSize: 13, weight: .medium)
        bubbleText.textColor = .labelColor
        bubbleText.preferredMaxLayoutWidth = 236
        bubbleText.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(bubbleText)

        catView.imageScaling = .scaleProportionallyUpOrDown
        catView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(bubble)
        container.addSubview(catView)

        NSLayoutConstraint.activate([
            // cat pinned to the bottom — never moves while the bubble fills
            catView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            catView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            catView.widthAnchor.constraint(equalToConstant: 150),
            catView.heightAnchor.constraint(equalToConstant: 150),

            bubble.topAnchor.constraint(equalTo: container.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: catView.topAnchor, constant: -6),
            bubble.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            bubble.widthAnchor.constraint(lessThanOrEqualToConstant: 260),
            // containment so the container actually has a non-zero width via fittingSize
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            catView.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            catView.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),

            bubbleText.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            bubbleText.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
            bubbleText.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 9),
            bubbleText.bottomAnchor.constraint(lessThanOrEqualTo: bubble.bottomAnchor, constant: -9),
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

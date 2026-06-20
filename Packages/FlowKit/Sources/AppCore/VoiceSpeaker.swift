import AppKit

/// Speaks a notification via macOS `say` (run as a subprocess so the app knows
/// exactly when it finishes) and shows the talking cat for that duration.
/// `say` has no per-word callback, so the caption shows in full.
@MainActor
public final class VoiceSpeaker {
    private let cat = CatOverlayController()
    private var process: Process?

    public init() {}

    public func speak(text: String, voiceName: String, rate: Int) {
        process?.terminate()
        cat.begin(text: text) // caption scrolls marquee-style in the pill

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        var args: [String] = []
        if !voiceName.isEmpty { args += ["-v", voiceName] }
        if rate > 0 { args += ["-r", String(rate)] }
        args.append(text)
        process.arguments = args
        process.terminationHandler = { _ in
            Task { @MainActor [weak self] in self?.cat.finish() }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            cat.finish()
        }
    }
}

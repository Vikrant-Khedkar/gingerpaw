import AppKit
import AVFoundation
import Foundation

private struct FBClick { let elapsed: Double; let element: String; let frame: String }
private struct FBFrame { let elapsed: Double; let file: String }

extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// Records a feedback session in a worktree: mic audio (16 kHz mono WAV), semantic clicks
/// from the WebView, and PNG snapshots on click + interval. On finish, transcribes the audio
/// (via the injected seam) and writes a SESSION.md the fix agent reads (frames attached).
@MainActor
@Observable
final class FeedbackRecorder {
    var isRecording = false
    var clickCount = 0
    var frameCount = 0

    private var recorder: AVAudioRecorder?
    private var audioURL: URL?
    private var sessionDir = ""
    private var t0 = Date()
    private var clicks: [FBClick] = []
    private var frames: [FBFrame] = []
    private var frameIndex = 0
    private var timer: Timer?
    private weak var controller: WebPreviewController?

    /// Request mic access, then begin. Returns false if denied.
    func start(controller: WebPreviewController, worktreePath: String) async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else { return false }

        let stamp = Int(Date().timeIntervalSince1970)
        sessionDir = (worktreePath as NSString).appendingPathComponent("feedback/session-\(stamp)")
        try? FileManager.default.createDirectory(atPath: sessionDir + "/frames", withIntermediateDirectories: true)
        appendExclude(worktreePath)   // keep feedback/ out of the diff/PR

        let url = URL(fileURLWithPath: sessionDir + "/audio.wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        guard let rec = try? AVAudioRecorder(url: url, settings: settings), rec.record() else { return false }

        recorder = rec; audioURL = url; t0 = Date()
        clicks = []; frames = []; frameIndex = 0; clickCount = 0; frameCount = 0
        self.controller = controller
        controller.onClick = { [weak self] ev in self?.onClick(ev) }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.snapshot(clickElement: nil) }
        }
        isRecording = true
        snapshot(clickElement: nil)   // initial frame
        return true
    }

    private func onClick(_ ev: ClickEvent) {
        let el = ev.text.isEmpty ? ev.tag.lowercased() : "\(ev.tag.lowercased()) '\(ev.text)'"
        clickCount += 1
        snapshot(clickElement: el)
    }

    private func snapshot(clickElement: String?) {
        let elapsed = Date().timeIntervalSince(t0)
        let idx = frameIndex; frameIndex += 1
        let rel = "frames/frame-\(String(format: "%04d", idx)).png"
        let dir = sessionDir
        Task {
            guard let img = await controller?.snapshot(), let png = img.pngData() else { return }
            try? png.write(to: URL(fileURLWithPath: dir + "/" + rel))
            frames.append(FBFrame(elapsed: elapsed, file: rel))
            frameCount = frames.count
            if let el = clickElement { clicks.append(FBClick(elapsed: elapsed, element: el, frame: rel)) }
        }
    }

    /// Stop, transcribe, and write SESSION.md. Returns (sessionDir, relative md path) or nil.
    func finish() async -> (dir: String, mdRelToWorktree: String)? {
        guard isRecording, let audioURL else { return nil }
        recorder?.stop(); recorder = nil
        timer?.invalidate(); timer = nil
        controller?.onClick = nil
        isRecording = false

        let transcript = await FeedbackTranscription.transcribe?(audioURL) ?? ""
        let md = buildMarkdown(transcript: transcript)
        let mdPath = sessionDir + "/SESSION.md"
        try? md.write(toFile: mdPath, atomically: true, encoding: .utf8)

        // worktree-relative path for the agent prompt
        let session = (sessionDir as NSString).lastPathComponent
        return (sessionDir, "feedback/\(session)/SESSION.md")
    }

    func cancel() {
        recorder?.stop(); recorder = nil
        timer?.invalidate(); timer = nil
        controller?.onClick = nil
        isRecording = false
    }

    private func buildMarkdown(transcript: String) -> String {
        func ts(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
        let interactions = clicks.isEmpty
            ? "_(no clicks recorded)_"
            : clicks.map { "- `\(ts($0.elapsed))` clicked **\($0.element)** — frame: `\($0.frame)`" }.joined(separator: "\n")
        let transcriptBlock = transcript.isEmpty ? "_(transcription unavailable)_" : transcript
        return """
        # User feedback session

        The user walked through the running app and spoke their feedback while clicking. \
        Screenshots are in `frames/` — **open them** to see exactly what they saw at each moment.

        ## What they said (voice transcript)
        \(transcriptBlock)

        ## Interaction log
        \(interactions)

        ## Frames
        \(frames.isEmpty ? "_(none)_" : frames.map { "- `\($0.file)` @ `\(ts($0.elapsed))`" }.joined(separator: "\n"))
        """
    }

    private func appendExclude(_ worktreePath: String) {
        var p = GitWorktrees.runRaw(["-C", worktreePath, "rev-parse", "--git-path", "info/exclude"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        if !p.hasPrefix("/") { p = (worktreePath as NSString).appendingPathComponent(p) }
        let existing = (try? String(contentsOfFile: p, encoding: .utf8)) ?? ""
        guard !existing.contains("feedback/") else { return }
        try? (existing + (existing.isEmpty ? "" : "\n") + "feedback/\n").write(toFile: p, atomically: true, encoding: .utf8)
    }
}

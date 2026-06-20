import Foundation

public protocol SpeechService: Sendable {
    func speak(_ text: String, voice: String, rate: Int)
}

/// Speaks via macOS `say`, **detached** — fires the speech in the background and
/// returns immediately so a Claude hook never blocks waiting for audio to finish.
public struct SaySpeechService: SpeechService {
    public init() {}

    public func speak(_ text: String, voice: String, rate: Int) {
        var sayCommand = "say"
        if !voice.isEmpty { sayCommand += " -v \(Self.shellQuote(voice))" }
        if rate > 0 { sayCommand += " -r \(rate)" }
        sayCommand += " \(Self.shellQuote(text))"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // `nohup … &` detaches say so it survives this process exiting
        process.arguments = ["-c", "nohup \(sayCommand) >/dev/null 2>&1 &"]
        try? process.run()
        process.waitUntilExit() // returns instantly — the `&` backgrounded say
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

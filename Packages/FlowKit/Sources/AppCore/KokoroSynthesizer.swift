import Foundation

/// Synthesizes speech with Kokoro (kokoro-onnx) by shelling out to a venv Python
/// **once per utterance** — no long-running server. Returns a WAV the app plays
/// itself, so the cat can sync to its real duration. Falls back to `say` upstream
/// when Kokoro isn't installed.
public actor KokoroSynthesizer {
    public init() {}

    struct Paths { let python: String; let model: String; let voices: String }

    public static var isAvailable: Bool { locate() != nil }

    public func synthesize(text: String, voice: String, speed: Double) async throws -> URL {
        guard let p = Self.locate() else { throw KokoroError.notInstalled }
        let script = try Self.writeScript()
        defer { try? FileManager.default.removeItem(at: script) }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("gingerpaw-kokoro-\(UUID().uuidString).wav")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: p.python)
        process.arguments = [script.path, p.model, p.voices, out.path, voice, String(speed), text]
        let err = Pipe()
        process.standardError = err
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw KokoroError.failed(e.isEmpty ? "kokoro exited \(process.terminationStatus)" : e)
        }
        return out
    }

    /// Looks for a ready Kokoro install (venv + model + voices). Prefers the app's
    /// own support dir, falls back to the standalone test harness.
    private static func locate() -> Paths? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let roots = [
            "\(home)/Library/Application Support/GingerPaw/kokoro",
            "\(home)/kokoro-tts-test",
        ]
        let fm = FileManager.default
        for r in roots {
            let p = Paths(python: "\(r)/.venv/bin/python",
                          model: "\(r)/models/kokoro-v1.0.fp16.onnx",
                          voices: "\(r)/models/voices-v1.0.bin")
            if fm.fileExists(atPath: p.python), fm.fileExists(atPath: p.model), fm.fileExists(atPath: p.voices) {
                return p
            }
        }
        return nil
    }

    private static func writeScript() throws -> URL {
        let script = """
        import sys
        import soundfile as sf
        from kokoro_onnx import Kokoro
        model, voices, out, voice, speed, text = sys.argv[1:7]
        k = Kokoro(model, voices)
        samples, sr = k.create(text, voice=voice, speed=float(speed), lang="en-us")
        sf.write(out, samples, sr)
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gingerpaw-kokoro-\(UUID().uuidString).py")
        try script.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

public enum KokoroError: Error {
    case notInstalled
    case failed(String)
}

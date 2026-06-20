import Foundation

/// Runs Moonshine (ONNX) by shelling out to Python — for internal A/B testing
/// against WhisperKit. Requires `pip install useful-moonshine-onnx`.
public actor MoonshineTranscriber: SpeechTranscriber {
    private let modelProvider: @Sendable () async -> String

    public init(modelProvider: @escaping @Sendable () async -> String) {
        self.modelProvider = modelProvider
    }

    public func transcribe(audioURL: URL) async throws -> String {
        let model = await modelProvider()
        let scriptURL = try Self.writeScript()
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", scriptURL.path, audioURL.path, model]
        process.environment = Self.pythonEnvironment()

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()

        let data = out.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if process.terminationStatus != 0 {
            let errText = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw MoonshineError.failed(errText.isEmpty ? "moonshine exited \(process.terminationStatus)" : errText)
        }
        return text
    }

    private static func writeScript() throws -> URL {
        let script = """
        import sys
        import moonshine_onnx as m
        out = m.transcribe(sys.argv[1], sys.argv[2])
        sys.stdout.write(out[0] if isinstance(out, list) else str(out))
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gingerpaw-moonshine-\(UUID().uuidString).py")
        try script.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func pythonEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let additions = [
            "\(home)/.pyenv/shims", "\(home)/.local/bin",
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
        ]
        env["PATH"] = (additions + [env["PATH"] ?? ""]).filter { !$0.isEmpty }.joined(separator: ":")
        return env
    }
}

public enum MoonshineError: Error {
    case failed(String)
}

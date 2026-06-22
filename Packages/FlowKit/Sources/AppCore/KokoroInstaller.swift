import Foundation

/// One-tap setup for the Kokoro neural voice: creates an isolated Python venv,
/// installs kokoro-onnx, and downloads the model into the app-support dir that
/// KokoroSynthesizer looks in. Opt-in (~200MB) — until then GingerPaw uses `say`.
@MainActor
public enum KokoroInstaller {
    public static let root = NSHomeDirectory() + "/Library/Application Support/GingerPaw/kokoro"

    public static var isInstalled: Bool { KokoroSynthesizer.isAvailable }

    /// Runs the bootstrap, streaming human-readable progress lines to `progress`.
    public static func install(progress: @escaping @MainActor (String) -> Void) async throws {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let status: Int32 = try await withCheckedThrowingContinuation { cont in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = ["-lc", bootstrapScript]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                let lines = text.split(whereSeparator: \.isNewline).map(String.init)
                Task { @MainActor in lines.forEach { progress($0) } }
            }
            process.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                cont.resume(returning: proc.terminationStatus)
            }
            do { try process.run() } catch { cont.resume(throwing: error) }
        }
        guard status == 0 else { throw KokoroError.failed("Kokoro setup failed (exit \(status))") }
    }

    private static var bootstrapScript: String {
        """
        set -e
        DIR="\(root)"
        mkdir -p "$DIR/models"
        PY="$(command -v python3 || true)"
        [ -n "$PY" ] || { echo "python3 not found — install Xcode Command Line Tools first"; exit 1; }
        echo "Setting up Python environment…"
        [ -d "$DIR/.venv" ] || "$PY" -m venv "$DIR/.venv"
        "$DIR/.venv/bin/pip" install --quiet --upgrade pip
        echo "Installing kokoro-onnx (this takes a minute)…"
        "$DIR/.venv/bin/pip" install --quiet kokoro-onnx soundfile
        # Download to .tmp then rename, so an interrupted download never leaves a corrupt model.
        if [ ! -f "$DIR/models/kokoro-v1.0.fp16.onnx" ]; then
          echo "Downloading voice model (~170MB)…"
          curl -L --fail -o "$DIR/models/kokoro-v1.0.fp16.onnx.tmp" "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.fp16.onnx"
          mv "$DIR/models/kokoro-v1.0.fp16.onnx.tmp" "$DIR/models/kokoro-v1.0.fp16.onnx"
        fi
        if [ ! -f "$DIR/models/voices-v1.0.bin" ]; then
          echo "Downloading voices…"
          curl -L --fail -o "$DIR/models/voices-v1.0.bin.tmp" "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin"
          mv "$DIR/models/voices-v1.0.bin.tmp" "$DIR/models/voices-v1.0.bin"
        fi
        echo "Kokoro ready."
        """
    }
}

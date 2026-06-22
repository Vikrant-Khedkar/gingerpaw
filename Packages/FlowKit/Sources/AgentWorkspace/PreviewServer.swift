import Foundation

/// Runs the app's dev server as a managed background process in the worktree, polls until
/// it answers on the port, then publishes the URL. Stops cleanly (terminate) on demand.
@MainActor
@Observable
final class PreviewServer {
    enum State: Equatable {
        case idle, starting, running(URL), failed(String)
    }

    var state: State = .idle
    private(set) var log = ""
    private var process: Process?

    func start(command: String, port: Int, cwd: String) {
        stop()
        state = .starting
        log = ""

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env = ProcessInfo.processInfo.environment
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-lc", command]
        p.environment = env
        p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            Task { @MainActor in self.appendLog(s) }
        }
        p.terminationHandler = { _ in
            Task { @MainActor in self.serverExited() }
        }
        process = p
        do { try p.run() } catch { state = .failed("Couldn't launch: \(error.localizedDescription)"); return }

        guard let url = URL(string: "http://localhost:\(port)") else { state = .failed("bad port"); return }
        Task { await waitReady(url) }
    }

    func stop() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        state = .idle
    }

    var isRunning: Bool { if case .running = state { return true }; return false }

    private func appendLog(_ s: String) {
        log += s
        if log.count > 8000 { log = String(log.suffix(6000)) }
    }

    private func serverExited() {
        switch state {
        case .starting, .running:
            state = .failed("Server exited.\n" + String(log.suffix(400)))
        default:
            break
        }
        process = nil
    }

    private func waitReady(_ url: URL) async {
        for _ in 0..<60 {
            if process == nil { return }
            if case .running = state { return }
            if await Self.probe(url) {
                if process != nil { state = .running(url) }
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
        if case .starting = state { state = .failed("Server didn't respond on \(url.absoluteString)") }
    }

    private nonisolated static func probe(_ url: URL) async -> Bool {
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        req.httpMethod = "HEAD"
        return await withCheckedContinuation { cont in
            let task = URLSession.shared.dataTask(with: req) { _, resp, err in
                cont.resume(returning: resp != nil || err == nil)
            }
            task.resume()
        }
    }
}

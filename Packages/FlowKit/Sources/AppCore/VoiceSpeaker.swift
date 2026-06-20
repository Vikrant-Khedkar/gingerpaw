import AgentNotifications
import AppKit

/// Speaks a notification and shows the talking cat for its duration.
/// Two engines: macOS `say` (zero-dep, instant) and Kokoro neural TTS (better
/// voice, generated to a WAV then played with `afplay`). The cat is shown the
/// moment audio starts and hidden when the player process exits — exact sync
/// either way.
@MainActor
public final class VoiceSpeaker {
    private let cat = CatOverlayController()
    private let kokoro = KokoroSynthesizer()
    private var process: Process?
    private var generation = 0

    public init() {}

    public func speak(text: String, voiceName: String, rate: Int) {
        let settings = VoiceSettings.load()
        if settings.ttsEngine == "kokoro" {
            speakKokoro(text: text, settings: settings, fallbackVoice: voiceName, fallbackRate: rate)
        } else {
            speakSay(text: text, voiceName: voiceName, rate: rate)
        }
    }

    private func speakKokoro(text: String, settings: VoiceSettings, fallbackVoice: String, fallbackRate: Int) {
        generation += 1
        let gen = generation
        process?.terminate()
        let voice = settings.kokoroVoice
        let speed = settings.kokoroSpeed
        Task { [weak self] in
            guard let self else { return }
            do {
                let wav = try await kokoro.synthesize(text: text, voice: voice, speed: speed)
                await MainActor.run {
                    guard gen == self.generation else { try? FileManager.default.removeItem(at: wav); return }
                    self.playWav(wav, caption: text)
                }
            } catch {
                await MainActor.run {
                    guard gen == self.generation else { return }
                    self.speakSay(text: text, voiceName: fallbackVoice, rate: fallbackRate)
                }
            }
        }
    }

    private func playWav(_ wav: URL, caption: String) {
        cat.begin(text: caption)
        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = [wav.path]
        player.terminationHandler = { _ in
            try? FileManager.default.removeItem(at: wav)
            Task { @MainActor [weak self] in self?.cat.finish() }
        }
        do {
            try player.run()
            self.process = player
        } catch {
            try? FileManager.default.removeItem(at: wav)
            cat.finish()
        }
    }

    private func speakSay(text: String, voiceName: String, rate: Int) {
        generation += 1
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

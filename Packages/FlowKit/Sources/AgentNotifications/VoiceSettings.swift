import Foundation

/// Voice-notification preferences, stored in a UserDefaults suite shared by the
/// GingerPaw app (writes them) and the `flowoss` CLI (reads them).
public struct VoiceSettings: Sendable {
    public var enabled: Bool
    public var speakOnStop: Bool
    public var speakOnNotification: Bool
    public var voice: String   // empty = system default voice
    public var rate: Int       // words-per-minute; 0 = `say` default

    public static let suiteName = "app.flowoss.voice"

    public init(enabled: Bool = true, speakOnStop: Bool = true, speakOnNotification: Bool = true, voice: String = "", rate: Int = 0) {
        self.enabled = enabled
        self.speakOnStop = speakOnStop
        self.speakOnNotification = speakOnNotification
        self.voice = voice
        self.rate = rate
    }

    public func shouldSpeak(_ event: AgentEvent) -> Bool {
        guard enabled else { return false }
        switch event {
        case .stop, .subagentStop: return speakOnStop
        case .notification: return speakOnNotification
        }
    }

    public static func load() -> VoiceSettings {
        let d = UserDefaults(suiteName: suiteName) ?? .standard
        return VoiceSettings(
            enabled: d.object(forKey: "enabled") as? Bool ?? true,
            speakOnStop: d.object(forKey: "speakOnStop") as? Bool ?? true,
            speakOnNotification: d.object(forKey: "speakOnNotification") as? Bool ?? true,
            voice: d.string(forKey: "voice") ?? "",
            rate: d.integer(forKey: "rate")
        )
    }

    public func save() {
        let d = UserDefaults(suiteName: Self.suiteName) ?? .standard
        d.set(enabled, forKey: "enabled")
        d.set(speakOnStop, forKey: "speakOnStop")
        d.set(speakOnNotification, forKey: "speakOnNotification")
        d.set(voice, forKey: "voice")
        d.set(rate, forKey: "rate")
    }
}

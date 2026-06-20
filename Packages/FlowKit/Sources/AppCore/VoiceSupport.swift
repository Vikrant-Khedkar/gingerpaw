import AgentNotifications
import Foundation
import Observation

/// Observable wrapper over the shared VoiceSettings suite for SwiftUI binding.
@MainActor
@Observable
final class VoiceSettingsStore {
    var enabled: Bool { didSet { save() } }
    var speakOnStop: Bool { didSet { save() } }
    var speakOnNotification: Bool { didSet { save() } }
    var voice: String { didSet { save() } }
    var rate: Int { didSet { save() } }

    init() {
        let s = VoiceSettings.load()
        enabled = s.enabled
        speakOnStop = s.speakOnStop
        speakOnNotification = s.speakOnNotification
        voice = s.voice
        rate = s.rate
    }

    private func save() {
        VoiceSettings(enabled: enabled, speakOnStop: speakOnStop,
                      speakOnNotification: speakOnNotification, voice: voice, rate: rate).save()
    }
}

/// Installs/removes GingerPaw's Stop + Notification hooks in a Claude config's settings.json.
enum HookInstaller {
    /// Prefer the CLI bundled inside the app; fall back to a dev install in ~/.local/bin.
    /// Named `flowoss-cli` (not `flowoss`) so it doesn't collide with the app's
    /// `FlowOSS` executable on the case-insensitive filesystem.
    static var flowossPath: String {
        Bundle.main.url(forAuxiliaryExecutable: "gingerpaw-cli")?.path
            ?? (NSHomeDirectory() + "/.local/bin/flowoss")
    }
    static var sgaiDir: String { NSHomeDirectory() + "/.claude-sgai" }

    private static func settingsPath(_ dir: String) -> String { dir + "/settings.json" }
    private static func command(_ arg: String) -> String { "\(flowossPath) notify --event \(arg)" }

    static func isInstalled(in dir: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: settingsPath(dir)),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else { return false }
        return containsFlowoss(hooks["Stop"])
    }

    static func install(in dir: String) throws {
        let path = settingsPath(dir)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var root: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: path) {
            try? data.write(to: URL(fileURLWithPath: path + ".gingerpaw-backup"))
            root = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        hooks["Stop"] = merged(hooks["Stop"], command: command("stop"))
        hooks["Notification"] = merged(hooks["Notification"], command: command("notification"))
        root["hooks"] = hooks
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try out.write(to: URL(fileURLWithPath: path))
    }

    static func remove(in dir: String) throws {
        let path = settingsPath(dir)
        guard let data = FileManager.default.contents(atPath: path),
              var root = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) else { return }
        try? data.write(to: URL(fileURLWithPath: path + ".gingerpaw-backup"))
        if var hooks = root["hooks"] as? [String: Any] {
            for event in ["Stop", "Notification"] {
                guard var groups = hooks[event] as? [[String: Any]] else { continue }
                groups = groups.compactMap { group in
                    var inner = (group["hooks"] as? [[String: Any]]) ?? []
                    inner.removeAll { ($0["command"] as? String)?.contains("flowoss") == true }
                    if inner.isEmpty { return nil }
                    var g = group; g["hooks"] = inner; return g
                }
                if groups.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = groups }
            }
            root["hooks"] = hooks
        }
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try out.write(to: URL(fileURLWithPath: path))
    }

    private static func containsFlowoss(_ groups: Any?) -> Bool {
        guard let groups = groups as? [[String: Any]] else { return false }
        for group in groups {
            for hook in (group["hooks"] as? [[String: Any]]) ?? [] {
                if (hook["command"] as? String)?.contains("flowoss") == true { return true }
            }
        }
        return false
    }

    private static func merged(_ existing: Any?, command: String) -> [[String: Any]] {
        var groups = existing as? [[String: Any]] ?? []
        if containsFlowoss(groups) { return groups }
        groups.append(["hooks": [["type": "command", "command": command]]])
        return groups
    }
}

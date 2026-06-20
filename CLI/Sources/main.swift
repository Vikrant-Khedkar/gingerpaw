import AgentNotifications
import Foundation

// Usage: flowoss notify --event <stop|notification|subagentStop>
// Reads the Claude hook JSON from stdin, speaks a short message per the shared
// voice settings. Designed to be invoked from a Claude Code hook command.

/// Block until `path`'s size has been unchanged for `settleMs`, or `maxMs` elapses.
/// Lets Claude's just-finished message finish writing before we read the transcript.
func waitForStableFile(_ path: String, settleMs: Int, maxMs: Int) {
    func size() -> Int {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let bytes = attrs[.size] as? Int else { return 0 }
        return bytes
    }
    let step = 75
    var elapsed = 0
    var last = size()
    var stableFor = 0
    while elapsed < maxMs {
        usleep(useconds_t(step * 1000))
        elapsed += step
        let now = size()
        if now == last && now > 0 {
            stableFor += step
            if stableFor >= settleMs { return }
        } else {
            stableFor = 0
            last = now
        }
    }
}

let args = CommandLine.arguments

guard args.count >= 2, args[1] == "notify" else {
    FileHandle.standardError.write(Data("usage: flowoss notify --event <stop|notification|subagentStop>\n".utf8))
    exit(2)
}

var eventName = "stop"
if let i = args.firstIndex(of: "--event"), args.indices.contains(i + 1) {
    eventName = args[i + 1]
}
let event = AgentEvent(rawValue: eventName) ?? .stop

// Read hook JSON from stdin (skip if attached to a terminal, so manual runs don't hang).
var payload: [String: Any] = [:]
if isatty(FileHandle.standardInput.fileDescriptor) == 0 {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    payload = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
}

let settings = VoiceSettings.load()
guard settings.shouldSpeak(event) else { exit(0) }

// For Stop, prefer what Claude itself chose to say (<say>…</say> in the transcript),
// falling back to the rule-based template if it's absent.
var message: String?
if event == .stop, let path = payload["transcript_path"] as? String {
    // The hook fires before Claude's final message is flushed to the transcript —
    // wait until the file stops growing so we read THIS turn, not the previous one.
    waitForStableFile(path, settleMs: 150, maxMs: 1500)
    message = Transcript.sayMessage(transcriptPath: path)
}
if message == nil {
    message = AgentMessage.text(for: event, payload: payload)
}

guard let spoken = message else { exit(0) }
SaySpeechService().speak(spoken, voice: settings.voice, rate: settings.rate)
exit(0)

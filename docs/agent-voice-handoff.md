# Agent Voice Notifications Handoff

## What we are trying to build

FlowOSS should become a local voice layer for coding agents that the user already runs in a terminal.

The desired product direction is:

- User runs Claude Code normally in Terminal, iTerm, Cursor, etc.
- When Claude finishes, needs input, requests permission, or fails, FlowOSS speaks a short notification.
- FlowOSS should not own the coding-agent session. It should listen to agent lifecycle events and speak useful updates.

Example spoken notifications:

- "Claude finished. Tests passed."
- "Claude needs your approval."
- "Claude hit a build error."
- "The agent is waiting for your next instruction."

The current preferred integration surface is Claude Code hooks plus a FlowOSS CLI, not MCP first.

## Proposed architecture

```text
Claude Code terminal
        |
        | Claude Code hook: Stop / Notification / SubagentStop
        v
flowoss notify --event stop
        |
        | local IPC
        v
FlowOSS macOS app
        |
        v
Local TTS speaks a short message
```

Recommended MVP pieces:

1. Add a `flowoss` CLI executable target.
2. Add `flowoss notify --event <event>` that reads Claude hook JSON from stdin.
3. Forward events to the running FlowOSS app through local IPC.
4. Add a `VoiceNotifications` or `AgentNotifications` FlowKit module.
5. Add app settings for enable/disable, voice, speed, and verbosity.
6. Add a Claude hook installer button that writes/updates `~/.claude/settings.json`.
7. Speak short rule-based messages first.
8. Add one-sentence summarization later if needed.

Do not start with cloud TTS or remote inference. The point is quick, private local feedback.

## Current repo state

Current branch when this handoff was written:

```sh
master
```

There is also an experimental branch:

```sh
feature/claude-playground
```

That branch implemented a different idea: a Playground tab that launches `claude-sgai` from FlowOSS. The user did not like that direction and pivoted to "speak when an existing Claude Code terminal is done."

Treat `feature/claude-playground` as reference only, not the intended product direction.

Important files in the current app:

- `Package.swift` - root SwiftPM app package.
- `Packages/FlowKit/Package.swift` - FlowKit package targets.
- `Packages/FlowKit/Sources/AppCore/AppComposition.swift` - central service construction.
- `Packages/FlowKit/Sources/AppCore/AppRuntime.swift` - runtime glue.
- `Packages/FlowKit/Sources/AppCore/SettingsView.swift` - likely place to add voice notification settings.
- `Packages/FlowKit/Sources/AppCore/AppShellView.swift` - app navigation.
- `Packages/FlowKit/Sources/Dictation/DictationCoordinator.swift` - existing dictation state machine; avoid coupling agent notifications into this unless needed.

## What we tested outside the repo

A Kokoro local TTS test harness was created outside the repo at:

```sh
/Users/vikrant/kokoro-tts-test
```

Files:

```text
/Users/vikrant/kokoro-tts-test/test-kokoro.sh
/Users/vikrant/kokoro-tts-test/test_kokoro.py
/Users/vikrant/kokoro-tts-test/models/kokoro-v1.0.fp16.onnx
/Users/vikrant/kokoro-tts-test/models/voices-v1.0.bin
/Users/vikrant/kokoro-tts-test/output.wav
```

Downloaded model assets:

```text
kokoro-v1.0.fp16.onnx   169 MB
voices-v1.0.bin          27 MB
```

Generated test audio:

```text
output.wav
mono 24 kHz WAV
```

The test command works:

```sh
/Users/vikrant/kokoro-tts-test/test-kokoro.sh "Claude finished. Tests passed."
```

Current script supports voice selection through `VOICE`:

```sh
VOICE=am_michael /Users/vikrant/kokoro-tts-test/test-kokoro.sh "Claude finished."
```

The script should be extended to expose speed:

```sh
VOICE=af_bella SPEED=1.15 /Users/vikrant/kokoro-tts-test/test-kokoro.sh "Claude finished."
```

## Recommended TTS path

Use a layered approach:

1. MVP: macOS built-in TTS through `AVSpeechSynthesizer`.
2. Local OSS option: Kokoro 82M fp16 via ONNX Runtime.
3. Later optional: Piper for smaller/faster voices.

Kokoro is good quality but packaging Python/ONNX directly inside a Swift macOS app needs careful work. For fastest product iteration, start with macOS TTS and keep Kokoro as a local premium/experimental engine.

## Claude Code hook direction

Research found Claude Code supports hooks such as:

- `Stop`
- `Notification`
- `SubagentStop`

Hooks are configured in Claude settings JSON and can execute shell commands. The hook command receives JSON on stdin.

Example shape to aim for:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "flowoss notify --event stop"
          }
        ]
      }
    ],
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "flowoss notify --event notification"
          }
        ]
      }
    ]
  }
}
```

Verify exact hook schema against current Claude Code docs before writing the installer.

## Suggested implementation plan for next agent

1. Create a new branch from `master`, e.g. `feature/agent-voice-notifications`.
2. Add a new FlowKit module: `AgentNotifications`.
3. Add models for incoming events:
   - `AgentNotificationEvent`
   - `AgentNotificationKind`
   - `AgentNotificationMessage`
4. Add a local speech service:
   - Start with `AVSpeechSynthesizer`.
   - Make it a protocol-backed service so Kokoro/Piper can be added later.
5. Add a CLI executable target:
   - `flowoss notify --event stop`
   - reads stdin
   - sends payload to app
6. Pick IPC:
   - simplest robust MVP: local HTTP server on `127.0.0.1`
   - alternate: Unix domain socket
   - fallback: file queue in Application Support
7. Add app listener service that receives CLI events and calls speech service.
8. Add settings UI:
   - Enable agent voice notifications
   - Speak only attention-needed events
   - Voice
   - Speed
   - Test voice button
9. Add Claude hook installer:
   - Detect `~/.claude/settings.json`
   - Merge hooks carefully
   - Back up before writing
10. Test with a real Claude Code session:
   - `Notification` when Claude needs input/permission
   - `Stop` when response finishes

## Avoid

- Do not make FlowOSS launch Claude Code as the main product flow.
- Do not read full agent responses aloud by default.
- Do not require cloud TTS for MVP.
- Do not put Kokoro model files inside the FlowOSS repo.
- Do not mutate `~/.claude/settings.json` without backup and clear user action.

## Open questions

- Should FlowOSS speak every `Stop`, or only long-running tasks?
- Should the CLI talk to the app through HTTP or a Unix socket?
- Should Kokoro be shipped, downloaded on demand, or kept as a user-installed engine?
- Should voice notifications be per-project or global?
- Should notifications include only speech, or also a small app history panel?

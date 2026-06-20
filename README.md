<div align="center">

<img src="docs/logo.png" alt="GingerPaw" width="160" height="160" />

# GingerPaw

**Push-to-talk dictation for macOS — fully on-device.**

Hold a hotkey, speak, release. Your words are transcribed locally with WhisperKit
and pasted into whatever app you're in. And when your coding agent finishes a task,
a ginger cat pops up and *tells you out loud* — so you can walk away. Nothing leaves your Mac.

<br/>

<img src="docs/media/cat-demo.gif" alt="GingerPaw's talking cat announcing a finished Claude Code task" width="720" />

<sub>Dictated a task to Claude Code, wandered off to browse domains — the cat called me back when it was done.</sub>

</div>

---

## Features

- **Push-to-talk** — hold **Fn or Right Option**, speak, release to paste.
- **On-device transcription** — [WhisperKit](https://github.com/argmaxinc/WhisperKit) CoreML models run on the Neural Engine. No cloud, no account.
- **Talking-cat agent notifications** — hook GingerPaw into [Claude Code](https://claude.com/claude-code) and a ginger cat appears and speaks a short summary every time the agent finishes or needs you. Walk away from your desk and still know when it's done.
- **AI formatting (experimental, off by default)** — a local **Qwen 0.5B** model (via [MLX](https://github.com/ml-explore/mlx-swift)) restructures dictation into bullets/numbered lists while preserving your words. Toggle it on in Settings.
- **Floating recording pill** — a dark capsule that turns red with a ginger-paw "purr" while recording, an animated waveform while transcribing.
- **Native macOS UI** — `NavigationSplitView`, SF Symbols, grouped cards, status pills. Menu-bar resident.
- **Clipboard-safe** — optionally restores your previous clipboard after pasting.

## Requirements

- macOS 14+ (Apple Silicon)
- Xcode 16+ with the Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`) — required to compile MLX's GPU shaders.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build

```sh
xcodegen generate                                    # project.yml -> GingerPaw.xcodeproj
xcodebuild -project GingerPaw.xcodeproj -scheme GingerPaw \
  -configuration Debug -derivedDataPath ./dd build
```

> MLX requires Xcode's build system to compile the Metal kernels — a plain `swift build` will not produce the metallib. Use `xcodebuild` (or open the project in Xcode).

Run `swift test` inside `Packages/FlowKit` for the unit tests.

## Permissions

GingerPaw needs three macOS grants (surfaced in the in-app **Permissions** tab):

| Grant | Why |
|-------|-----|
| Microphone | Record your voice for transcription |
| Input Monitoring | Detect the push-to-talk hotkey globally |
| Accessibility | Paste text into the focused app |

## Agent voice notifications (the talking cat)

GingerPaw installs a [Claude Code hook](https://docs.claude.com/en/docs/claude-code/hooks) that fires when the agent stops or needs input. Claude writes its own one-line `<say>…</say>` summary; the bundled CLI reads it from the transcript and signals the app, which speaks it via macOS `say` while a ginger cat overlay pops up and lip-syncs the caption.

Enable it from the in-app **Voice** tab (Install Hook), or point any Claude config's `settings.json` at the bundled CLI:

```
GingerPaw.app/Contents/MacOS/gingerpaw-cli notify --event stop
```

The app does the talking when it's running (cat + caption stay in sync); the CLI falls back to speaking headless if the app is closed.

## Architecture

A thin SwiftUI app shell (`App/`) over **FlowKit** (`Packages/FlowKit`), a SwiftPM package of focused libraries:

- `Dictation` — the `DictationCoordinator` state machine (`idle → recording → processing → inserting → copied/failed`)
- `Audio` · `Transcription` (WhisperKit) · `TextInsertion` (clipboard + synthetic ⌘V)
- `TextProcessing` — MLX/Qwen formatter behind a `TextProcessor` protocol
- `Hotkeys` (global `CGEventTap`) · `Permissions` (TCC) · `Overlay` (the recording pill) · `Settings`
- `AgentNotifications` — the `<say>` transcript parser + speech service shared by the app and the `gingerpaw-cli` hook binary
- `AppCore` — composition + the Dictate / Voice / Permissions / Settings UI, plus the talking-cat `CatOverlayController`

Models are loaded from the app bundle if present (shippable offline), otherwise downloaded once to the Hugging Face cache and run on-device.

## License

MIT

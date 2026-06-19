<div align="center">

<img src="docs/logo.png" alt="GingerPaw" width="160" height="160" />

# GingerPaw

**Push-to-talk dictation for macOS — fully on-device.**

Hold a hotkey, speak, release. Your words are transcribed locally with WhisperKit
and pasted into whatever app you're in. Optional on-device AI cleans rambly speech
into clean bullets and sentences. Nothing leaves your Mac.

</div>

---

## Features

- **Push-to-talk** — hold **Fn or Right Option**, speak, release to paste.
- **On-device transcription** — [WhisperKit](https://github.com/argmaxinc/WhisperKit) CoreML models run on the Neural Engine. No cloud, no account.
- **AI formatting (optional)** — a local **Qwen 0.5B** model (via [MLX](https://github.com/ml-explore/mlx-swift)) restructures dictation into bullets/numbered lists while preserving your words. Toggleable.
- **Floating recording pill** — a dark capsule that turns red with a ginger-paw "purr" while recording, an animated waveform while transcribing.
- **Native macOS UI** — `NavigationSplitView`, SF Symbols, grouped cards, status pills. Menu-bar resident.
- **Clipboard-safe** — optionally restores your previous clipboard after pasting.

## Requirements

- macOS 14+ (Apple Silicon)
- Xcode 16+ with the Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`) — required to compile MLX's GPU shaders.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build

```sh
xcodegen generate                                    # project.yml -> FlowOSS.xcodeproj
xcodebuild -project FlowOSS.xcodeproj -scheme FlowOSS \
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

## Architecture

A thin SwiftUI app shell (`App/`) over **FlowKit** (`Packages/FlowKit`), a SwiftPM package of focused libraries:

- `Dictation` — the `DictationCoordinator` state machine (`idle → recording → processing → inserting → copied/failed`)
- `Audio` · `Transcription` (WhisperKit) · `TextInsertion` (clipboard + synthetic ⌘V)
- `TextProcessing` — MLX/Qwen formatter behind a `TextProcessor` protocol
- `Hotkeys` (global `CGEventTap`) · `Permissions` (TCC) · `Overlay` (the recording pill) · `Settings`
- `AppCore` — composition + the Dictate / Permissions / Settings UI

Models are loaded from the app bundle if present (shippable offline), otherwise downloaded once to the Hugging Face cache and run on-device.

## License

MIT

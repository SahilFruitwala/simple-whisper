# Simple Wisper

Native macOS menu-bar dictation. Hold a hotkey, speak, release — clean text is pasted into whatever you were typing.

Everything runs on-device. Speech is transcribed with Whisper (WhisperKit, Neural Engine), then cleaned by **S1-mini by Superwhisper** (MLX): fillers dropped, self-corrections resolved, punctuation and capitalization applied.

```
mic  →  WhisperKit  →  S1-mini by Superwhisper  →  paste
```

Requirements: Apple Silicon Mac, macOS 14+.

## Lightweight by design

- ~50 MB RAM while idle. Models load on first dictation (while you speak) and unload after 10 idle minutes (configurable: Never / 5 / 10 / 30 min).
- The microphone is only opened while recording.
- Models are downloaded on first use, not bundled: Whisper to `~/Library/Application Support/SimpleWisper/whisperkit`, S1-mini to the Hugging Face cache. The first Whisper load also compiles it for the Neural Engine once.

## Build and install

Needs Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) and the Metal toolchain (`xcodebuild -downloadComponent MetalToolchain`).

```bash
make cert      # once: creates a self-signed "Simple Wisper Local" signing identity
make install   # builds Release and copies to /Applications
```

The self-signed identity keeps macOS permission grants across rebuilds. No Apple Developer account is needed.

`make dmg` builds `build/SimpleWisper.dmg`. Since it is not notarized, recipients must right-click → Open the first time, or run `xattr -dr com.apple.quarantine "/Applications/Simple Wisper.app"`.

## Permissions

- **Microphone** — prompted on first launch.
- **Accessibility** — System Settings → Privacy & Security → Accessibility. Needed for the global hotkey and auto-paste. Without it, text is only copied.

## Use

- Default: hold **Right Option**. Right Command and a tap-to-start/stop mode are in the Hotkey menu.
- The HUD shows **ON AIR**, then **TRANSCRIBING** and **POLISHING**.
- Auto-paste restores your previous clipboard afterwards.

Menu: Styling / Structure / Context (S1-mini control line), Whisper size (`small.en` default), Input device, Hotkey, Unload Models, Open at Login.

Settings from the old Python version (`~/.config/simple-wisper/config.json`) are imported once on first launch.

## License notes

This repo is MIT. **S1-mini by Superwhisper** is Apache 2.0 plus a naming clause: keep the name "S1-mini" by "Superwhisper" with that capitalization. See [NOTICE](NOTICE) and the [model card](https://huggingface.co/superwhisper/s1-mini).

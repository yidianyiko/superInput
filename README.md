<div align="center">

# SlashVibe

### macOS Menu Bar Speech + Memory Workspace

**活动标签：#小红书黑客松巅峰赛** | GitHub Topic: `redhackathon`

</div>

Minimal macOS push-to-talk speech-to-text app scaffolded for the architecture described in the product and hardware research docs.

## What is implemented

- Native macOS menu bar app shell using `SwiftUI MenuBarExtra`
- Clean seams between hardware input, audio capture, transcription, and UI orchestration
- Global hold-space push-to-talk with short-tap space passthrough
- Mac microphone capture via `AVFoundation`
- Deepgram live transcription over WebSocket
- Keychain-backed Deepgram API key storage
- Auto-insert of final transcript into the currently focused chat or text field
- Future-ready interfaces for USB HID and USB Audio replacements
- Coordinator tests for the session state machine
- Deepgram message decoding tests
- File-backed audio source test for integration-style coverage

## Project structure

- `Sources/SpeechBarDomain`
  Shared protocols, events, audio descriptors, and state enums.
- `Sources/SpeechBarApplication`
  `VoiceSessionCoordinator` and the app-level orchestration logic.
- `Sources/SpeechBarInfrastructure`
  On-screen push-to-talk source, global space-key capture, mac microphone capture, Deepgram client, Keychain, and transcript delivery implementations.
- `Sources/SpeechBarApp`
  Menu bar app shell and the UI.

## API key handling

The app never hardcodes a Deepgram API key in source or plist files.

- Launch the app.
- Paste your Deepgram key into the secure field.
- Save it to Keychain.

The key shared in chat should be treated as exposed. Rotate it before any real use.

## Build locally

This workspace currently has Swift command line tools but not a full Xcode installation.

### Build the executable

```bash
cd /Users/lixingting/Desktop/StartUp/Code
swift build
```

### Build a local `.app` bundle wrapper

```bash
cd /Users/lixingting/Desktop/StartUp/Code
./Scripts/build_app_bundle.sh
open ./dist/SlashVibe.app
```

### Build a release zip for another Mac

```bash
cd /Users/lixingting/Desktop/StartUp/Code
./Scripts/package_release.sh
```

That creates a distributable zip in `release/`.

## Permissions for the new workflow

To use global hold-space and automatic transcript insertion into another app:

- Allow microphone access
- Allow Accessibility access
- If macOS asks, allow Input Monitoring for the app so it can watch the space key globally

## Run tests

```bash
cd /Users/lixingting/Desktop/StartUp/Code
swift test
```

## Notes

- Default Deepgram model is `nova-2` with `language=zh-CN`.
- Audio is normalized to `16kHz / mono / linear16` before streaming.
- KeepAlive messages are sent every 4 seconds.
- Short press on `Space` still types a normal space. Long press on `Space` starts voice capture.
- Replacing the on-screen button with a future USB HID input should only require a new `HardwareEventSource`.

## Distribution and GitHub

- Install and sharing guide: [INSTALL.md](/Users/lixingting/Desktop/StartUp/Code/INSTALL.md)
- GitHub upload guide: [GITHUB_SETUP.md](/Users/lixingting/Desktop/StartUp/Code/GITHUB_SETUP.md)

---

<div align="center">

*小红书黑客松巅峰赛 · GitHub Topic `redhackathon`*

</div>

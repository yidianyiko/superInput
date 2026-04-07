# Repository Guidelines

## Project Structure & Module Organization
This repository is a Swift Package for a macOS menu bar speech app. Core code lives under `Sources/`:

- `Sources/SpeechBarDomain`: shared types, protocols, events, and configuration models.
- `Sources/SpeechBarApplication`: orchestration and coordinator logic.
- `Sources/SpeechBarInfrastructure`: microphone capture, Keychain, transcription clients, and transcript publishing.
- `Sources/SpeechBarApp`: the executable app target and SwiftUI UI shell.
- `Tests/SpeechBarTests`: package tests covering coordinators, integrations, and decoders.
- `Config/` and `Resources/`: app bundle metadata and packaged assets.
- `Scripts/`: local signing, app bundle creation, and release packaging.
- `Vendor/SwiftWhisper`: vendored dependency; treat it as external unless a change is required.

## Build, Test, and Development Commands
- `swift build`: builds the package and `SpeechBarApp`.
- `swift test`: runs the `SpeechBarTests` suite.
- `./Scripts/create_local_signing_identity.sh`: creates the local code-signing identity expected by bundle packaging.
- `./Scripts/build_app_bundle.sh`: builds and signs `dist/SlashVibe.app`, then syncs an installed copy next to the repo.
- `./Scripts/package_release.sh`: creates a release zip in `release/` using a release build.

Run commands from the repository root.

## Coding Style & Naming Conventions
Follow existing Swift conventions: 4-space indentation, one primary type per file, `UpperCamelCase` for types, `lowerCamelCase` for methods and properties, and clear protocol-oriented names such as `TranscriptPublisher`. Keep module boundaries clean: domain stays platform-agnostic, infrastructure owns OS and network details, and application coordinates behavior.

No `SwiftLint` or `SwiftFormat` config is checked in, so match the surrounding style instead of introducing a new formatter profile.

## Testing Guidelines
Tests use Swift's `Testing` package (`import Testing`, `@Suite`, `@Test`). Name files after the subject under test, for example `VoiceSessionCoordinatorTests.swift`, and use descriptive test names such as `successfulPushToTalkPublishesFinalTranscript`. Add tests with behavior changes, especially for coordinator state transitions, provider switching, and infrastructure adapters.

## Commit & Pull Request Guidelines
Git history is not included in this exported snapshot, so there is no local commit log to mine for conventions. Use short, imperative commit subjects such as `Add replay bundle cleanup` and keep each commit focused. For pull requests, include a concise description, call out user-visible changes, list verification steps (`swift test`, packaging script used), and attach screenshots when `SpeechBarApp` UI changes.

## Security & Configuration Tips
Never hardcode API keys or secrets. Use the existing Keychain-backed credential flow, keep signing identities local, and avoid committing generated `dist/` or `release/` artifacts unless a release process explicitly requires them.

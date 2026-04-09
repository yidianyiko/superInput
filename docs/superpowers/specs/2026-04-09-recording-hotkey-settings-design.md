# Recording Hotkey Settings Design

Status: approved
Date: 2026-04-09
Repository: `/Users/oliver/Downloads/redheak_source_20260407_220321`

## 1. Summary

This document defines the approved design for adding recording hotkey configuration and diagnostics to the existing settings page.

The approved direction is:

- add hotkey configuration directly inside the current settings page instead of creating a separate screen
- support two recording-trigger modes: `rightCommand` and `customCombo`
- preserve the current right-side `Command` toggle behavior as a first-class selectable mode
- support arbitrary user-defined global key combinations for `customCombo`
- require every custom combination to include at least one modifier key
- keep trigger semantics as `press once to start, press again to stop`
- apply hotkey changes at runtime without requiring an app relaunch
- show a diagnostics block that reports current mode, registration state, recent trigger activity, and permission guidance
- keep `VoiceSessionCoordinator` and the downstream recording / publish pipeline unchanged

The user explicitly chose to support arbitrary custom combinations, keep the current right-side `Command` mode available, require modifier keys for custom combinations, and use toggle semantics instead of hold-to-talk.

## 2. Product Intent

The app currently has a recording shortcut, but it is effectively hidden behind implementation details:

- the active shortcut is not configurable
- the current settings page does not explain whether hotkey listening is healthy
- users cannot tell whether failure to trigger comes from permission state, registration failure, or simply using the wrong key

The goal of this work is to make recording input legible and controllable:

- users can see which recording shortcut is active
- users can switch between right-side `Command` mode and a standard custom shortcut
- users can record a new shortcut directly in settings
- users can immediately see whether the shortcut is active and when it last fired
- users get explicit guidance when permissions or registration state prevent hotkey use

This is a settings and diagnostics improvement, not a redesign of the recording pipeline.

## 3. Design Goals

- Make the current recording shortcut visible from the settings page.
- Allow users to switch between the existing right-side `Command` mode and a custom global combination.
- Allow custom combinations to be changed in-app without editing code or restarting intentionally.
- Reject unsafe custom configurations such as bare letter keys with no modifiers.
- Show enough diagnostic state that a user can self-serve common hotkey problems.
- Preserve existing `VoiceSessionCoordinator` behavior and hardware event semantics.
- Keep the implementation narrow enough to ship without refactoring all hardware input sources.

## 4. Non-Goals

- Adding per-shortcut actions beyond start/stop recording.
- Adding hold-to-talk semantics for this feature.
- Supporting multiple different recording shortcuts at the same time.
- Allowing bare non-modifier keys as valid global shortcuts.
- Building a generalized shortcut-management framework for every product command.
- Solving OS-level shortcut collisions with perfect attribution to the conflicting app.
- Replacing USB board input, on-screen button input, or rotary input logic.

## 5. Approved Direction

Three approaches were considered:

1. Add a lightweight display-only card that shows the active shortcut and stores changes for next launch.
2. Add a runtime-switchable hotkey center with in-settings recording, validation, live re-registration, and diagnostics.
3. Refactor all hardware input into a generalized input platform before adding shortcut settings.

The approved approach is `Add a runtime-switchable hotkey center with in-settings recording, validation, live re-registration, and diagnostics`.

This provides the behavior the user asked for without turning the task into a broad input-architecture rewrite.

## 6. Confirmed User Decisions

The following choices are fixed by user approval:

- custom shortcuts must support arbitrary key combinations
- the current right-side `Command` mode remains available as a selectable option
- the diagnostics area should show current shortcut, health, and recent trigger activity
- trigger semantics are toggle-based: one activation starts recording, the next activation stops recording
- custom shortcuts must include at least one modifier key

## 7. User-Visible Behavior

### 7.1 Settings Placement

The feature lives inside the existing settings page, under a new dedicated card rather than a new top-level page.

The card should sit alongside the existing audio-input and permission cards so that recording setup is discoverable in one place.

### 7.2 Shortcut Modes

Users can choose between two modes:

- `右侧 Command`
- `自定义组合键`

`右侧 Command` preserves current behavior:

- only the right-side `Command` key is recognized
- left-side `Command` does not trigger recording
- the shortcut toggles recording on each valid press
- the mode still depends on Accessibility-backed event listening

`自定义组合键` uses a normal global shortcut combination:

- the user picks one non-modifier key plus one or more modifiers
- the shortcut toggles recording on each successful press
- the setting becomes effective immediately after save

### 7.3 Recording a Custom Shortcut

The settings card includes a recording affordance such as `录制快捷键`.

When recording starts:

- the UI enters a temporary capture state
- the next valid key combination is displayed live
- invalid input is rejected inline instead of being saved
- the user can cancel recording without changing the current shortcut

Validation rules:

- at least one modifier is required
- a main key is required
- modifier-only combinations are invalid
- the reserved special case of bare right-side `Command` is only valid through `rightCommand` mode, not through custom recording

### 7.4 Saving and Applying

When a valid custom shortcut is confirmed:

- it is written to persistent settings
- the currently active global shortcut registration is torn down
- the new registration is attempted immediately
- the diagnostics area updates to reflect the result

No intentional app restart is required for normal changes.

### 7.5 Diagnostics Surface

The settings card includes a diagnostics block that shows:

- current mode
- current shortcut display string
- listener registration status
- whether Accessibility is currently required for the selected mode
- recent trigger activity, including last trigger time and whether it started or stopped recording
- current guidance when the listener is not operational

This block is diagnostic, not interactive telemetry. It should be understandable at a glance.

### 7.6 Failure and Recovery States

The UI must distinguish between at least these states:

- `正在监听`: the selected hotkey path is registered and ready
- `需要辅助功能权限`: the selected mode requires Accessibility and the app is not trusted
- `快捷键无效`: the custom combination fails local validation
- `注册失败`: the app attempted to register the custom shortcut and the OS rejected it

Recovery affordances should include:

- `打开辅助功能设置` when permissions are missing
- `重新尝试注册` when registration previously failed

When the app cannot prove the exact cause of a registration failure, the copy should stay honest and generic, for example: the shortcut may already be occupied by the system or another app.

## 8. Interaction Rules

### 8.1 Toggle Semantics

Both shortcut modes share the same trigger contract:

- first trigger emits `.pushToTalkPressed`
- second trigger emits `.pushToTalkReleased`
- subsequent triggers continue alternating

This preserves the app's current recording model and avoids widening scope into press-and-hold behavior.

### 8.2 Mode-Specific Permission Rules

`rightCommand` mode is permission-sensitive because it relies on an event tap that currently checks Accessibility trust.

`customCombo` mode should use standard global shortcut registration and should not require Accessibility solely for hotkey capture.

The diagnostics copy must therefore be mode-aware:

- in `rightCommand`, permission state is part of shortcut readiness
- in `customCombo`, missing Accessibility should not be presented as the reason the shortcut itself is unavailable

### 8.3 Conflict Signaling

For custom combinations, the app should attempt registration immediately and surface the result.

If registration fails:

- keep the saved configuration visible
- show that the shortcut is not currently active
- explain that the key combination may already be in use
- do not silently fall back to another shortcut mode

### 8.4 Last Trigger Reporting

Diagnostics should retain a lightweight memory of the most recent successful shortcut activation:

- timestamp
- source mode
- action emitted: start or stop

This allows users to verify that the app saw the hotkey even if recording later failed for unrelated reasons.

## 9. Architecture

The implementation should introduce one new runtime configuration store, one runtime shortcut controller, and one diagnostics surface for the settings UI.

### 9.1 Components

#### A. Shortcut Configuration Store

New app-owned settings store responsible for:

- persisting the selected shortcut mode
- persisting the custom key combination
- exposing display-ready values for the settings UI
- validating stored configuration before runtime registration

Recommended model:

- `RecordingHotkeyMode`
- `RecordingHotkeyCombination`
- `RecordingHotkeyConfiguration`

This store should use `UserDefaults` in the same style as the existing home-window settings stores.

#### B. Runtime Shortcut Controller

New runtime controller responsible for:

- reading the current shortcut configuration
- instantiating exactly one active shortcut listener at a time
- converting successful triggers into `HardwareEvent`
- re-registering listeners when configuration changes
- publishing lightweight diagnostics snapshots

This controller should continue to present itself outwardly as a `HardwareEventSource` so that `VoiceSessionCoordinator` can remain unchanged.

#### C. Right-Command Listener

The current `GlobalRightCommandPushToTalkSource` remains the implementation for `rightCommand` mode, with only the changes needed to expose readiness / failure state through diagnostics.

Its behavior should not be generalized beyond what this feature needs.

#### D. Custom Combination Listener

Introduce or adapt a listener dedicated to normal global shortcut combinations.

Responsibilities:

- register a single system-wide key combination
- emit alternating pressed / released hardware events
- report registration success or failure
- support teardown and re-registration at runtime

This listener should back only `customCombo` mode.

#### E. Diagnostics Snapshot

New lightweight state object for the settings UI.

Recommended fields:

- selected mode
- display string
- registration status
- status message
- requires accessibility
- accessibility trusted
- last trigger timestamp
- last trigger action

The view should consume this snapshot rather than reading listener internals directly.

### 9.2 Startup Wiring

Current startup wiring creates one concrete global shortcut source and merges it into `MergedHardwareEventSource`.

The new design should replace that single hardcoded source with the runtime shortcut controller so that:

- existing on-screen button input remains unchanged
- board and rotary test sources remain unchanged
- the coordinator still receives the same `HardwareEvent` types
- only the recording hotkey source becomes configurable

### 9.3 Settings UI Composition

The settings page should gain one new card with two sections:

1. `快捷键设置`
2. `快捷键检测`

The first section manages mode and configuration.

The second section reads from diagnostics and offers recovery actions.

This should be implemented as focused subviews rather than growing `HomeWindowView` with one large inline block.

## 10. Data Model

The exact names may change, but the design requires equivalent concepts:

- `RecordingHotkeyMode`
  - `rightCommand`
  - `customCombo`

- `RecordingHotkeyCombination`
  - key code
  - modifier flags
  - display label

- `RecordingHotkeyValidationResult`
  - `valid`
  - `missingModifier`
  - `missingMainKey`
  - `reservedRightCommand`

- `RecordingHotkeyRegistrationStatus`
  - `registered`
  - `permissionRequired`
  - `invalidConfiguration`
  - `registrationFailed`

- `RecordingHotkeyLastTrigger`
  - occurred at
  - mode
  - emitted action

- `RecordingHotkeyDiagnosticsSnapshot`
  - current configuration
  - current registration state
  - current guidance copy
  - last trigger metadata

## 11. Settings Copy Expectations

The copy should make the mental model explicit:

- right-side `Command` is a special built-in mode
- custom combination mode requires at least one modifier key
- the shortcut toggles recording on and off
- diagnostics show whether the listener is actually active

Copy should avoid overclaiming. If the app only knows that registration failed, it must not name a specific conflicting app.

## 12. Testing Strategy

The implementation should add tests for behavior changes, not only storage.

Required coverage:

- configuration validation accepts combinations with at least one modifier and one main key
- configuration validation rejects modifier-only input and bare keys
- switching modes reconfigures the active runtime listener
- custom-combo registration failure updates diagnostics correctly
- right-command permission-required state updates diagnostics correctly
- successful triggers update last-trigger diagnostics with the correct action
- startup wiring still delivers shortcut events into `VoiceSessionCoordinator`
- settings view model state reflects runtime diagnostics and current persisted configuration

UI snapshots are optional; behavior tests are required.

## 13. Risks and Constraints

### 13.1 Different Registration Mechanisms

The two supported modes do not share the same low-level mechanism:

- right-command mode depends on event-tap listening
- custom-combo mode depends on normal global shortcut registration

The design must reflect this rather than pretending every failure is the same.

### 13.2 Runtime Re-registration

Changing shortcuts live means old listeners must be fully torn down before new ones are installed.

If the controller leaks old registrations, users may see duplicated or phantom toggles.

### 13.3 Key Display Consistency

The app must show the same human-readable shortcut string everywhere in settings and diagnostics.

Formatting logic should therefore live in one place, not be duplicated across views.

## 14. Open Implementation Guidance

The following implementation choices are intentionally left flexible:

- whether the custom-combo listener reuses and generalizes the existing `GlobalShortcutToggleSource` or introduces a new dedicated source
- the exact SwiftUI control used for shortcut recording
- the exact visual layout of the diagnostics card, so long as it remains consistent with the existing settings page

These are implementation details, not product-level requirements.

## 15. File Impact Overview

Likely touch points include:

- `Sources/SpeechBarApp/StartUpSpeechBarApp.swift`
- `Sources/SpeechBarApp/HomeWindowStore.swift`
- `Sources/SpeechBarApp/HomeWindowView.swift`
- `Sources/SpeechBarInfrastructure/GlobalRightCommandPushToTalkSource.swift`
- `Sources/SpeechBarInfrastructure/GlobalF5ToggleSource.swift` or a replacement custom-combo listener
- new app and infrastructure files for configuration and diagnostics
- tests covering validation, runtime switching, and diagnostics reporting

The design purposefully avoids changes to:

- `VoiceSessionCoordinator` recording semantics
- transcript publishing logic
- existing board / rotary input features

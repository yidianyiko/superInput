# Global Star Injection Feedback Design

Status: approved
Date: 2026-04-09
Repository: `/Users/oliver/Downloads/redheak_source_20260407_220321`

## 1. Summary

This document defines the approved design for adding a global star-injection feedback animation after a voice transcript is recognized and published.

The approved direction is:

- keep the existing real transcript delivery logic unchanged
- keep clipboard paste and Accessibility insertion as the only real delivery mechanisms
- add a separate full-screen transparent overlay only on the target application's screen
- start the visual effect at the same time real publish begins
- treat the animation as feedback only, never as a prerequisite for text insertion
- skip any temporary text preview and emit stars immediately
- remove any lingering success glow after impact
- treat the current primary paste path as a success outcome, not as a downgrade
- still play the animation when delivery truly downgrades to clipboard-only, but end with a clearly different downgraded visual treatment

The user explicitly chose to preserve the current paste / AX injection path and add only a visual feedback layer around it.

## 2. Product Intent

The current product already performs real transcript insertion, but the transition from "speech recognized" to "text appeared in the target app" is operational rather than theatrical.

The goal of this work is to make transcript delivery feel intentional and legible:

- recording ends
- transcript is recognized
- a brief global star effect appears on the target screen
- the user perceives that the recognized result has been "sent into" the destination app

This is not meant to change reliability or input semantics. The purpose is to strengthen product feel without putting delivery success at risk.

## 3. Design Goals

- Add a clearly visible global feedback animation for transcript publishing.
- Restrict the animation to the target application's screen instead of all displays.
- Keep real publish latency unchanged by running animation and insertion in parallel.
- Reuse the current target-capture behavior so the animation follows the same intended destination as real insertion.
- Provide a downgraded-but-still-informative visual ending when delivery falls back to clipboard.
- Keep the implementation narrow enough to ship without destabilizing the current input pipeline.

## 4. Non-Goals

- Replacing the existing clipboard paste or Accessibility insertion logic.
- Delaying publish until the animation finishes.
- Rendering the effect on every connected display.
- Showing the polished transcript as temporary overlay text before animation.
- Leaving a persistent glow, badge, or residual marker near the destination.
- Building a general-purpose global animation framework for unrelated product surfaces.
- Redesigning the existing recording pill or the home-window constellation UI for this task.

## 5. Approved Direction

Three approaches were considered:

1. Extend the existing bottom recording panel so it visually bursts into stars.
2. Add a separate target-screen global overlay dedicated to publish feedback.
3. Build a generalized cross-feature fullscreen motion stage for recording, switching, and publishing.

The approved approach is `Add a separate target-screen global overlay dedicated to publish feedback`.

This keeps the current delivery path intact while giving the product a convincingly global animation surface. It also avoids overloading the existing `RecordingOverlayController` with fullscreen responsibilities it was not designed to own.

## 6. Confirmed User Decisions

The following choices are fixed by user approval:

- real transcript insertion still starts immediately when publishing begins
- the animation is feedback only and does not gate publish
- the animation appears only on the target application's screen
- stars launch immediately with no intermediate transcript text flash
- stars disappear on arrival with no lingering glow
- clipboard-only fallback still triggers the animation
- the normal paste-shortcut path keeps the success ending
- clipboard fallback keeps the same destination direction but ends with a visibly downgraded finish

## 7. User-Visible Behavior

### 7.1 Success Path

When a transcript reaches the publishing stage:

- the current recording pill remains as-is
- the app immediately begins real delivery through the existing publisher
- at the same moment, a transparent fullscreen overlay appears on the target screen
- a compact burst of stars forms near the lower center of that screen
- the stars arc toward the captured destination area
- on arrival, the stars collapse and vanish quickly with no trailing afterglow
- the overlay tears down immediately after the short animation completes

The intended feel is "recognized and sent" rather than "waiting for animation to unlock insertion."

### 7.2 Delivery Outcome Mapping

Animation endings must map to the current delivery outcomes as follows:

- `.insertedIntoFocusedApp`: success ending
- `.typedIntoFocusedApp`: success ending
- `.pasteShortcutSent`: success ending
- `.copiedToClipboard`: downgraded ending
- `.publishedOnly`: no global overlay unless a future implementation explicitly defines a visual contract for this outcome

The current codebase uses `.pasteShortcutSent` for the primary paste-based publish path, so it must not be treated as a downgrade.

### 7.3 Clipboard Downgrade Path

If real delivery falls back to `.copiedToClipboard`:

- the same target-screen animation still plays
- stars still travel toward the same destination direction
- the endpoint finish changes to a downgraded visual cue rather than the clean success collapse
- the downgraded cue should read as "delivery finished differently" rather than as a hard error
- the downgraded cue must still disappear quickly and leave no persistent glow

This preserves the product story while remaining honest about the result.

### 7.4 Missing Target Geometry

If the app cannot resolve enough target geometry to determine a destination screen:

- real publish still proceeds unchanged
- the global overlay should not appear

It is better to skip the effect than show it on the wrong display.

## 8. Animation Rules

### 8.1 Motion Character

The animation should feel fast, clean, and directional.

- total visible duration should stay short, roughly 450 to 700 milliseconds
- the opening burst should be compact rather than explosive
- star count should stay restrained, roughly 10 to 18 particles
- trajectories should converge rather than scatter aimlessly
- the effect should feel like injection, not fireworks

### 8.2 Source Anchor

The source anchor should live on the target screen rather than literally reusing the recording panel's current window position.

Approved rule:

- start from a virtual source point near the lower center of the target screen
- shape the opening cluster so it visually echoes the product's recording-pill language

This avoids awkward cross-display travel when the recording panel and target app are not on the same screen.

### 8.3 Destination Anchor

The destination should use the best geometry available in this order:

1. focused input element frame center
2. focused window frame with a bias toward the likely text-entry region
3. screen-local fallback point derived from the target window or screen center

This geometry is for visual guidance only. It must not alter the real insertion code path.

### 8.4 Overlay Window Behavior

The fullscreen overlay window must be specified tightly enough that it cannot interfere with the target app.

Required window behavior:

- use a borderless nonactivating panel
- keep the panel transparent and visually fullscreen on the target screen only
- set `ignoresMouseEvents = true`
- do not become key or main
- use collection behavior that allows appearance across Spaces and fullscreen contexts without entering the app's normal window cycle
- use a window level high enough to remain visible above the target app, but not in a way that steals focus

The overlay is a visual layer only. It must never intercept input.

### 8.5 Success Finish

On successful direct insertion:

- the star cluster should contract into the destination point
- particle brightness should decay immediately
- the overlay should be removed without lingering halo or residue

### 8.6 Downgraded Finish

On clipboard-oriented outcomes:

- keep the same inbound travel
- replace the clean collapse with a slightly different terminal beat
- the downgraded beat should be neutral, not red or alarming
- use shape or timing differences rather than a persistent message bubble

One acceptable form is a brief segmented collapse or squared-off endpoint accent that disappears within roughly 120 to 180 milliseconds.

### 8.7 Reduce Motion

When macOS Reduce Motion is enabled:

- keep the overlay and directional effect
- shorten travel distance and remove ornamental drift
- reduce particle count
- rely on restrained fade and scale changes instead of sweeping arcs

The feature should remain understandable without requiring large motion.

## 9. Architecture

The implementation should introduce one new app-owned feedback pipeline and one lightweight geometry-query surface.

### 9.1 Components

#### A. Transcript Injection Overlay Controller

New app-level controller responsible for:

- observing publish-phase transitions
- resolving a visual target snapshot before or at animation start
- creating and destroying a transparent fullscreen panel on the target screen
- passing animation state into a SwiftUI overlay view
- updating the active animation with the eventual delivery outcome for the same publish session only

This controller owns lifecycle only. It should not know how real insertion works internally.

#### B. Transcript Injection Overlay View

New SwiftUI view responsible for:

- rendering the fullscreen transparent canvas
- drawing the particle burst and converging star paths
- rendering different end treatments for success vs downgrade
- respecting Reduce Motion

The view should remain stateless beyond the animation state passed into it.

#### C. Transcript Injection Motion Helper

New pure helper responsible for:

- particle spawn positions
- travel curves
- timing windows
- opacity and scale curves
- alternate downgrade finish rules

This helper should be deterministic and testable without UI harnesses.

#### D. Transcript Injection Target Snapshot Provider

A new narrow surface should expose target-screen geometry for animation only.

It should provide:

- target screen frame or identifier
- focused window frame when available
- focused element frame when available
- a resolved destination point
- minimal app metadata useful for debugging

This geometry query belongs next to the existing focus-capture infrastructure and should extend that surface rather than introduce a second competing target model. It must not change how `publish(_:)` chooses paste vs AX insertion.

### 9.2 Ownership and Module Boundaries

- `SpeechBarInfrastructure` remains the owner of focus capture and Accessibility geometry lookup.
- `SpeechBarApp` owns the visual controller, overlay view, and motion math.
- `SpeechBarApplication` should remain close to orchestration and expose only the publish-phase state the app layer needs to observe.

The key boundary is: infrastructure discovers target geometry, app renders feedback, application coordinates session state.

## 10. Data Flow

The runtime sequence should be:

1. Voice capture begins and the current target is remembered using the existing capture mechanism.
2. Recording, transcription, and optional polishing proceed unchanged.
3. `VoiceSessionCoordinator` creates a fresh publish-feedback session identifier for this publish attempt.
4. `VoiceSessionCoordinator` emits a start signal that contains the session identifier and enough data for the app layer to begin visual feedback.
5. The new overlay controller receives that start signal, requests a target snapshot from the geometry provider, and decides whether an overlay can be shown.
6. If a target screen is available, the controller creates a transparent fullscreen panel on that screen and starts the animation immediately.
7. In parallel, `VoiceSessionCoordinator` calls the existing transcript publisher to perform real insertion.
8. When delivery outcome arrives, `VoiceSessionCoordinator` emits a completion signal tagged with the same publish-feedback session identifier.
9. The overlay controller only updates the active animation when the completion signal matches the in-flight session identifier.
10. The animation completes and the overlay panel is removed.
11. The existing status message flow remains unchanged.

`lastDeliveryOutcome` is not a sufficient source of truth for animation completion because it is persistent state rather than a session-scoped event.

The controller should tolerate publish completing before the animation reaches its terminal beat.

## 11. Files Likely to Change

Primary production additions:

- `Sources/SpeechBarApp/TranscriptInjectionOverlayController.swift`
- `Sources/SpeechBarApp/TranscriptInjectionOverlayView.swift`
- `Sources/SpeechBarApp/TranscriptInjectionOverlayMotion.swift`

Primary production modifications:

- `Sources/SpeechBarApp/StartUpSpeechBarApp.swift`
- `Sources/SpeechBarInfrastructure/FocusedTextTranscriptPublisher.swift`
- `Sources/SpeechBarApplication/VoiceSessionCoordinator.swift`

Potential supporting model additions:

- a session-scoped publish feedback event type
- a small app-facing target snapshot type aligned with the existing focus-capture model

Primary test additions:

- `Tests/SpeechBarTests/TranscriptInjectionOverlayMotionTests.swift`
- `Tests/SpeechBarTests/TranscriptInjectionOverlayControllerTests.swift`

Primary test modifications:

- `Tests/SpeechBarTests/VoiceSessionCoordinatorTests.swift`

The coordinator change should stay narrow. Most new logic should live in the app layer and in pure motion helpers.

## 12. Error Handling and Fallback Rules

### 12.1 Geometry Lookup Failure

If no target screen can be resolved:

- skip the overlay
- continue publish unchanged

### 12.2 Overlay Creation Failure

If the fullscreen feedback panel cannot be created:

- log the failure through existing diagnostics if convenient
- continue publish unchanged

### 12.3 Publish Failure

If publish throws and no delivery outcome is produced:

- stop any in-flight animation quickly
- do not synthesize a fake success finish
- leave the existing error status path unchanged

### 12.4 Repeated Sessions

If a new recording session starts while an older animation is somehow still active:

- cancel and tear down the older animation immediately
- never allow multiple fullscreen publish overlays to stack

## 13. Testing and Verification

Required automated coverage:

- motion helper produces bounded particle positions and timing values
- success and downgrade endings differ deterministically
- Reduce Motion path shortens or simplifies travel
- controller starts an animation when publish begins and target geometry is available
- controller skips animation when no target screen is available
- controller ignores completion events whose session identifier does not match the active animation
- controller updates the active animation when the matching delivery outcome arrives
- clipboard-oriented outcomes select the downgraded ending instead of the clean success collapse
- `.pasteShortcutSent` selects the success ending rather than the downgraded ending

Required command-line verification after implementation:

- `swift test --filter TranscriptInjectionOverlay`
- `swift test --filter VoiceSessionCoordinatorTests`
- `swift test`
- `swift build`

Required manual verification after implementation:

- publish into a normal editable field and confirm stars appear only on the destination screen
- confirm the text inserts immediately rather than waiting for animation completion
- test with the target app on a secondary display and confirm only that display animates
- verify clipboard downgrade still animates with the alternate ending
- enable Reduce Motion and confirm a simplified but understandable effect
- verify no mouse interaction is blocked by the overlay

## 14. Risks and Controls

### 14.1 Visual Dishonesty Risk

A flashy effect could imply direct insertion even when the system actually downgraded to clipboard.

Control:

- use a visibly different downgraded terminal beat
- do not show the same clean success collapse for clipboard outcomes

### 14.2 Wrong-Screen Risk

If geometry resolution is weak, the animation could appear on the wrong display.

Control:

- require a resolved target screen before showing the overlay
- prefer skipping the effect over guessing across displays

### 14.3 Delivery Regression Risk

Tightly coupling animation to publish could accidentally slow or destabilize insertion.

Control:

- keep animation launch separate from `publish(_:)`
- never wait on animation to begin or end before publishing
- keep existing publisher logic unchanged

### 14.4 Stale Outcome Risk

If the overlay subscribes to persistent publish state rather than a session-scoped event, one animation can consume an older session's result.

Control:

- require a fresh publish-feedback session identifier per publish attempt
- require start and completion signals to carry that identifier
- make the overlay controller ignore mismatched completion events

### 14.5 UI Complexity Risk

If logic spreads across coordinator, app shell, and publisher, the feature could become hard to reason about.

Control:

- keep coordinator changes minimal
- centralize visual lifecycle in a dedicated overlay controller
- keep motion math pure and testable

## 15. Implementation Outcome

When implementation is complete:

- transcript delivery still uses the existing paste / AX path
- recognized results gain a dedicated global feedback animation
- the animation appears only on the destination screen
- animation and real delivery run in parallel
- clipboard downgrade remains visible but visually distinct
- no persistent glow or text preview is added
- the new behavior feels more cinematic without making insertion less reliable

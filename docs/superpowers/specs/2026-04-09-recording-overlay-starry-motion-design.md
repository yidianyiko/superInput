# Recording Overlay Starry Motion Design

Status: approved
Date: 2026-04-09
Repository: `/Users/oliver/Downloads/redheak_source_20260407_220321`

## 1. Summary

This document defines the approved design for adding star-themed motion to the recording overlay only.

The approved direction is:

- keep the existing bottom-center recording capsule layout
- keep the cancel button, waveform bars, and confirm button exactly where they are
- add a subtle starfield treatment only while the overlay is in `.recording`
- make the capsule edge glow react to live audio level
- leave `.finalizing`, `.polishing`, `.publishing`, and `.failed` visually unchanged
- respect macOS Reduce Motion by disabling continuous drift and keeping only a restrained static treatment

The user explicitly rejected changing the home page or status-panel visuals for this task.

## 2. Product Intent

The recording overlay should feel alive during capture, not merely present.

When recording is active, the overlay should communicate two things at once:

- it is currently listening
- the app has a star-themed visual identity

The result should still read as a compact control surface rather than a decorative widget. The overlay must stay quick to parse, low-risk to click, and visually calm enough for repeated daily use.

## 3. Design Goals

- Add a visible but restrained star-themed motion treatment to the recording overlay.
- Preserve the current overlay size, layout, and button hit targets.
- Use live audio input to strengthen the glow so the overlay feels responsive to speech.
- Keep the waveform bars as the primary functional recording indicator.
- Limit the new treatment to the `.recording` phase.
- Provide a reduced-motion path that avoids continuous background drift.

## 4. Non-Goals

- Changing the main home window.
- Changing the status bar popover cards.
- Moving the overlay, resizing it, or changing its interaction model.
- Replacing the waveform bars with a different control metaphor.
- Applying star motion to the post-recording `ThinkingDots` states.
- Turning the overlay into a miniature Memory Constellation with cluster labels or bridge lines.

## 5. Approved Direction

Three approaches were considered:

1. Background-only enhancement: add faint stars and edge glow while leaving the rest untouched.
2. Background enhancement plus audio-linked glow: keep the current structure, add subtle star drift, and strengthen glow based on live audio level.
3. Mini constellation treatment: make the whole capsule feel like a small animated star map.

The approved approach is `Background enhancement plus audio-linked glow`.

This gives the overlay a clearer sense of life and brand identity without turning a compact utility surface into a more decorative component.

## 6. User-Visible Behavior

### 6.1 Recording Phase

While `overlayPhase == .recording`:

- the capsule keeps its current dark base
- a low-density starfield appears behind the controls
- stars drift slowly and twinkle subtly
- a soft mint-white glow appears on the capsule edge
- the glow strength increases as recent audio levels rise
- the waveform bars remain centered and visually dominant

The intended visual hierarchy is:

1. controls and waveform
2. audio-reactive glow
3. starfield atmosphere

### 6.2 Non-Recording Phases

While `overlayPhase` is `.finalizing`, `.polishing`, `.publishing`, or `.failed`:

- the existing status pill stays intact
- the `ThinkingDots` behavior remains unchanged
- no starfield or audio glow is shown

This keeps recording-specific feedback distinct from post-processing feedback.

### 6.3 Reduce Motion

When macOS Reduce Motion is enabled:

- the starfield remains visible in recording mode
- star positions stay fixed
- there is no continuous drift animation
- glow can still respond to audio level changes, but without extra ambient motion layers

The reduced-motion path should still communicate “recording is active” without requiring constant motion.

## 7. Architecture

The implementation should add one small pure-motion helper plus one view integration change.

### 7.1 Motion Helper

Create a new `SpeechBarApp` helper dedicated to recording-overlay motion math.

Its responsibilities:

- define a stable set of normalized ambient star positions
- convert `[AudioLevelSample]` into a clamped overlay intensity
- compute per-star offset and opacity for a given timeline phase
- compute edge-glow opacity and blur from audio intensity

This helper should be pure and deterministic so it can be covered by Swift Testing without UI-specific harnesses.

### 7.2 Overlay Integration

`RecordingOverlayController.swift` should remain the owner of overlay rendering.

Changes:

- add a timeline-driven rendering path for the recording pill only
- derive `recordingIntensity` from `coordinator.audioLevelWindow`
- render a starfield layer inside the capsule background
- render an audio-reactive edge glow behind the existing controls
- keep all interaction handlers and panel resizing logic unchanged

## 8. Visual Rules

### 8.1 Density

- use a small number of stars, roughly 6 to 10 visible points
- avoid dense scatter that competes with the waveform bars
- keep motion amplitude small enough that the capsule does not look busy

### 8.2 Color

- stars should be white to mint-white
- glow should stay in the same restrained mint range already suggested by the current waveform gradient
- the base capsule remains predominantly black / charcoal

### 8.3 Motion

- star drift should be slow and smooth
- twinkle should vary opacity modestly rather than flashing
- glow response should feel attached to speech energy, not random breathing

### 8.4 Layout Safety

- no star or glow layer should block button hit testing
- controls must remain the sharpest foreground element
- no new motion should alter capsule dimensions or baseline alignment

## 9. Testing and Verification

Required automated coverage:

- `RecordingOverlayMotion.audioIntensity(from:)` returns `0` for empty input
- audio intensity remains clamped within `0...1`
- star offsets differ across phases while staying within restrained bounds
- glow strength increases as audio intensity increases

Required command-line verification:

- `swift test --filter RecordingOverlayMotion`
- `swift test`
- `swift build`

Required manual verification:

- start recording and confirm the bottom overlay shows subtle drifting stars
- speak louder and confirm the capsule glow becomes more pronounced
- stop recording and confirm the status pill returns to the existing non-star treatment
- enable Reduce Motion and confirm the starfield becomes static

## 10. Risks and Controls

### 10.1 Visual Noise Risk

Too many stars or too much drift would make the overlay feel gimmicky.

Control:

- keep star count low
- keep movement amplitude small
- keep waveform bars as the clearest foreground signal

### 10.2 Accessibility Risk

Continuous motion can be distracting or uncomfortable.

Control:

- gate timeline drift behind `Reduce Motion`
- use static stars plus restrained intensity changes in the reduced-motion path

### 10.3 Performance Risk

The overlay is always-on during recording, so expensive rendering would be wasteful.

Control:

- use a small fixed star set
- keep rendering inside one capsule-sized view
- compute motion from simple deterministic math only

## 11. Implementation Outcome

When implementation is complete:

- the current recording overlay keeps its familiar control structure
- the recording state gains a subtle star-themed animated background
- the capsule edge visibly reacts to live voice energy
- non-recording overlay states remain unchanged
- automated tests cover the motion math that drives the effect

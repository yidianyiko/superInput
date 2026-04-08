# Recording Overlay Starry Motion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a subtle star-themed animated background and audio-reactive glow to the existing recording overlay capsule without changing its layout or non-recording states.

**Architecture:** Keep all panel ownership and interaction flow inside `RecordingOverlayController.swift`, but extract the motion math into a small pure helper so the visual behavior is deterministic and unit-testable. Only the `.recording` overlay path gets the new starfield and glow layers; processing and failure pills remain unchanged.

**Tech Stack:** SwiftUI, AppKit, SpeechBarDomain audio level samples, Swift Testing.

---

### Task 1: Add pure recording-overlay motion coverage

**Files:**
- Create: `Tests/SpeechBarTests/RecordingOverlayMotionTests.swift`
- Create: `Sources/SpeechBarApp/RecordingOverlayMotion.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
import SpeechBarDomain
@testable import SpeechBarApp

@Suite("RecordingOverlayMotion")
struct RecordingOverlayMotionTests {
    @Test
    func audioIntensityIsZeroForEmptySamples() {
        #expect(RecordingOverlayMotion.audioIntensity(from: []) == 0)
    }

    @Test
    func audioIntensityTracksRecentAverageAndPeakWithinBounds() {
        let samples = [
            AudioLevelSample(level: 0.10, peak: 0.15),
            AudioLevelSample(level: 0.22, peak: 0.30),
            AudioLevelSample(level: 0.48, peak: 0.62),
            AudioLevelSample(level: 0.72, peak: 0.90)
        ]

        let intensity = RecordingOverlayMotion.audioIntensity(from: samples)

        #expect(intensity > 0.40)
        #expect(intensity < 0.95)
    }

    @Test
    func starOffsetsStaySubtleButMoveAcrossPhases() {
        let early = RecordingOverlayMotion.starOffset(index: 2, phase: 0, intensity: 0.45)
        let later = RecordingOverlayMotion.starOffset(index: 2, phase: 2.4, intensity: 0.45)

        #expect(abs(early.width - later.width) > 0.05 || abs(early.height - later.height) > 0.05)
        #expect(abs(early.width) <= 4.0)
        #expect(abs(early.height) <= 2.5)
        #expect(abs(later.width) <= 4.0)
        #expect(abs(later.height) <= 2.5)
    }

    @Test
    func edgeGlowStrengthIncreasesAsAudioIntensityRises() {
        let quiet = RecordingOverlayMotion.edgeGlowOpacity(intensity: 0.10)
        let loud = RecordingOverlayMotion.edgeGlowOpacity(intensity: 0.90)

        #expect(loud > quiet)
        #expect(quiet >= 0.10)
        #expect(loud <= 0.28)
    }
}
```

- [ ] **Step 2: Run the targeted test to verify it fails**

Run:

```bash
swift test --filter RecordingOverlayMotion
```

Expected: FAIL with compile errors such as `cannot find 'RecordingOverlayMotion' in scope`.

- [ ] **Step 3: Write the minimal implementation**

Create `Sources/SpeechBarApp/RecordingOverlayMotion.swift`:

```swift
import CoreGraphics
import Foundation
import SpeechBarDomain

enum RecordingOverlayMotion {
    struct AmbientStar: Equatable {
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let seed: Double
    }

    static let ambientStars: [AmbientStar] = [
        .init(x: 0.16, y: 0.30, size: 2.0, seed: 0.2),
        .init(x: 0.24, y: 0.66, size: 1.8, seed: 0.8),
        .init(x: 0.34, y: 0.38, size: 1.6, seed: 1.4),
        .init(x: 0.47, y: 0.72, size: 1.8, seed: 2.0),
        .init(x: 0.56, y: 0.28, size: 2.0, seed: 2.7),
        .init(x: 0.66, y: 0.60, size: 1.5, seed: 3.1),
        .init(x: 0.77, y: 0.34, size: 1.9, seed: 3.8),
        .init(x: 0.84, y: 0.68, size: 1.7, seed: 4.5)
    ]

    static func audioIntensity(from samples: [AudioLevelSample]) -> Double {
        guard !samples.isEmpty else { return 0 }

        let recentSamples = Array(samples.suffix(6))
        let averageLevel = recentSamples.reduce(0) { $0 + $1.level } / Double(recentSamples.count)
        let recentPeak = recentSamples.reduce(0) { max($0, $1.peak) }

        return min(max((averageLevel * 0.65) + (recentPeak * 0.35), 0), 1)
    }

    static func starOffset(index: Int, phase: TimeInterval, intensity: Double) -> CGSize {
        let clampedIntensity = min(max(intensity, 0), 1)
        let seed = ambientStars[index % ambientStars.count].seed
        let amplitude = 1.2 + Double(index % 3) * 0.45 + (clampedIntensity * 0.85)

        return CGSize(
            width: sin((phase * 0.52) + seed) * amplitude,
            height: cos((phase * 0.44) + (seed * 1.31)) * (amplitude * 0.55)
        )
    }

    static func starOpacity(index: Int, phase: TimeInterval, intensity: Double) -> Double {
        let clampedIntensity = min(max(intensity, 0), 1)
        let seed = ambientStars[index % ambientStars.count].seed
        let shimmer = 0.08 * sin((phase * 0.86) + seed + Double(index) * 0.41)
        let base = 0.14 + (clampedIntensity * 0.10)

        return min(max(base + shimmer, 0.08), 0.34)
    }

    static func edgeGlowOpacity(intensity: Double) -> Double {
        let clampedIntensity = min(max(intensity, 0), 1)
        return 0.10 + (clampedIntensity * 0.18)
    }

    static func edgeGlowBlurRadius(intensity: Double) -> CGFloat {
        let clampedIntensity = min(max(intensity, 0), 1)
        return CGFloat(4 + (clampedIntensity * 6))
    }

    static func nebulaOpacity(intensity: Double) -> Double {
        let clampedIntensity = min(max(intensity, 0), 1)
        return 0.06 + (clampedIntensity * 0.14)
    }
}
```

- [ ] **Step 4: Run the targeted test to verify it passes**

Run:

```bash
swift test --filter RecordingOverlayMotion
```

Expected: PASS for the `RecordingOverlayMotion` suite.

- [ ] **Step 5: Commit**

```bash
git add Tests/SpeechBarTests/RecordingOverlayMotionTests.swift Sources/SpeechBarApp/RecordingOverlayMotion.swift
git commit -m "Add recording overlay motion helpers"
```

### Task 2: Integrate the starfield and audio-reactive glow into the recording pill

**Files:**
- Modify: `Sources/SpeechBarApp/RecordingOverlayController.swift`
- Test: `Tests/SpeechBarTests/RecordingOverlayMotionTests.swift`

- [ ] **Step 1: Add timeline gating and recording intensity plumbing**

Update `RecordingOverlayView` so only the recording pill uses a running timeline:

```swift
private struct RecordingOverlayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var coordinator: VoiceSessionCoordinator

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !shouldAnimateTimeline)) { context in
            let phase = shouldAnimateTimeline ? context.date.timeIntervalSinceReferenceDate : 0

            Group {
                if coordinator.overlayPhase == .recording {
                    recordingPill(phase: phase)
                } else {
                    statusPill
                }
            }
            .frame(width: pillWidth, height: pillHeight)
            .clipShape(Capsule(style: .continuous))
            .background(Color.clear)
        }
    }

    private var shouldAnimateTimeline: Bool {
        coordinator.overlayPhase == .recording && !reduceMotion
    }

    private var recordingIntensity: Double {
        RecordingOverlayMotion.audioIntensity(from: coordinator.audioLevelWindow)
    }
}
```

- [ ] **Step 2: Replace the static recording capsule background with a starfield layer**

Convert `recordingPill` from a computed property into a phase-aware function and add a background helper:

```swift
private func recordingPill(phase: TimeInterval) -> some View {
    let glowOpacity = RecordingOverlayMotion.edgeGlowOpacity(intensity: recordingIntensity)
    let glowRadius = RecordingOverlayMotion.edgeGlowBlurRadius(intensity: recordingIntensity)

    return ZStack {
        Capsule(style: .continuous)
            .fill(Color.black.opacity(0.95))
            .overlay(recordingBackground(phase: phase))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color(red: 0.58, green: 0.93, blue: 0.82).opacity(glowOpacity), lineWidth: 1.1)
                    .blur(radius: glowRadius)
            )
            .shadow(
                color: Color(red: 0.48, green: 0.88, blue: 0.78).opacity(glowOpacity * 0.65),
                radius: glowRadius,
                x: 0,
                y: 0
            )

        HStack(spacing: 10) {
            actionButton(
                systemName: "xmark",
                foreground: .white.opacity(0.92),
                background: Color.white.opacity(0.17)
            ) {
                coordinator.cancelCaptureFromOverlay()
            }

            WaveformBars(samples: coordinator.audioLevelWindow)
                .frame(width: 42, height: 14)

            actionButton(
                systemName: "checkmark",
                foreground: .black.opacity(0.92),
                background: .white
            ) {
                coordinator.finalizeCaptureFromOverlay()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }
}

private func recordingBackground(phase: TimeInterval) -> some View {
    GeometryReader { proxy in
        let size = proxy.size

        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.14, blue: 0.18).opacity(0.82),
                    Color.black.opacity(0.30)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.60, green: 0.92, blue: 0.83).opacity(
                        RecordingOverlayMotion.nebulaOpacity(intensity: recordingIntensity)
                    ),
                    Color.clear
                ],
                center: .center,
                startRadius: 4,
                endRadius: 64
            )

            ForEach(Array(RecordingOverlayMotion.ambientStars.enumerated()), id: \.offset) { item in
                let index = item.offset
                let star = item.element
                let offset = reduceMotion
                    ? .zero
                    : RecordingOverlayMotion.starOffset(index: index, phase: phase, intensity: recordingIntensity)

                Circle()
                    .fill(
                        Color.white.opacity(
                            RecordingOverlayMotion.starOpacity(index: index, phase: phase, intensity: recordingIntensity)
                        )
                    )
                    .frame(width: star.size, height: star.size)
                    .position(
                        x: (star.x * size.width) + offset.width,
                        y: (star.y * size.height) + offset.height
                    )
            }
        }
        .clipShape(Capsule(style: .continuous))
        .allowsHitTesting(false)
    }
}
```

- [ ] **Step 3: Keep non-recording pills unchanged and verify the file still only changes the recording path**

After the edit, `statusPill`, `ThinkingDots`, `WaveformBars`, panel sizing, and overlay-phase transitions should remain functionally identical. The only structural differences in `RecordingOverlayController.swift` should be:

```swift
// new
@Environment(\.accessibilityReduceMotion) private var reduceMotion

// changed
private func recordingPill(phase: TimeInterval) -> some View

// new
private func recordingBackground(phase: TimeInterval) -> some View
private var shouldAnimateTimeline: Bool
private var recordingIntensity: Double
```

- [ ] **Step 4: Run the targeted tests and build the app**

Run:

```bash
swift test --filter RecordingOverlayMotion
swift build
```

Expected:

- `RecordingOverlayMotion` tests still PASS
- package build succeeds without changing any non-overlay targets

- [ ] **Step 5: Commit**

```bash
git add Sources/SpeechBarApp/RecordingOverlayController.swift
git commit -m "Add starfield motion to recording overlay"
```

### Task 3: Verify behavior end to end

**Files:**
- Test: `Tests/SpeechBarTests/RecordingOverlayMotionTests.swift`
- Modify if needed: `Sources/SpeechBarApp/RecordingOverlayController.swift`
- Modify if needed: `Sources/SpeechBarApp/RecordingOverlayMotion.swift`

- [ ] **Step 1: Run the full automated suite**

Run:

```bash
swift test
```

Expected: full `SpeechBarTests` suite passes.

- [ ] **Step 2: Build an app bundle for manual verification**

Run:

```bash
./Scripts/build_app_bundle.sh
```

Expected: the script completes successfully and refreshes `dist/SlashVibe.app`.

- [ ] **Step 3: Manually verify the recording overlay in the app**

Manual checklist:

```text
1. Launch the app and start recording from either the status-panel trigger or the home window.
2. Confirm the bottom-center recording capsule keeps the current button and waveform layout.
3. Confirm a faint starfield appears only while the overlay is recording.
4. Speak softly, then loudly, and confirm the capsule edge glow becomes stronger with louder input.
5. Stop recording and confirm the overlay returns to the existing processing pill without stars.
6. Trigger a failed recording path if convenient and confirm the failure pill still uses the old error treatment.
```

- [ ] **Step 4: Verify the reduced-motion path**

Manual checklist:

```text
1. Enable Reduce Motion in macOS Accessibility settings.
2. Start another recording.
3. Confirm the overlay still shows the star treatment, but stars no longer drift continuously.
4. Confirm the capsule remains readable and the controls stay clickable.
```

- [ ] **Step 5: Commit any verification-driven follow-up fixes as a separate commit**

If verification requires small visual tuning, commit only those follow-ups:

```bash
git add Sources/SpeechBarApp/RecordingOverlayController.swift Sources/SpeechBarApp/RecordingOverlayMotion.swift Tests/SpeechBarTests/RecordingOverlayMotionTests.swift
git commit -m "Tune recording overlay starfield motion"
```

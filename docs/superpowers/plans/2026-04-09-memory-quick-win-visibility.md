# Memory Quick-Win Visibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing memory system feel visibly active by default through recall-on startup behavior, clearer capture feedback, stronger recording-time hint display, and minimum viable hide/delete controls.

**Architecture:** Keep the current memory modules and constellation UI intact. Extend the existing `MemoryConstellationStore` and related views to track capture deltas, highlight recently added memories, and forward hide/delete actions into the existing storage-backed memory coordinator.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing, existing `MemoryDomain` / `MemoryCore` / `MemoryStorageSQLite` targets.

---

### Task 1: Enable Recall By Default

**Files:**
- Modify: `Sources/SpeechBarApp/MemoryFeatureFlagStore.swift`
- Modify: `Tests/SpeechBarTests/MemoryFeatureFlagStoreTests.swift`

- [ ] Write the failing test for recall-enabled defaults.
- [ ] Run the focused test and verify it fails.
- [ ] Flip the default behavior in the feature-flag store.
- [ ] Re-run the focused test and verify it passes.

### Task 2: Track Post-Capture Added Memories

**Files:**
- Modify: `Sources/SpeechBarApp/MemoryConstellationModels.swift`
- Modify: `Sources/SpeechBarApp/MemoryConstellationBuilder.swift`
- Modify: `Sources/SpeechBarApp/MemoryConstellationStore.swift`
- Modify: `Tests/SpeechBarTests/MemoryConstellationStoreTests.swift`

- [ ] Write a failing store test for post-capture added-memory status.
- [ ] Run the focused test and verify it fails.
- [ ] Add store-side capture delta tracking and builder inputs.
- [ ] Re-run the focused test and verify it passes.

### Task 3: Highlight Newly Added Stars

**Files:**
- Modify: `Sources/SpeechBarApp/MemoryConstellationModels.swift`
- Modify: `Sources/SpeechBarApp/MemoryConstellationCanvasView.swift`
- Modify: `Tests/SpeechBarTests/MemoryConstellationBuilderTests.swift`

- [ ] Write a failing test for recent-star marking.
- [ ] Run the focused test and verify it fails.
- [ ] Render a visible recent marker in the star layer.
- [ ] Re-run the focused test and verify it passes.

### Task 4: Promote Memory Hints In Recording Overlay

**Files:**
- Modify: `Sources/SpeechBarApp/RecordingOverlayController.swift`
- Modify: `Tests/SpeechBarTests/RecordingOverlayViewTests.swift`

- [ ] Write a failing overlay test for hint-driven expansion.
- [ ] Run the focused test and verify it fails.
- [ ] Expand the recording overlay and render up to two hint chips.
- [ ] Re-run the focused test and verify it passes.

### Task 5: Add Minimum Hide/Delete Controls

**Files:**
- Modify: `Sources/MemoryDomain/MemoryDomain.swift`
- Modify: `Sources/MemoryCore/MemoryCore.swift`
- Modify: `Sources/MemoryStorageSQLite/MemoryStorageSQLite.swift`
- Modify: `Sources/SpeechBarApp/MemoryConstellationScreen.swift`
- Modify: `Sources/SpeechBarApp/MemoryConstellationDetailPanelView.swift`
- Modify: `Sources/SpeechBarApp/MemoryConstellationStore.swift`
- Modify: `Tests/MemoryTests/MemoryStorageSQLiteTests.swift`
- Modify: `Tests/SpeechBarTests/MemoryConstellationStoreTests.swift`

- [ ] Write failing tests for hide and delete flows.
- [ ] Run the focused tests and verify they fail.
- [ ] Add hidden-status persistence and UI-triggered management actions.
- [ ] Re-run the focused tests and verify they pass.

### Task 6: Verify And Commit

**Files:**
- Modify: working tree verification only

- [ ] Run focused test groups for modified memory and app UI behavior.
- [ ] Run a broader memory-oriented regression suite.
- [ ] Review the diff for scope correctness.
- [ ] Commit the implementation with a focused message.

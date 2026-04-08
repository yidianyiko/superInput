# Polish Playground Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a manual in-app playground that lets the user paste text and run the existing OpenAI polish flow without recording audio.

**Architecture:** Keep the feature in `SpeechBarApp` as a small observable store with injected async runner logic. Reuse the existing `TranscriptPostProcessor` and current user profile context so the test path exercises the same polish backend and persona settings as the voice flow, while avoiding changes to the core recording coordinator.

**Tech Stack:** SwiftUI, Combine, Swift Testing, existing `TranscriptPostProcessor` abstraction.

---

### Task 1: Add store tests

**Files:**
- Create: `Tests/SpeechBarTests/PolishPlaygroundStoreTests.swift`
- Modify: `Tests/SpeechBarTests/TestDoubles.swift`

- [ ] **Step 1: Write the failing test**
- [ ] **Step 2: Run the targeted test to verify it fails**
- [ ] **Step 3: Implement the minimal store surface needed by the test**
- [ ] **Step 4: Run the targeted test to verify it passes**

### Task 2: Wire the store into the app UI

**Files:**
- Create: `Sources/SpeechBarApp/PolishPlaygroundStore.swift`
- Modify: `Sources/SpeechBarApp/StartUpSpeechBarApp.swift`
- Modify: `Sources/SpeechBarApp/HomeWindowController.swift`
- Modify: `Sources/SpeechBarApp/HomeWindowView.swift`
- Modify: `Sources/SpeechBarApp/OffscreenHomeSnapshot.swift`

- [ ] **Step 1: Inject a `PolishPlaygroundStore` from app startup**
- [ ] **Step 2: Pass the store into `HomeWindowView`**
- [ ] **Step 3: Add a simple input / run / output panel to the model page**
- [ ] **Step 4: Keep the UI read-only where appropriate and surface errors inline**

### Task 3: Verify end to end

**Files:**
- Test: `Tests/SpeechBarTests/PolishPlaygroundStoreTests.swift`
- Test: `Tests/SpeechBarTests`

- [ ] **Step 1: Run `swift test --filter PolishPlaygroundStore`**
- [ ] **Step 2: Run `swift test`**

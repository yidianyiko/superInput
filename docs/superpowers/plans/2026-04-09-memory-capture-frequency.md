# Memory Capture Frequency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the default memory system generate visible memories more often by loosening extraction rules inside `DefaultMemoryExtractor` without changing schema, storage, recall APIs, or the constellation UI.

**Architecture:** Keep the entire change inside `Sources/MemoryExtraction/MemoryExtraction.swift`, where one input event is turned into zero or more `MemoryItem`s. First remove the `style` extractor's `polish`-only restriction, then add a small scene-descriptor helper that falls back from `fieldLabel` to `pageTitle`, `windowTitle`, and finally `appName`, while choosing the narrowest existing `MemoryScope` that still matches recall.

**Tech Stack:** Swift 6.2 packages, `MemoryDomain`, `MemoryExtraction`, Swift Testing (`import Testing`), `swift test`, `swift build`.

---

## File Structure

### Existing Files To Modify

- `Sources/MemoryExtraction/MemoryExtraction.swift`
  - Keep `DefaultMemoryExtractor` as the only production change surface.
  - Relax `styleMemory(from:)` so transcribed inputs can also emit a style memory.
  - Replace the current `fieldLabel`-only scene gate with a fallback descriptor helper that returns both the chosen label and the appropriate existing `MemoryScope`.
- `Tests/MemoryTests/MemoryExtractionTests.swift`
  - Keep all extractor behavior coverage in one test suite.
  - Add a small `makeEvent(...)` helper so the new transcribe/page/window/app fallback cases are readable.
  - Add focused regression tests for style-on-transcribe, scene fallback, multi-category extraction, and sensitive exclusion.

## Task 1: Let transcribed inputs produce style memories

**Files:**
- Modify: `Tests/MemoryTests/MemoryExtractionTests.swift`
- Modify: `Sources/MemoryExtraction/MemoryExtraction.swift`

- [ ] **Step 1: Write the failing test**

Append this test and helper to `Tests/MemoryTests/MemoryExtractionTests.swift`:

```swift
    @Test
    func transcribeEventCreatesStyleMemory() async throws {
        let extractor = DefaultMemoryExtractor()
        let event = makeEvent(
            rawTranscript: "reply shortly",
            insertedText: "reply shortly",
            finalUserEditedText: "reply shortly"
        )

        let memories = try await extractor.extract(from: event)

        let style = try #require(memories.first { $0.type == .style })
        #expect(style.valueFingerprint == "brevity=short")
        #expect(style.scope == .app("com.apple.TextEdit"))
        #expect(style.confidence == 0.65)
    }
}

private func makeEvent(
    appIdentifier: String = "com.apple.TextEdit",
    appName: String = "TextEdit",
    windowTitle: String? = "Untitled",
    pageTitle: String? = nil,
    fieldRole: String = "AXTextArea",
    fieldLabel: String? = "Body",
    sensitivityClass: SensitivityClass = .normal,
    observationStatus: ObservationStatus = .observedFinal,
    actionType: MemoryActionType = .transcribe,
    rawTranscript: String? = "hello world",
    polishedText: String? = nil,
    insertedText: String? = "hello world",
    finalUserEditedText: String? = "hello world"
) -> InputEvent {
    InputEvent(
        id: UUID(),
        timestamp: Date(timeIntervalSince1970: 0),
        languageCode: "en",
        localeIdentifier: "en-US",
        appIdentifier: appIdentifier,
        appName: appName,
        windowTitle: windowTitle,
        pageTitle: pageTitle,
        fieldRole: fieldRole,
        fieldLabel: fieldLabel,
        sensitivityClass: sensitivityClass,
        observationStatus: observationStatus,
        actionType: actionType,
        rawTranscript: rawTranscript,
        polishedText: polishedText,
        insertedText: insertedText,
        finalUserEditedText: finalUserEditedText,
        outcome: .published,
        durationMs: 900,
        source: .speech
    )
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter MemoryExtraction
```

Expected: FAIL in `transcribeEventCreatesStyleMemory` because `styleMemory(from:)` still returns `nil` for `.transcribe` events.

- [ ] **Step 3: Write minimal implementation**

Replace `styleMemory(from:)` in `Sources/MemoryExtraction/MemoryExtraction.swift` with:

```swift
    private func styleMemory(from event: InputEvent) -> MemoryItem? {
        guard let final = event.effectiveLearningText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !final.isEmpty else {
            return nil
        }

        let brevity = final.count < 80 ? "short" : "long"
        let confidence = event.hasConfirmedFinalText ? 0.65 : 0.45
        return makeMemory(
            type: .style,
            key: "style:\(event.appIdentifier):default",
            payload: "brevity=\(brevity)",
            scope: .app(event.appIdentifier),
            confidence: confidence,
            sourceEventID: event.id,
            timestamp: event.timestamp,
            confirmedAt: event.hasConfirmedFinalText ? event.timestamp : nil
        )
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
swift test --filter MemoryExtraction
```

Expected: PASS for `transcribeEventCreatesStyleMemory` and the pre-existing `MemoryExtraction` tests.

- [ ] **Step 5: Commit**

```bash
git add Tests/MemoryTests/MemoryExtractionTests.swift Sources/MemoryExtraction/MemoryExtraction.swift
git commit -m "Increase style memory capture for transcribed input"
```

## Task 2: Add scene fallback extraction and lock in multi-memory coverage

**Files:**
- Modify: `Tests/MemoryTests/MemoryExtractionTests.swift`
- Modify: `Sources/MemoryExtraction/MemoryExtraction.swift`

- [ ] **Step 1: Write the failing tests**

Append these tests inside `MemoryExtractionTests` in `Tests/MemoryTests/MemoryExtractionTests.swift`:

```swift
    @Test
    func pageTitleFallbackCreatesSceneMemoryWithoutFieldLabel() async throws {
        let extractor = DefaultMemoryExtractor()
        let event = makeEvent(
            appIdentifier: "com.apple.mail",
            appName: "Mail",
            windowTitle: "Reply",
            pageTitle: "Inbox Thread",
            fieldLabel: nil,
            rawTranscript: "reply soon",
            insertedText: "reply soon",
            finalUserEditedText: "reply soon"
        )

        let memories = try await extractor.extract(from: event)

        let scene = try #require(memories.first { $0.type == .scene })
        #expect(scene.key == "scene:com.apple.mail:inbox thread")
        #expect(scene.scope == .field(
            appIdentifier: "com.apple.mail",
            windowTitle: "Reply",
            fieldRole: "AXTextArea",
            fieldLabel: nil
        ))
    }

    @Test
    func windowTitleFallbackCreatesSceneMemoryWhenPageTitleMissing() async throws {
        let extractor = DefaultMemoryExtractor()
        let event = makeEvent(
            appIdentifier: "com.apple.mail",
            appName: "Mail",
            windowTitle: "Draft Reply",
            pageTitle: nil,
            fieldLabel: nil,
            rawTranscript: "ship tomorrow",
            insertedText: "ship tomorrow",
            finalUserEditedText: "ship tomorrow"
        )

        let memories = try await extractor.extract(from: event)

        let scene = try #require(memories.first { $0.type == .scene })
        #expect(scene.key == "scene:com.apple.mail:draft reply")
        #expect(scene.scope == .field(
            appIdentifier: "com.apple.mail",
            windowTitle: "Draft Reply",
            fieldRole: "AXTextArea",
            fieldLabel: nil
        ))
    }

    @Test
    func appNameFallbackCreatesAppScopedSceneMemoryWhenNoOtherContextExists() async throws {
        let extractor = DefaultMemoryExtractor()
        let event = makeEvent(
            appIdentifier: "com.apple.notes",
            appName: "Notes",
            windowTitle: nil,
            pageTitle: nil,
            fieldLabel: nil,
            rawTranscript: "buy milk",
            insertedText: "buy milk",
            finalUserEditedText: "buy milk"
        )

        let memories = try await extractor.extract(from: event)

        let scene = try #require(memories.first { $0.type == .scene })
        #expect(scene.key == "scene:com.apple.notes:notes")
        #expect(scene.scope == .app("com.apple.notes"))
    }

    @Test
    func sparseMetadataTranscribeEventProducesAllFourMemoryTypes() async throws {
        let extractor = DefaultMemoryExtractor()
        let event = makeEvent(
            appIdentifier: "com.apple.mail",
            appName: "Mail",
            windowTitle: "Draft Reply",
            pageTitle: nil,
            fieldLabel: nil,
            rawTranscript: "open ai roadmap",
            insertedText: "open ai roadmap",
            finalUserEditedText: "OpenAI roadmap"
        )

        let memories = try await extractor.extract(from: event)

        #expect(memories.count == 4)
        #expect(Set(memories.map(\.type)) == [.correction, .vocabulary, .scene, .style])
    }

    @Test
    func secureExcludedEventStillProducesNoMemories() async throws {
        let extractor = DefaultMemoryExtractor()
        let event = makeEvent(
            appIdentifier: "com.1password.1password",
            appName: "1Password",
            windowTitle: "Sign In",
            fieldRole: "AXSecureTextField",
            fieldLabel: "Password",
            sensitivityClass: .secureExcluded,
            observationStatus: .blockedSensitive,
            rawTranscript: nil,
            insertedText: nil,
            finalUserEditedText: nil
        )

        let memories = try await extractor.extract(from: event)

        #expect(memories.isEmpty)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter MemoryExtraction
```

Expected: FAIL in the three fallback scene tests and in `sparseMetadataTranscribeEventProducesAllFourMemoryTypes` because `sceneMemory(from:)` still requires `fieldLabel`.

- [ ] **Step 3: Write minimal implementation**

Replace `sceneMemory(from:)` and add the two private helpers below it in `Sources/MemoryExtraction/MemoryExtraction.swift`:

```swift
    private func sceneMemory(from event: InputEvent) -> MemoryItem? {
        guard let descriptor = sceneDescriptor(from: event) else {
            return nil
        }

        let confidence = event.hasConfirmedFinalText ? 0.65 : 0.45
        return makeMemory(
            type: .scene,
            key: "scene:\(event.appIdentifier):\(normalized(descriptor.label))",
            payload: event.fieldRole,
            scope: descriptor.scope,
            confidence: confidence,
            sourceEventID: event.id,
            timestamp: event.timestamp,
            confirmedAt: event.hasConfirmedFinalText ? event.timestamp : nil
        )
    }

    private func sceneDescriptor(from event: InputEvent) -> (label: String, scope: MemoryScope)? {
        if let fieldLabel = trimmed(event.fieldLabel) {
            return (
                label: fieldLabel,
                scope: .field(
                    appIdentifier: event.appIdentifier,
                    windowTitle: event.windowTitle,
                    fieldRole: event.fieldRole,
                    fieldLabel: fieldLabel
                )
            )
        }
        if let pageTitle = trimmed(event.pageTitle) {
            return (
                label: pageTitle,
                scope: .field(
                    appIdentifier: event.appIdentifier,
                    windowTitle: event.windowTitle,
                    fieldRole: event.fieldRole,
                    fieldLabel: nil
                )
            )
        }
        if let windowTitle = trimmed(event.windowTitle) {
            return (
                label: windowTitle,
                scope: .field(
                    appIdentifier: event.appIdentifier,
                    windowTitle: event.windowTitle,
                    fieldRole: event.fieldRole,
                    fieldLabel: nil
                )
            )
        }
        if let appName = trimmed(event.appName) {
            return (
                label: appName,
                scope: .app(event.appIdentifier)
            )
        }
        return nil
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }
        return trimmedValue
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
swift test --filter MemoryExtraction
```

Expected: PASS for the full `MemoryExtraction` suite, including:

- `transcribeEventCreatesStyleMemory`
- `pageTitleFallbackCreatesSceneMemoryWithoutFieldLabel`
- `windowTitleFallbackCreatesSceneMemoryWhenPageTitleMissing`
- `appNameFallbackCreatesAppScopedSceneMemoryWhenNoOtherContextExists`
- `sparseMetadataTranscribeEventProducesAllFourMemoryTypes`
- `secureExcludedEventStillProducesNoMemories`

- [ ] **Step 5: Run full verification**

Run:

```bash
swift test
swift build
```

Expected:

- `swift test` exits `0`
- `swift build` exits `0`

- [ ] **Step 6: Commit**

```bash
git add Tests/MemoryTests/MemoryExtractionTests.swift Sources/MemoryExtraction/MemoryExtraction.swift
git commit -m "Increase scene fallback memory capture"
```

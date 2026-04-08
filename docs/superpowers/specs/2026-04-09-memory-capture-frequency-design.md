# Memory Capture Frequency Design

Status: approved
Date: 2026-04-09
Repository: `/Users/oliver/Downloads/redheak_source_20260407_220321`

## 1. Summary

This document defines the approved design for making memory growth more obvious in the default product behavior.

The approved direction is:

- keep the existing memory schema and current four memory types
- keep storage, recall interfaces, and constellation UI structure unchanged
- increase capture frequency by making a single input event produce more memory categories more often
- prefer a simple and aggressive extraction strategy over a careful and conservative one
- accept higher capture noise for the short term so tomorrow's demo shows clearer memory growth
- keep recall somewhat protected by the existing confidence threshold rather than by adding new extraction gates

The user explicitly chose default product behavior rather than a demo-only mode, preferred faster visible growth over recall purity, and preferred growth from richer extraction instead of duplicate retention.

## 2. Product Intent

The memory system currently records one input event per completed voice session, but visible constellation growth is inconsistent because extraction is selective.

For the upcoming demo, and for the default product behavior afterward, the system should feel like it is learning actively. A normal successful input should more often turn into multiple visible memories instead of just one.

The goal is not to make the model smarter in one step. The goal is to make learning look alive and cumulative with minimal implementation risk.

## 3. Design Goals

- Increase the average number of stored memories generated from a normal successful input.
- Make constellation growth feel more immediate after each completed voice session.
- Keep implementation tightly scoped so it can ship quickly.
- Avoid changes to database schema, recall API shape, or UI grouping.
- Preserve the current correction-memory behavior because it is already the most reliable signal.

## 4. Non-Goals

- Adding new memory types.
- Changing the memory database schema.
- Changing `MemoryCoordinator` ranking or deduplication logic.
- Reworking constellation layout, grouping, or bridge scoring.
- Introducing a demo-only feature flag.
- Fine-tuning recall quality with new thresholds or advanced heuristics.

## 5. Approved Direction

Three approaches were considered:

1. Loosen the current extraction rules while keeping the existing schema and types.
2. Add new memory types so one event can naturally fan out into more categories.
3. Preserve more near-duplicate memories by weakening deduplication.

The approved approach is `Loosen the current extraction rules while keeping the existing schema and types`.

This is the simplest way to produce faster visible growth while staying aligned with the user's requirement that growth should come mainly from richer per-event extraction rather than from storing repeated duplicates.

## 6. User-Visible Behavior

### 6.1 Successful Voice Input

After a successful voice session is published:

- the system still records one `InputEvent`
- extraction should now more often produce `vocabulary + scene + style`
- confirmed rewrites can still additionally produce `correction`
- a typical successful input should therefore often create 2 to 3 memories, and sometimes 4

The intended result is that the memory constellation gains visible stars and relationship structure more quickly during normal use.

### 6.2 Scene Capture

Scene memory generation should become more permissive.

Current behavior depends on `fieldLabel` being present. The approved behavior uses a fallback chain:

1. `fieldLabel`
2. `pageTitle`
3. `windowTitle`
4. `appName`

This means text fields and apps that do not expose a useful accessibility label can still contribute a scene memory.

### 6.3 Style Capture

Style memory generation should no longer require `actionType == .polish`.

Normal transcription results should also produce a simple style memory, using the existing coarse brevity signal:

- `brevity=short`
- `brevity=long`

This keeps the implementation simple and raises the chance that almost every normal input yields a style memory.

### 6.4 Vocabulary Capture

Vocabulary extraction should remain broadly as-is.

It already provides one of the most reliable paths for memory creation, including lower-confidence capture when final text cannot be observed. No new restriction should be added for this task.

### 6.5 Sensitive Inputs

Sensitive exclusion behavior remains unchanged.

If the event is classified as neither `.normal` nor `.redacted`, extraction still returns no memories. This task increases frequency only for eligible inputs and does not weaken the current privacy boundary.

## 7. Architecture

Implementation is intentionally narrow.

### 7.1 Files to Change

Primary production change:

- `Sources/MemoryExtraction/MemoryExtraction.swift`

Primary test changes:

- `Tests/MemoryTests/MemoryExtractionTests.swift`

No domain, storage, or app-shell files should be changed for this task unless a small test fixture adjustment is required.

### 7.2 Extraction Rules

The extractor should behave as follows:

- `correctionMemory(from:)`: unchanged
- `vocabularyMemory(from:)`: unchanged
- `sceneMemory(from:)`: use the new label fallback chain and continue creating field-oriented scene memories when possible
- `styleMemory(from:)`: remove the `actionType == .polish` guard and keep the current brevity-based payload

The extractor remains the single place where capture aggressiveness is tuned.

### 7.3 Storage and Recall

Storage behavior remains unchanged:

- one input event is inserted
- extracted memories are upserted by existing `identityHash`

Recall behavior also remains unchanged:

- ranking logic stays the same
- recall still uses the existing minimum confidence thresholds

This means capture becomes more aggressive while recall remains relatively conservative.

## 8. Testing and Verification

Required automated coverage:

- a normal `.transcribe` event can now produce a `style` memory
- a scene memory is produced when `fieldLabel` is missing but `pageTitle` is available
- a scene memory is produced when `fieldLabel` and `pageTitle` are missing but `windowTitle` is available
- a representative successful input can produce multiple memory categories from one event
- sensitive excluded events still produce zero memories

Required command-line verification:

- `swift test --filter MemoryExtraction`
- `swift test`
- `swift build`

Manual verification after implementation:

- complete several normal voice inputs in different apps or windows
- confirm the memory constellation count grows faster than before
- confirm scene and style stars appear even when accessibility metadata is sparse
- confirm secure or opted-out fields still do not generate visible memories

## 9. Risks and Controls

### 9.1 Capture Noise

More permissive extraction will create noisier `scene` and `style` memories.

Accepted tradeoff:

- this is intentional for the short term
- recall remains partially protected by its existing confidence threshold

### 9.2 Repeated Style Memories

Because style extraction becomes much more common, some apps may repeatedly converge on the same brevity memory.

Accepted tradeoff:

- current upsert behavior already limits exact duplicates
- this task does not attempt to diversify or age style memories

### 9.3 Weak Scene Labels

Fallback labels such as `windowTitle` or `appName` may be less semantically precise than `fieldLabel`.

Accepted tradeoff:

- visible growth matters more than label quality for this iteration
- the fallback chain is still ordered from most specific to least specific

## 10. Implementation Outcome

When implementation is complete:

- the default product behavior generates memories more aggressively
- successful voice inputs more often create multiple memory categories
- constellation growth becomes easier to demonstrate after each session
- privacy-sensitive inputs remain excluded
- recall remains structurally unchanged while capture becomes simpler and rougher

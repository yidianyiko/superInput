# Personal Input Memory and Action Runtime Design

Status: proposed
Date: 2026-04-08
Repository: `/data/projects/superInput`

## 1. Summary

This document defines a reusable memory system for SlashVibe that upgrades the current speech input workflow into a personal input agent.

The system learns from real input behavior, not only from configuration. It observes what the user said, what the system transcribed, what the system inserted, and what the user finally changed the text to. It then turns those observations into reusable memories that improve transcription, polish, and direct-fill actions for comments and simple forms.

The memory system will live in the current repository as a set of independent Swift Package targets. It must serve the current app first while remaining reusable by future projects.

Phase 1 is package-embedded and local-first. It is not a separate memory server.

## 2. Product Goal

SlashVibe is not evolving into a general chat assistant. It is evolving into a personal input agent centered on text entry.

The memory system exists to make the product:

- more accurate during transcription
- more personalized during text polish
- more automatic when filling comments and simple text fields
- less dependent on manual profile configuration over time

## 3. Goals

- Learn from actual user input behavior and final edits.
- Improve both transcription correction and polish personalization.
- Support direct fill for comments, text areas, and simple single-page forms.
- Keep memory visible, editable, disable-able, and deletable.
- Keep hot-path recall fast enough for interactive input.
- Keep the implementation reusable by other projects inside the same monorepo.

## 4. Non-Goals

- General long-horizon agent memory for arbitrary conversations.
- Automatic submission of forms, comments, or any irreversible action.
- Payment flows, security settings, account management, or multi-step workflows.
- Cross-device sync in the first implementation phase.
- A dedicated memory service process in the first implementation phase.

## 5. Core Product Principle

Memory truth is ranked by user intent, not by model output.

The precedence order is:

```text
final user-edited text
> inserted text
> polished text
> raw transcript
```

Whenever two signals conflict, the system must prefer the highest-ranked source above.

This rule is global. It applies to extraction, consolidation, recall ranking, and future learning logic.

## 6. Scope of the First Memory Program

This document covers the first full memory program, which will ship in multiple delivery phases.

The program includes:

- input event capture
- memory extraction
- local storage
- recall for transcription and polish
- direct fill for comments, text fields, and simple forms
- memory management UI
- diagnostics and testing

The program excludes:

- automatic submit
- browser automation across multiple pages
- remote sync
- remote memory backend
- generalized planner-style agents

## 7. Monorepo Structure

The memory system will be added as new targets inside the existing Swift package.

```text
superInput/
├─ Package.swift
├─ Sources/
│  ├─ SpeechBarApp/
│  ├─ SpeechBarApplication/
│  ├─ SpeechBarDomain/
│  ├─ SpeechBarInfrastructure/
│  ├─ MemoryDomain/
│  ├─ MemoryCore/
│  ├─ MemoryExtraction/
│  ├─ MemoryStorageSQLite/
│  └─ ActionRuntime/
└─ Tests/
   ├─ SpeechBarTests/
   └─ MemoryTests/
```

Rationale:

- The app and memory system will share domain events, accessibility context, and integration tests.
- Monorepo targets keep versioning, testing, and iterative refactors cheap.
- Reuse is preserved through stable target boundaries rather than a separate repository.

## 8. Target Responsibilities

### 8.1 `MemoryDomain`

Pure types and protocols. No UI, no macOS-specific APIs, no network provider code.

Responsibilities:

- `InputEvent`
- `MemoryItem`
- `MemoryType`
- `MemoryScope`
- `RecallRequest`
- `RecallBundle`
- `MemoryStore`
- `MemoryExtractor`
- `MemoryRetriever`
- `ActionPolicy`

### 8.2 `MemoryCore`

Orchestration layer that turns captured events into memories and memories into runtime recall.

Responsibilities:

- accept `InputEvent`
- coordinate extraction
- merge or update existing memories
- apply confidence and precedence rules
- produce recall bundles for runtime consumers
- expose management APIs for UI and diagnostics

### 8.3 `MemoryExtraction`

Background extraction logic that turns observed input behavior into durable memory candidates.

Responsibilities:

- vocabulary extraction
- correction extraction
- style extraction
- scene extraction
- confidence assignment
- duplicate normalization

### 8.4 `MemoryStorageSQLite`

Local-first persistent store.

Responsibilities:

- SQLite schema
- CRUD for events and memories
- query by scope and confidence
- local text search
- deletion tombstones so deleted memories do not silently reappear

SQLite is the default storage engine because it is local, reliable, testable, and available in the current app environment.

### 8.5 `ActionRuntime`

Runtime for direct-fill behavior. It consumes current UI context and memory recall. It does not own long-term storage.

Responsibilities:

- detect target type
- select safe action policy
- request memory recall
- generate text for the target
- fill the target field
- report outcome and follow-up observation events

## 9. Memory Types

The first implementation will support exactly four memory classes.

### 9.1 Vocabulary Memory

Stable lexical knowledge:

- names
- product names
- project names
- company names
- domain terminology
- bilingual or mixed-language phrases

Primary use:

- improve transcription hints
- improve polish fidelity

### 9.2 Correction Memory

Observed rewrites from one form to another:

- recurring misrecognitions
- recurring rewrite pairs
- common abbreviation expansions
- canonical spelling preferences

Primary use:

- transcription correction
- polish correction

### 9.3 Style Memory

Stable writing preferences:

- concise versus expanded
- formal versus casual
- list-oriented versus prose-oriented
- polite phrasing patterns
- preferred reply tone

Primary use:

- polish personalization
- direct-fill generation

### 9.4 Scene Memory

Context-specific preferences tied to scope:

- per app
- per window title or page title
- per field label
- per field role

Primary use:

- recall ranking
- direct-fill specialization

## 10. Data Model

### 10.1 `InputEvent`

`InputEvent` records a single input episode.

Required fields:

```text
id
timestamp
appIdentifier
appName
windowTitle
pageTitle
fieldRole
fieldLabel
actionType
rawTranscript
polishedText
insertedText
finalUserEditedText
outcome
durationMs
source
```

Field notes:

- `actionType` is one of `transcribe`, `polish`, `commentFill`, `textFill`, or `formFill`.
- `source` identifies whether the episode started from speech, manual trigger, or direct-fill flow.
- `finalUserEditedText` may be empty only when no post-insert edit signal is available.

### 10.2 `MemoryItem`

`MemoryItem` is the durable unit used for recall and management.

Required fields:

```text
id
type
key
value
scope
confidence
status
createdAt
updatedAt
lastConfirmedAt
sourceEventIDs[]
```

Definitions:

- `type`: `vocabulary`, `correction`, `style`, `scene`
- `scope`: `global`, `app`, `window`, `field`
- `status`: `active`, `hidden`, `deleted`

### 10.3 `RecallRequest`

`RecallRequest` is the query contract for runtime use.

Required fields:

```text
timestamp
appIdentifier
windowTitle
pageTitle
fieldRole
fieldLabel
requestedCapabilities[]
```

`requestedCapabilities` is a subset of:

- `transcription`
- `polish`
- `directFill`

### 10.4 `RecallBundle`

`RecallBundle` is the runtime result.

Required fields:

```text
vocabularyHints[]
correctionHints[]
styleHints[]
sceneHints[]
diagnosticSummary
```

The bundle is intentionally small. It is not a dump of all matching memory.

## 11. Storage Model

The default storage model is SQLite with explicit tables for:

- `input_events`
- `memory_items`
- `memory_item_sources`
- `memory_deletions`

Recommended indexing:

- timestamp index for event history
- scope index for app/window/field filtering
- type plus confidence index for recall selection
- FTS-backed text lookup for management UI and debugging

The store must support:

- insert event
- insert or merge memory
- query memories by scope and type
- mark memory hidden
- mark memory deleted
- hard delete only through maintenance tooling, not normal UI

Deletion behavior:

- UI deletion writes a tombstone state
- deleted items are excluded from recall
- extractors must not recreate a deleted item from the same source pattern without new confirming evidence

## 12. Event Capture and Learning Flow

The memory system learns from events, not from free-form prompts.

```text
user speaks or triggers fill
-> system transcribes
-> system polishes
-> system inserts text
-> user edits or leaves it unchanged
-> app captures final observed outcome
-> InputEvent is recorded
-> background extraction produces MemoryItems
-> MemoryStore persists merged results
```

### 12.1 Post-Insert Observation

After insertion, the app opens a short reconciliation window to detect edits to the target field.

Phase 1 rule:

- open an observation window after text insertion
- capture final field text if accessible
- if observation is unavailable, retain the inserted text and mark final edit status as unknown

This is mandatory because final user edits are the highest-value learning signal.

### 12.2 Context Capture

Each event captures:

- frontmost app
- window title when available
- page title when available
- field role
- field label or nearest accessible label when available

This context is the basis for scene memory and scoped recall.

## 13. Extraction Rules

Extraction runs off the hot path.

### 13.1 Vocabulary Extraction

Create or strengthen vocabulary memory when:

- uncommon proper nouns repeat
- mixed-language phrases recur
- the same specialized term appears across multiple events
- a final user edit consistently introduces the same lexical token

### 13.2 Correction Extraction

Create or strengthen correction memory when:

- the inserted text or raw transcript is repeatedly edited into the same replacement
- the same normalization pattern appears across multiple events

Correction memory stores the preferred output form as the canonical value.

### 13.3 Style Extraction

Create or strengthen style memory when:

- the user repeatedly rewrites system output toward a stable tone
- the user prefers shorter or longer endings in the same scene
- direct-fill output is consistently edited toward a stable pattern

Style memory must be aggregated, not stored as raw user text chunks.

### 13.4 Scene Extraction

Create or strengthen scene memory when:

- a pattern is stable inside a specific app
- a pattern is stable inside a specific window or page
- a pattern is stable inside a field class such as comment box or title field

### 13.5 Confidence Rules

Confidence increases with:

- repetition
- confirmation by final user-edited text
- narrower scope matches

Confidence decreases with:

- one-off events
- conflicting final outcomes
- explicit user disabling

Low-confidence memory can be stored but must not drive direct-fill behavior.

## 14. Runtime Architecture

Runtime has two paths.

### 14.1 Hot Path

Purpose:

- low-latency input enhancement

Consumers:

- transcription
- polish

Behavior:

- build `RecallRequest` from current UI context
- recall only high-confidence and relevant memories
- inject vocabulary and correction memory into transcription configuration
- inject style and scene memory into polish context

Constraints:

- bounded result size
- no background extraction on the user-critical path
- safe fallback to current behavior if recall fails

### 14.2 Action Path

Purpose:

- direct field filling

Consumers:

- comment box fill
- text field fill
- simple form field fill

Behavior:

- detect current target type
- check safety policy
- build scoped recall request
- generate text using scene, style, vocabulary, and correction memory
- fill the target field
- observe follow-up edits
- learn back into memory

Constraints:

- direct fill allowed
- automatic submit forbidden
- ambiguous target detection means no action

## 15. Allowed Actions in Phase 1

Allowed:

- fill comment boxes
- fill free-form text areas
- fill simple single-page form fields

Blocked:

- click submit
- confirm payments
- approve workflows
- modify credentials
- navigate multi-step flows automatically

The system is an input agent, not a transactional agent.

## 16. Safety Policy

Action execution must pass all of the following checks:

- target is recognized as a supported field
- target is in the allowlisted action class
- confidence is above the configured threshold
- required field context is available
- generated output is non-empty and structurally valid for the target

When any check fails, the action runtime must not execute the fill.

### 16.1 Failure Behavior

- recall failure: continue with current app behavior
- extraction failure: store the event and skip memory update
- generation failure: do not fill
- ambiguous target: do not fill
- fill failure: keep generated text available for clipboard fallback

## 17. Memory Management UI

The existing memory page should evolve into a memory center.

Target sections:

```text
Memory Center
├─ Vocabulary
├─ Corrections
├─ Style
├─ Scenes
├─ Recently learned
├─ Hidden
└─ Deleted
```

Phase 1 management capabilities:

- browse memories
- search memories
- filter by app, field, and memory type
- edit values
- hide values
- delete values
- inspect source events

The system must not become a black box. User-visible memory management is a product requirement, not a debugging convenience.

## 18. Integration with Existing Targets

### 18.1 `SpeechBarApp`

- extend the existing memory page into a memory management interface
- expose toggles for learning and direct-fill modes
- show recent recalls and recent learned items

### 18.2 `SpeechBarApplication`

- integrate recall into `VoiceSessionCoordinator`
- add learning hooks after publish and after final observed edits
- route direct-fill actions through `ActionRuntime`

### 18.3 `SpeechBarInfrastructure`

- capture frontmost app and accessibility field context
- support post-insert observation
- expose diagnostics for recall and action outcomes

### 18.4 `SpeechBarDomain`

- continue to hold current user profile types
- gradually reduce dependence on manually entered `memoryProfile`
- consume `RecallBundle` as a runtime input for transcription and polish

## 19. Migration from Current Behavior

Current behavior already has:

- user profession
- manually entered memory profile
- terminology glossary
- polish mode and related settings

Migration direction:

- keep current profile fields as explicit user-owned configuration
- introduce learned memory alongside them
- let learned vocabulary and corrections complement the glossary
- avoid deleting current profile features in the first rollout

The system starts additive, not replacement-first.

## 20. External Memory Project Strategy

The product should not depend on an external GitHub memory system as its source of truth.

Recommended use of existing projects:

- `LangMem`: reference for hot-path versus background split
- `mem0`: reference for extraction and recall ranking patterns
- `ReMe`: reference for editable memory UX
- `mem9`: defer until cross-project shared memory becomes necessary
- `Supermemory`: not recommended for phase 1 due to scope and weight
- `Graphiti` and `Hindsight`: research references, not implementation dependencies for phase 1

Decision:

- self-owned memory model
- self-owned storage contract
- adapter-friendly internals
- no external memory backend in phase 1

## 21. Phased Delivery

### Phase 1: Memory Capture

- define domain models
- persist input events
- implement post-insert observation
- build background extraction
- do not affect runtime behavior yet

### Phase 2: Hot-Path Recall

- recall vocabulary and correction memory for transcription
- recall style and scene memory for polish
- add diagnostics and feature flags

### Phase 3: Memory Center

- add browse, edit, hide, and delete UI
- expose source-event inspection
- support filtering and search

### Phase 4: Direct Fill

- support comments
- support text areas
- support simple single-page forms
- forbid automatic submit

### Phase 5: Reusable Package Hardening

- stabilize public interfaces
- improve target isolation
- document embedding for other projects
- evaluate optional remote adapters only after real reuse pressure exists

## 22. Testing Strategy

Testing is required at the package level and at the app integration level.

### 22.1 Unit Tests

- extraction rules for all four memory types
- precedence order enforcement
- confidence merge logic
- deletion and tombstone behavior
- scoped recall ranking

### 22.2 Integration Tests

- event capture through insertion and post-edit observation
- recall injection into transcription and polish flows
- action runtime fill decisions in supported and unsupported contexts
- fallback behavior when context is incomplete

### 22.3 Regression Tests

- user-final-text override always wins
- deleted memories do not silently return
- unsupported actions never execute
- recall failure never blocks normal input

## 23. Observability

The system must emit diagnostics for:

- event capture success and failure
- extraction success and failure
- recall hit and miss summaries
- action execution decisions
- fallback reasons

Diagnostics are required both for developer debugging and for validating product quality during rollout.

## 24. Rollout Policy

Phase 1 and Phase 2 should ship behind internal feature flags.

Recommended rollout order:

- learn-only mode
- hot-path recall for internal users
- visible memory management UI
- direct-fill for internal users
- broader rollout after safety and quality review

## 25. Final Decision

SlashVibe will adopt a monorepo, multi-target memory architecture with a reusable embedded memory core.

The system will:

- learn from input events
- trust final user edits above all other signals
- improve transcription and polish
- directly fill supported text targets
- remain local-first and package-embedded in phase 1
- stay reusable by future projects through clear target boundaries

This is the implementation direction for the first memory system release.

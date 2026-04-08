# Personal Input Memory and Action Runtime Design

Status: proposed
Date: 2026-04-08
Repository: `/data/projects/superInput`

## 1. Summary

This document defines a memory system for the `superInput` repository's current app, `SlashVibe`, that upgrades the current speech input workflow into a personal input agent.

The system learns from real input behavior, not only from configuration. It observes what the user said, what the system transcribed, what the system inserted, and what the user finally changed the text to. It then turns those observations into reusable memories that improve transcription, polish, and direct-fill actions for comments and simple forms.

The memory system will live in the current repository as a set of independent Swift Package targets. It must serve the current app first while being structured for future extraction and reuse by later projects.

The first release train is package-embedded and local-first. It is not a separate memory server.

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
- Provide explicit privacy controls, sensitive-field exclusion, and bounded retention.
- Define measurable quality metrics for recall and post-edit reduction.
- Keep the implementation structured for future reuse by other projects inside the same monorepo.

## 4. Non-Goals

- General long-horizon agent memory for arbitrary conversations.
- Automatic submission of forms, comments, or any irreversible action.
- Payment flows, security settings, account management, or multi-step workflows.
- Cross-device sync in the first release train.
- A dedicated memory service process in the first release train.

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

When `finalUserEditedText` is unavailable, `insertedText` is only provisional truth. It must not be treated as equivalent to an observed final outcome. When observation is available and the user makes no change, `finalUserEditedText == insertedText` counts as positive confirmation.

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
- generic multi-page browser automation
- remote sync
- remote memory backend
- generalized planner-style agents

### 6.1 Privacy and Sensitive-Field Boundary

The system must fail closed around sensitive input.

Sensitive or excluded fields include:

- secure text entry fields exposed by accessibility
- password, passkey, one-time-code, or payment fields when metadata is available
- known credential, wallet, banking, and security-management apps
- user-configured app, window, or field opt-outs

Rules:

- sensitive or opted-out fields must never persist raw text, polished text, inserted text, or final observed text
- sensitive or opted-out fields are not valid direct-fill targets
- allowed fields still pass through a redaction step before persistence for high-risk secrets such as API keys, access tokens, credit-card-like strings, passwords, and one-time codes
- persisted event text is encrypted at rest using a local master key stored in Keychain
- every app and field can be opted out independently for capture and for direct fill

### 6.2 Supported Target Scope

The memory program covers all current transcription and polish flows, but the first fill stage is narrower.

- capture and recall may run for any supported transcription target that passes the privacy gate
- direct fill in the first fill stage only supports native macOS text controls with reliable accessibility semantics
- browser, Electron, and arbitrary web comment boxes require a companion DOM adapter or browser extension and are outside the first fill stage

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
- Reuse is a structural goal, not a guarantee of current cross-project stability. Public hardening is deferred to the final delivery stage.

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
- local metadata and memory search
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
languageCode
localeIdentifier
appIdentifier
appName
windowTitle
pageTitle
fieldRole
fieldLabel
sensitivityClass
observationStatus
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
- `sensitivityClass` is one of `normal`, `redacted`, `secureExcluded`, or `optOut`.
- `observationStatus` is one of `observedFinal`, `observedNoChange`, `unavailable`, or `blockedSensitive`.
- `finalUserEditedText` may be empty only when `observationStatus` is `unavailable` or `blockedSensitive`.
- if `observationStatus` is `observedNoChange`, `finalUserEditedText` must equal `insertedText` and counts as positive confirmation
- if `sensitivityClass` is `secureExcluded` or `optOut`, all text-bearing fields must be empty before persistence

### 10.2 `MemoryItem`

`MemoryItem` is the durable unit used for recall and management.

Required fields:

```text
id
type
key
valuePayload
valueFingerprint
identityHash
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
- `valuePayload` is typed structured data, not an untyped free-form string
- `identityHash` is computed from `type + normalizedScope + normalizedKey + valueFingerprint`

Concrete examples:

- vocabulary: `key = "term:openai api"`, `valuePayload = {"canonical":"OpenAI API","aliases":["open ai api"]}`
- correction: `key = "corr:扣子空间"`, `valuePayload = {"canonical":"Coze Space"}`
- style: `key = "style:mail.reply.default"`, `valuePayload = {"tone":"polite","brevity":"short","structure":"paragraph"}`
- scene: `key = "scene:com.apple.mail:reply-body"`, `valuePayload = {"intent":"reply","preferredStyleKey":"style:mail.reply.default"}`

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
- metadata and memory-item search indexes for management UI and debugging

Storage rules:

- all text-bearing columns in `input_events` are encrypted at rest
- encryption keys are not stored in SQLite; they are derived from a local master key held in Keychain
- secure or opted-out events store metadata only, or are skipped entirely when even metadata capture is disallowed
- raw event text is not FTS-indexed

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
- extractors must not recreate a deleted item with the same `identityHash` until either the user restores it or at least three new distinct confirming events are observed after the deletion timestamp

Retention rules:

- text-bearing `input_events` are retained for 30 days or 10,000 events, whichever limit is reached first
- older text-bearing events are compacted to metadata-only summaries or purged
- `memory_items` persist until hidden, deleted, or explicitly aged out by future policy
- deletion tombstones are retained for 180 days by default

## 12. Event Capture and Learning Flow

The memory system learns from events, not from free-form prompts.

```text
user speaks or triggers fill
-> classify field sensitivity
-> redact or suppress persistence if needed
-> system transcribes
-> system polishes
-> system inserts text
-> user edits or leaves it unchanged
-> app captures final observed outcome when supported
-> InputEvent is recorded
-> background extraction produces MemoryItems
-> MemoryStore persists merged results
```

### 12.1 Pre-Persistence Privacy Gate

Every episode is classified before text is persisted.

Pipeline:

```text
detect field
-> classify sensitivity
-> apply opt-out policy
-> redact high-risk secrets if field is allowed
-> persist allowed text or metadata-only event
```

If the field is secure or opted out, the system records no text content and performs no learning from content.

### 12.2 Post-Insert Observation

After insertion, the app opens a short reconciliation window to detect edits to the target field.

Observation support is not universal.

Reliable in the first release train:

- native AppKit text fields and text views with readable accessibility value semantics
- explicitly supported native editors that expose stable focused-element value reads

Unreliable in the first release train:

- generic browser DOM fields without a companion adapter
- many Electron apps that do not expose final editable values through accessibility

Capture-stage rule:

- open an observation window after text insertion
- capture final field text only when the target class is known to support reliable reads
- if observation is unavailable, retain the inserted text only as provisional evidence and mark `observationStatus = unavailable`
- if observation is available and no user edit occurs, mark `observationStatus = observedNoChange`

Observed final user edits are the highest-value learning signal, but they are not always available. The system must degrade honestly rather than pretending observation works everywhere.

### 12.3 Context Capture

Each event captures:

- frontmost app
- window title when available
- page title when available
- field role
- field label or nearest accessible label when available

This context is the basis for scene memory and scoped recall.

## 13. Extraction Rules

Extraction runs off the hot path.

Scheduling model:

- each persisted event is enqueued on a serial background extraction actor
- extraction flushes when either 10 events are buffered, 5 seconds have elapsed, or the app becomes idle/backgrounded
- tests must be able to force a synchronous flush for deterministic verification

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

`confidence` is a normalized floating-point score in the range `0.0 ... 1.0`.

Scoring rules:

- base score from one unconfirmed event: `0.35`
- add `0.20` when confirmed by `observedFinal` or `observedNoChange`
- add `0.10` for each additional distinct confirming event, up to `+0.30`
- add `0.10` when the same value is stable at exact field scope
- subtract `0.25` for each conflicting observed final outcome
- clamp the final score into `0.0 ... 1.0`

Thresholds:

- show in UI: `>= 0.20`
- usable in hot-path recall: `>= 0.60`
- usable in direct-fill generation: `>= 0.80`

Special case:

- a memory derived only from `insertedText` when `observationStatus = unavailable` is provisional and may not exceed `0.55` until later observed confirmation exists

### 13.6 Scope and Conflict Resolution

Recall precedence is explicit:

```text
field scope
> window scope
> app scope
> global scope
```

Tie-break rules for conflicting memories with the same normalized key:

- more specific scope wins first
- then higher confidence
- then later `lastConfirmedAt`
- if conflicting values still tie after these rules, suppress recall for that key and emit a diagnostic event

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

### 14.2 Target Detection Strategy

The action runtime does not assume that all editable fields are equally detectable.

Native macOS path:

- identify the focused accessibility element
- verify it is editable and not secure
- read role, subrole, label, placeholder, and window context
- classify the target as comment box, free-form text area, or simple form field only when role and context agree

Ambiguous target conditions:

- no focused editable element
- multiple candidate editable elements with equal certainty
- unsupported role or missing editability signal
- missing label for a structured form field

Web and Electron path:

- generic accessibility-only classification is not a supported contract for the first fill stage
- browser, Electron, and arbitrary web forms require a companion DOM adapter or browser extension, or an explicit app-specific adapter
- without a supported adapter, `ActionRuntime` must return `unsupportedTarget`

### 14.3 Action Path

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

## 15. Allowed Actions in the Fill Stage

Allowed:

- fill native macOS comment boxes with reliable accessibility detection
- fill native macOS free-form text areas
- fill native macOS simple single-page form fields with recoverable labels or roles

Deferred:

- browser comment boxes without a DOM companion
- Electron fields without a supported adapter
- arbitrary web forms without a supported adapter

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
- target is not classified as sensitive or opted out
- target is in the allowlisted action class
- confidence is above the configured threshold
- required field context is available
- generated output is non-empty and structurally valid for the target
- no unresolved recall conflict exists for the same normalized key

When any check fails, the action runtime must not execute the fill.

### 16.1 Failure Behavior

- recall failure: continue with current app behavior
- extraction failure: store the event and skip memory update
- generation failure: do not fill
- ambiguous target: do not fill
- fill failure: offer clipboard fallback only when the user has enabled clipboard fallback or the current publish mode already uses clipboard delivery; otherwise keep the draft only in app-local UI state

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

Center-stage capabilities:

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
- implement secure-field detection, privacy gating, and at-rest text encryption support

### 18.4 `SpeechBarDomain`

- continue to hold current user profile types
- gradually reduce dependence on manually entered `memoryProfile`
- define only app-domain types that remain independent of memory runtime plumbing

`RecallBundle` belongs to `MemoryDomain` and is consumed by `SpeechBarApplication`, not by `SpeechBarDomain`.

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
- `mem9-ai/mem9`: defer until cross-project shared memory becomes necessary
- `Supermemory`: not recommended for the first release train due to scope and weight
- `Graphiti` and `Hindsight`: research references, not implementation dependencies for the first release train

Decision:

- self-owned memory model
- self-owned storage contract
- adapter-friendly internals
- no external memory backend in the first release train

## 21. Delivery Stages

### Stage A: Capture

- define domain models
- persist input events
- implement post-insert observation
- build background extraction
- do not affect runtime behavior yet

### Stage B: Recall

- recall vocabulary and correction memory for transcription
- recall style and scene memory for polish
- add diagnostics and feature flags

### Stage C: Memory Center

- add browse, edit, hide, and delete UI
- expose source-event inspection
- support filtering and search

### Stage D: Direct Fill

- support native macOS comments
- support native macOS text areas
- support native macOS simple single-page forms
- forbid automatic submit
- defer browser and Electron fill until a supported adapter exists

### Stage E: Package Hardening

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

- observed final user text override always wins when available
- deleted memories do not silently return
- unsupported actions never execute
- recall failure never blocks normal input

### 22.4 Success Metrics

The rollout must track product quality with explicit metrics.

Metric interpretation rules:

- compare Stage B and Stage D behavior against a learn-only or recall-off baseline cohort
- only use events with `observationStatus = observedFinal` or `observedNoChange` for post-edit quality metrics
- treat privacy-suppressed events as excluded from quality scoring but included in privacy reporting

- post-insert manual edit rate for transcription output
- acceptance rate of polished output when observation is available
- direct-fill edit-after-fill rate
- hot-path recall hit rate by memory type
- percentage of events suppressed by privacy gating

## 23. Observability

The system must emit diagnostics for:

- event capture success and failure
- privacy gate allow, redact, suppress, and opt-out decisions
- extraction success and failure
- recall hit and miss summaries
- action execution decisions
- unsupported target reasons
- fallback reasons

Diagnostics are required both for developer debugging and for validating product quality during rollout.

## 24. Rollout Policy

Stage A and Stage B should ship behind internal feature flags.

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
- enforce privacy gating, redaction, encryption, and retention from the start
- remain local-first and package-embedded in the first release train
- stay structured for future reuse through clear target boundaries

This is the implementation direction for the first memory system release.

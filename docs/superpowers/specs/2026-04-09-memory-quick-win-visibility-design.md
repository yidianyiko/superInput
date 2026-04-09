# Memory Quick-Win Visibility Design

Status: approved
Date: 2026-04-09
Repository: `/Users/oliver/Downloads/redheak_source_20260407_220321`

## Summary

This design defines a narrow set of changes that make the current memory system feel obviously alive during normal use without changing its fundamental architecture.

The user already approved implementing the previously recommended quick-win actions as the next step.

## Scope

The implementation should do five things:

1. Turn memory recall on by default.
2. Show visible post-capture growth after a completed transcript reloads the constellation.
3. Make newly added memories look visually fresh in the constellation.
4. Surface active memory hints in a more prominent recording-time surface.
5. Add minimum viable hide and delete controls for a selected memory.

## Non-Goals

- No new memory types.
- No schema redesign.
- No direct-fill runtime work.
- No search or full source-event inspection UI.
- No tombstone redesign or package-hardening work in this pass.

## Design Decisions

### Recall Default

`MemoryFeatureFlagStore` should default `recallEnabled` to `true`.

This makes existing recall behavior immediately visible in transcription keywords, polish context, and on-screen hint surfaces.

### Post-Capture Growth Feedback

`MemoryConstellationStore` should detect added memory identities only when the reload follows a completed transcript pulse.

When new identities appear, the constellation should expose:

- a short-lived "本次新增 N 条" style status signal
- a per-star "recently added" marker so the user can find what changed

Initial load must not treat all existing memories as newly captured.

### More Prominent Hints

`RecordingOverlayView` should show up to two active memory hints during recording when they exist.

The overlay should grow to fit the hint chips instead of truncating them into the existing compact pill.

### Minimum Viable Management

The selected memory detail panel should expose:

- `隐藏`
- `删除`

These actions should update local memory status, reload the constellation, and clear selection when the chosen item is no longer visible.

This pass is intentionally browse/manage oriented. It does not add editing or source-event drill-down.

## Testing

Add or update tests for:

- recall default behavior
- post-capture added-memory signaling
- recent-star marking
- overlay expansion when memory hints exist
- hide/delete management flows

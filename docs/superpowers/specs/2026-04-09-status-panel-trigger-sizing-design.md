# Status Panel Trigger Sizing Design

Status: approved
Date: 2026-04-09
Repository: `/Users/oliver/Downloads/redheak_source_20260407_220321`

## 1. Summary

This document defines the approved design for the menu bar status panel adjustment requested in review.

The approved direction is intentionally narrow:

- keep the current `StatusPanelView` layout and information architecture
- keep the current trigger button copy, gradients, and interaction behavior
- reduce the visual weight of the `开始一次语音输入` trigger card
- do that only by shrinking the trigger card height and tightening its internal padding/spacing

The user explicitly does not want a broader status-panel redesign at this stage.

## 2. Product Intent

The menu bar popover should remain quick to scan.

Right now the trigger card reads closer to a hero banner than a compact primary action. The goal is to make it feel like the main control inside the panel, not the entire panel itself.

## 3. Design Goals

- Make the trigger button visibly smaller in the popover.
- Preserve the existing visual language so the change feels like a polish pass, not a redesign.
- Avoid introducing layout churn in neighboring cards.
- Reduce the sense of crowding caused by the current oversized primary action.

## 4. Non-Goals

- Reworking the popover structure.
- Changing the surrounding cards, sections, or copy.
- Redesigning the status item icon or popover chrome.
- Revisiting border treatments in this task.
- Changing recording logic or button behavior.

## 5. Approved Direction

Three approaches were considered:

1. Height only: reduce the trigger card height and leave internal spacing untouched.
2. Height plus internal padding: reduce the card height and tighten the internal vertical rhythm.
3. Height plus typography/icon scaling: reduce the card and also shrink content sizes.

The approved approach is `Height plus internal padding`.

This gives a clear reduction in visual weight without turning the task into a broader redesign.

## 6. UI Change Specification

The target is the trigger card in [`Sources/SpeechBarApp/StatusPanelView.swift`](/Users/oliver/Downloads/redheak_source_20260407_220321/Sources/SpeechBarApp/StatusPanelView.swift).

Required changes:

- reduce the trigger card height from `106` to roughly `72`
- reduce the trigger card’s vertical padding so the top status row and title block sit closer together
- tighten the internal spacing enough that the existing content fits comfortably at the smaller height

Required non-changes:

- keep the existing `recordButtonTitle` and `recordButtonSubtitle`
- keep the current gradient treatment for idle and active states
- keep the current icon, text styling, and interaction states unless a minimal spacing fix is required to prevent overlap
- keep the rest of the status panel layout unchanged

## 7. Layout Rules

- The trigger card should still read as the primary action in the panel.
- The card should no longer dominate the first screenful of the popover.
- The button must remain visually balanced with the header card and the compact status cards below it.
- The smaller layout must not create text overlap, clipped content, or unstable alignment across idle, recording, and finalizing states.

## 8. Error Handling and Edge Cases

- If the missing-credential subtitle wraps more aggressively at the smaller size, spacing may be tightened further, but the implementation should not broaden into copy changes.
- If the finalizing state is visually cramped, the fix should stay inside the trigger card’s local spacing and frame constraints.
- If a minimal font or icon reduction becomes strictly necessary to prevent overlap, it should be treated as a containment fix, not as a restyling pass.

## 9. Testing and Verification

Required automated coverage:

- add or update a view-oriented test that locks in the smaller trigger height or render behavior in `StatusPanelView`
- ensure existing theme and status-panel tests continue to pass

Required command-line verification:

- `swift test`

Manual verification should confirm:

- the trigger button is obviously smaller than before
- the button still reads clearly as the primary action
- no overlap or clipping appears in idle, recording, missing-credential, or finalizing states

## 10. Risks and Controls

### 10.1 Cramped Content Risk

Reducing height can force the subtitle and status row into each other.

Control:

- tighten only the local internal spacing
- keep the change scoped to the trigger card

### 10.2 Scope Drift Risk

The status panel has other review issues, especially border treatment, which can tempt broader edits.

Control:

- treat those observations as deferred
- keep this implementation limited to trigger sizing only

## 11. Implementation Outcome

When implementation is complete:

- the menu bar popover looks cleaner at first glance
- the main recording control remains prominent
- the button no longer feels oversized relative to the rest of the panel

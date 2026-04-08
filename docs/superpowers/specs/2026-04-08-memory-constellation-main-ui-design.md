# Memory Constellation Main UI Design

Status: proposed
Date: 2026-04-08
Repository: `/Users/oliver/Downloads/redheak_source_20260407_220321`

## 1. Summary

This document defines the main interface for the Memory Constellation experience in `superInput`.

The screen is a relationship-first memory view. Its job is not to expose every stored memory, nor to behave like a graph editor. Its job is to help the user quickly understand the major themes in their memory, and then notice the small number of cross-theme relationships that matter right now.

The approved direction is `Cluster Map`.

## 2. Product Intent

When the user opens Memory Constellation, they should feel like they are looking at a private sky made from their own input behavior.

The first impression should be:

- stable theme clusters already exist
- some relationships across those clusters are now becoming meaningful
- the system is calm and readable before it becomes detailed

The screen should reward inspection, not demand decoding.

## 3. Design Goals

- Show major memory themes before individual memory points.
- Reveal relationships progressively instead of rendering a dense edge network by default.
- Keep the interface emotionally quiet and personal rather than analytical or dashboard-like.
- Make cross-cluster bridge stories visible enough to feel useful, but restrained enough to preserve clarity.
- Support future expansion into detail drawers, timeline replay, and memory management without changing the main reading model.

## 4. Non-Goals

- Showing every relationship on first load.
- Making the primary screen double as a full memory CRUD surface.
- Turning the experience into a classic node-link analysis tool.
- Prioritizing metrics, counters, and filters over spatial understanding.
- Designing the full memory detail page in this document.

## 5. Core Interaction Principle

The user should read the sky in this order:

```text
cluster mass
> today's bridge
> cluster labels
> specific stars
> detailed relationship stories
```

This ordering is the main interaction rule for the screen.

If a design choice makes individual nodes or controls louder than cluster mass and current bridge signals, that choice is incorrect.

## 6. Main Screen Structure

The main screen has five layers.

### 6.1 Header

The header establishes identity and quiet context.

It contains:

- screen title, for example `My Universe`
- short explanatory copy
- compact status pills such as retention window and memory totals
- a memory status control, such as `Memory On`

The header must not look like an analytics console. Counts are supporting metadata only.

### 6.2 Filter Toolbar

The toolbar sits below the header and exposes lightweight view controls.

Initial controls:

- cluster filter chips: `All`, `Vocabulary`, `Style`, `Scenes`
- view mode chips: `Cluster Map`, `Bridge Stories`, `Timeline Replay`

The toolbar is present but visually subordinate to the canvas.

### 6.3 Constellation Canvas

The canvas is the main surface.

It shows:

- 3 to 5 major cluster fields
- bright stars for stable memories
- soft field stars for contextual memory density
- restrained intra-cluster connection lines
- 1 to 2 highlighted gold bridge lines across clusters
- soft cluster labels and counts

The default view is spatial and atmospheric, not exhaustive.

### 6.4 Floating Guidance Layer

The canvas can contain small floating guidance panels.

Initial panels:

- `Today's Bridge`: explains the strongest current cross-cluster relationship
- `Reading Cue`: explains the first recommended interaction, such as hovering a cluster

These panels are instructional overlays, not persistent management widgets.

### 6.5 Relationship Tray

Below the canvas is a tray of 2 to 4 relationship story cards.

The tray answers:

- what bridge is strongest now
- what bridge is rising
- what bridge is subtle but forming

The tray translates spatial relationships into readable language without forcing the user to decode the graph on their own.

## 7. Default Overview State

The default opening state is the most important state in the design.

### 7.1 What Must Be Visible

- clear cluster masses
- one primary gold bridge
- one optional secondary bridge
- cluster labels
- bottom relationship tray
- timeline ribbon in a passive state

### 7.2 What Must Stay Hidden or Soft

- dense cross-cluster edge networks
- edit and delete affordances
- memory detail drawer
- full relationship provenance
- aggressive hover chrome

### 7.3 Reading Outcome

Within a few seconds, the user should be able to say:

- what the main memory regions are
- which relationship matters most today
- which part of the screen to inspect next

If the user instead asks "what am I looking at?" then the default state is too abstract.

## 8. Interaction Model

The design uses progressive disclosure.

### 8.1 Hover Cluster

Hovering a cluster is the first interaction, not clicking a single star.

On cluster hover:

- that cluster's internal lines brighten
- stars inside the cluster sharpen in opacity
- related clusters respond subtly
- the relationship tray updates to stories relevant to that cluster

Cross-cluster bridge lines remain limited. The screen should still feel calm.

### 8.2 Focus Bridge

Selecting a highlighted bridge moves the screen from overview into relationship focus.

On bridge focus:

- the selected bridge becomes the strongest visual element
- related nodes stay visible
- unrelated clusters dim slightly
- the relationship tray rewrites around that bridge story

This is the point where provenance, recent activation, and related scenes can appear in supporting UI.

### 8.3 Focus Star

Direct star focus exists, but it is a secondary interaction path.

Star focus may:

- open a detail drawer
- show the star's strongest cluster and bridge associations
- show recency and confidence metadata

Star focus must not replace the cluster-first reading model.

### 8.4 Timeline Replay

Timeline replay is a mode switch, not the default state.

In replay mode:

- clusters can expand or contract as the time window changes
- new bridges can appear gradually
- the current window is reflected in the timeline ribbon

Timeline replay should feel like replaying formation, not scrubbing a chart.

## 9. Visual Language

### 9.1 Mood

The screen should feel:

- nocturnal
- private
- precise
- restrained

It should not feel:

- playful
- loud
- corporate
- data-heavy

### 9.2 Color Roles

- near-black background for depth
- blue field for vocabulary cluster regions
- rose field for style cluster regions
- green field for scene cluster regions
- gold for active bridge and current activation
- warm off-white for readable stars and text

Gold is reserved for meaning, not decoration.

### 9.3 Typography

- light to regular weight typography
- small uppercase labels for system framing
- restrained hierarchy with generous spacing

Type should support the sky, not compete with it.

## 10. Motion

Motion should confirm relationships, not entertain.

Animation rules:

- cluster hover: opacity and glow changes only
- bridge focus: soft brightening and isolation
- replay: gradual appearance, not snapping
- tray updates: fade and translate subtly

Avoid:

- bouncing
- overscaled zooms
- continuous ambient movement

Reduced-motion mode should replace animated transitions with simple opacity swaps.

## 11. Privacy and Safety States

Privacy must still be first-class even though it is not the center of this screen.

The main screen must support a privacy-safe presentation mode:

- dense labels hidden or minimized
- sensitive or live-only items shown as ghost stars or not shown at all
- bridges involving protected content suppressed
- summary text rewritten to avoid exposing raw private terms

The screen must fail closed when memory visibility is disabled.

## 12. Edge Cases

### 12.1 Sparse Memory

When the user has little data:

- show fewer clusters
- increase spacing
- use instructional copy to explain that patterns will emerge over time

Do not fake density.

### 12.2 No Strong Bridge Today

When no bridge is especially meaningful:

- remove the gold bridge emphasis
- replace `Today's Bridge` with a quieter message, such as emerging themes or recent cluster activity

### 12.3 One Dominant Cluster

If one cluster strongly outweighs the others:

- preserve the cluster-first model
- do not force false balance
- keep smaller clusters visible as satellites if they are real

## 13. Accessibility

This is a macOS-first desktop design.

Requirements:

- keyboard navigation for toolbar chips, bridge cards, and focus targets
- visible focus states that preserve the visual language
- contrast sufficient for labels, cards, and interactive controls
- non-color cues for focused and selected elements
- reduced-motion support
- semantic equivalents for relationship tray content so the graph is not the only way to understand the screen

## 14. Implementation Shape

The main screen should be implemented as a set of separable UI pieces rather than one monolithic view.

Recommended pieces:

- screen shell
- header and status pills
- filter toolbar
- constellation canvas renderer
- floating guidance overlays
- relationship tray
- timeline ribbon
- optional detail drawer

The canvas renderer should receive derived display data, not own memory retrieval logic directly.

## 15. Validation and Testing

The first implementation should be evaluated with both visual QA and behavior checks.

Visual and interaction checks:

- default state reads cluster mass before node detail
- hover cluster increases understanding without creating clutter
- focus bridge makes one relationship story obvious
- relationship tray matches canvas emphasis
- timeline replay preserves atmosphere and clarity
- privacy mode removes sensitive exposure

Engineering tests should cover:

- view-state transitions between overview, cluster hover, bridge focus, and replay
- correct mapping from memory domain data into cluster, star, and bridge presentation models
- suppression rules for privacy-safe display
- empty, sparse, and dense memory datasets

## 16. Deferred Design Work

This document intentionally leaves the following for later specs:

- memory detail drawer design
- memory edit and delete flows
- full privacy management screen
- bridge provenance deep dive
- no-memory onboarding state beyond basic rules in this document

## 17. Approved Outcome

The approved direction is:

- `Cluster Map` as the main interface model
- relationship-first reading rather than management-first reading
- clusters visible by default
- bridge stories visible in restrained form
- detailed relationships revealed through hover, focus, and replay

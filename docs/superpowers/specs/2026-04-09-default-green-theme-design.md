# Default Green Theme Design

Status: approved
Date: 2026-04-09
Repository: `/Users/oliver/Downloads/redheak_source_20260407_220321`

## 1. Summary

This document defines the approved design for adding a new default theme to the app.

The approved direction is:

- keep the existing multi-theme system
- add a new default green theme preset
- use `#00F7A2` as the primary brand accent
- use `#000000` as the base background
- use `#FFFFFF` and `#00F7A2` as the primary text and emphasis colors
- apply the same visual language to the home window, status panel, and Memory Constellation

The user approved the `layered dark green` treatment rather than a flat pure-black treatment.

## 2. Product Intent

The app should feel more distinct and more branded without removing the existing theme picker.

When the user opens the app, the interface should read as:

- black at the base
- bright green for the main action and emphasis
- white for primary reading
- deep green surfaces for hierarchy and depth

The result should feel cohesive across both the main productivity UI and the Memory Constellation UI, instead of looking like two separate products.

## 3. Design Goals

- Introduce a new default theme that matches the requested palette exactly at the brand level.
- Keep theme switching available in Settings.
- Unify theme tokens across `HomeWindowView`, `StatusPanelView`, and `MemoryConstellation`.
- Replace existing hardcoded decorative colors that currently bypass the app theme.
- Preserve semantic state colors for success, warning, and error feedback.
- Migrate only the default-theme behavior, not every historical theme into a full redesign.

## 4. Non-Goals

- Removing the existing theme picker.
- Rebuilding every existing preset around the new palette.
- Replacing semantic error, warning, or success colors with the brand green.
- Reworking layout, copy, or interaction flows unrelated to color and theme styling.
- Turning this task into a full design-system rewrite.

## 5. Approved Direction

Three approaches were considered:

1. Minimal split implementation: update the home/status theme separately from Memory Constellation.
2. Unified theme tokens: add a new default theme preset and drive both UI families from shared color roles.
3. Full theme-system expansion: move all decorative and semantic colors into a comprehensive global token system.

The approved approach is `Unified theme tokens`.

This gives the app one coherent default theme without expanding the task into a large refactor.

## 6. Theme Model

The implementation should define one shared theme role set for the default green preset.

The shared roles are:

- `brandPrimary`: `#00F7A2`
- `baseBackground`: `#000000`
- `textPrimary`: `#FFFFFF`
- `textAccent`: `#00F7A2`
- `textSecondary`: reduced-opacity white derived from `#FFFFFF`
- `surfaceBase`: near-black green surfaces derived from `#000000` and `#00F7A2`
- `surfaceElevated`: slightly brighter deep-green surfaces for hero cards and active states
- `surfaceStroke`: low-contrast green or white border for separation
- `surfaceGlow`: subtle green glow for branded emphasis

These roles should feed both the existing `HomeThemePalette` and the Memory Constellation-specific color helpers.

## 7. Visual Rules

### 7.1 Base Surfaces

- The outer canvas background is black.
- Cards and grouped surfaces use very dark green layering, not flat gray.
- Borders stay restrained and should never compete with content.
- The UI should feel deep and clean, not neon-saturated everywhere.

### 7.2 Text

- Primary reading text is white.
- Branded emphasis text uses the theme green.
- Secondary copy is white with reduced opacity.
- Text contrast must remain readable on all layered surfaces.

### 7.3 Emphasis

- Main actions, selection states, active pills, and primary highlights use the brand green.
- Decorative glow should stay subtle and only reinforce focus or hierarchy.
- Red remains reserved for destructive or active-recording warning states.

### 7.4 Memory Constellation

- Memory Constellation adopts the same black and deep-green surface system.
- The default atmospheric look should stay calm and dark, but gold/blue/rose decorative accents should be removed from its core theme.
- Cluster and focus emphasis should derive from the shared green palette, with intensity changes instead of unrelated hue changes.
- The constellation should still remain readable as a relationship map, so brightness, opacity, and glow can vary by state even when hue families are shared.

## 8. Scope of Code Changes

### 8.1 Home Theme Presets

`HomeWindowStore.ThemePreset` remains the source of selectable presets.

Changes:

- add a new green preset
- make it the default preset for fresh users
- update the theme migration version so old installs that never explicitly chose a theme move to the new default
- preserve user-selected non-default themes

### 8.2 Shared Visual System

`SlashVibeVisualSystem` should stop assuming a light glass treatment for the default path.

Changes:

- canvas background uses black plus subtle green depth
- card backgrounds become dark layered surfaces
- hero surfaces adopt dark elevated panels
- secondary buttons use dark surfaces and white/green text instead of white cards

### 8.3 Home Window and Status Panel

`HomeWindowView` and `StatusPanelView` should continue reading from the selected theme palette, but the new default preset must cover current hardcoded decorative colors that break consistency.

Examples of colors to absorb into theme roles:

- black title text currently tuned for light surfaces
- white translucent button fills intended for glass cards
- non-semantic decorative gradients for inactive UI sections

### 8.4 Memory Constellation

`MemoryConstellationTheme` currently behaves like a separate product theme.

Changes:

- derive its background, panel fill, text, chips, and focus states from the same approved green theme roles
- preserve state meaning through opacity, stroke weight, and glow instead of unrelated hue palettes
- keep the existing component structure; only the visual language changes

## 9. Migration Strategy

The theme migration should be explicit and versioned.

Rules:

- if the stored theme-style version is older than the new migration version, and the stored theme is missing or still set to the previous default preset, the app should move selection to the new green preset
- if the stored theme-style version is older than the new migration version, but the stored theme is a non-default preset, that selection remains intact
- the migration should update the stored theme version so the switch only happens once

This keeps the new theme truly default without overwriting deliberate user choices.

## 10. Testing and Verification

The implementation must include behavior-focused verification for theme defaulting and theme mapping.

Required automated coverage:

- `HomeWindowStore` default-theme loading and migration behavior
- theme persistence when a user explicitly selects another preset
- Memory Constellation color-role mapping or rendering smoke coverage for the new shared theme path

Required command-line verification:

- `swift test`

Manual visual verification should confirm:

- home window uses black background, deep-green surfaces, white text, and green emphasis
- status panel matches the same language
- Memory Constellation no longer shows the old blue/gold/rose system as its primary theme
- semantic error and warning states still read correctly

## 11. Risks and Controls

### 11.1 Contrast Risk

Dark surfaces plus bright green can become either too harsh or too dim.

Control:

- keep white as the dominant reading color
- use green for emphasis rather than body text
- keep surface layering visible through subtle brightness differences

### 11.2 Theme Drift Risk

If Memory Constellation keeps separate color logic, the UI will drift again.

Control:

- map its theme constants from the same approved preset roles instead of maintaining unrelated default values

### 11.3 Migration Risk

A blunt migration can overwrite a user’s chosen theme.

Control:

- gate the migration through the stored theme version and preserve explicit user selections

## 12. Implementation Outcome

When implementation is complete:

- the app still offers multiple themes
- a new green preset exists and is the default theme
- the default experience uses `#00F7A2`, `#000000`, and `#FFFFFF` as its core visual language
- home window, status panel, and Memory Constellation look like one product family
- existing semantic status colors continue to communicate system meaning clearly

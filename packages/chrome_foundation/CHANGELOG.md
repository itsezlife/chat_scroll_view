# Changelog

All notable changes to `chrome_foundation` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Changed

- Source-breaking: `ComposerStrings.pastePlainAction` (required), the
  selection menu item that pastes the clipboard's plain text. The English and
  Russian presets have it.
- Source-breaking: `describeChromeStrings(strings)` in `testing.dart` is
  `ChromeStringsSnapshot.of(strings)`.

### Added

- `PanelStrings.colorAllTitle` (source-breaking for hosts that build
  `PanelStrings`): the title of the tone-for-all picker.
- `ActionTokens.iconHover` (from `ChromePalette.iconActive`): the colour of a
  composer action's glyph while a mouse is over it.

### Changed

- The preset strings' `categoryTitle` is keyed by the reference client's
  sections (`people`, `nature`, `food`, `activity`, `travel`, `objects`,
  `symbols`) in the reference client's wording, not by Unicode group slugs.

### Fixed

- Glass on a surface less than five pixels across (one growing from nothing)
  no longer throws from its rim thickness: the bound never falls below a
  pixel.

### Changed

- `MotionRole.popupHide` lasts 200 ms (was 150 ms), the reference client's fade-out;
  `popupShow` was already 200 ms. A popup that fades out for 50 ms longer can be
  turned back for that long, which is what hovering it again does.

### Added

- `PanelStrings.copyAction`, `removeRecentAction` and `clearRecentAction`: the
  labels of the recents context menu (the last is answered by the existing
  clear-recents confirmation). Required, like every member; the English and
  Russian presets have them.
- The `selectionSlide` motion role (a selection marker moving to the next
  control, 400 ms ease-out cubic). `ChromeMotion` takes and copies it. A host
  that builds `ChromeMotion(...)` field by field must pass it.
- `PanelTokens.stripFill`: the fill of the category strip where a page pins it
  at the bottom (the text colour at alpha `0x0A` over `background`), one step
  off the grid in light and dark. Required in the `PanelTokens` constructor.
- The `stripReveal` (150 ms, ease-out quint) and `iconMorph` (350 ms, ease-out
  quint) motion roles. `ChromeMotion` takes and copies them like the other
  roles, so code that constructs a full table must now give both.

- The `loop` motion role (one turn of an indeterminate loop, 900 ms linear).
  `ChromeMotion` takes and copies it like the other roles.
- `PanelStrings.categoryTitle` (the title of a category section by id) and
  `SemanticsStrings.categoryStripLabel`, both required, with English and
  Russian presets.
- `ChromePalette` (custom, light, dark, high-contrast, `fromColorScheme`).
- Token groups `ComposerTokens`, `PanelTokens`, `ActionTokens`,
  `PlaceholderTokens`, `GlassMaterialTokens`, each with `fromPalette`,
  `copyWith` and `lerp`; `ChromeThemeData` bundles them.
- `ChromeThemeScope` (required, nestable `InheritedModel`) and
  `AnimatedChromeThemeScope`.
- `ChromeContrast` for WCAG contrast checks.
- `ChromeMotion` role table (`MotionRole`, `MotionSpec`), `ChromeMotionSpeed`
  (normal, `times(n)`, instant) and the optional, nestable `ChromeMotionScope`.
- `ScalePressable` and `OvershootCurve`, moved here from `chat_chrome`.
- `ChromeStrings` (`PanelStrings`, `ComposerStrings`, `SemanticsStrings`) and
  the required `ChromeStringsScope`; English and Russian presets in
  `testing.dart` only.
- `ChromeIconId`, `ChromeIconRegistry` (stock painters, host registration,
  fallback glyph), `ChromeIconScope`, `ChromeIcon` and `AnimatedChromeIcon`
  (morph between font glyphs, cross-fade for painted icons).

- Glass stack: `GlassSurface`, `GlassMaterial`, `GlassQuality`,
  `GlassQualityScope`, `GlassCapabilities`, `GlassSourceScope` and
  `GlassSource`, with an internal strategy chain (sampled liquid, sampled
  frost, backdrop filter, flat) and the three fragment shaders, moved here
  from `chat_chrome`. `GlassMaterialTokens.colorsOf`.

### Changed

- `AnimatedChromeThemeScope` takes its default duration and curve from the
  `themeSwitch` motion role (`duration` and `curve` are now optional) and its
  duration is scaled by the motion speed. Explicit values still apply.

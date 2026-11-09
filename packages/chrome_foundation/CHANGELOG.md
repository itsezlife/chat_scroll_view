# Changelog

All notable changes to `chrome_foundation` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Added (chrome typography)

- `ChromeTypography.of`: the base style of chrome text, the host theme's
  body face at the regular weight, not inheriting. Chrome drawn outside a
  `Material` (an overlay entry, a popup route) reads its face here instead of
  the framework's debug style. `PointerMenu` reads its face through it.

### Added (bulletins)

- `BulletinTokens`, a token group (`ChromeThemeData.bulletin`,
  `ChromeThemeScope.bulletinOf`, `ChromeThemeAspect.bulletin`): a bulletin's
  card, text, accent and countdown colours. `fromPalette` gives the
  dark card (`referenceAndroid`) on every palette but the
  high-contrast presets (`highContrast`). Code that builds a
  `ChromeThemeData` whole must now pass `bulletin`.
- `MotionRole.bulletinShow` (255 ms, ease-out quad) and
  `MotionRole.bulletinHide` (175 ms, ease-in quad). Code that builds a
  `ChromeMotion` whole must now pass both.
- `BulletinStrings`, the seventh group of `ChromeStrings` (`bulletin`,
  `ChromeStringsScope.bulletinOf`): `undoAction` and `dismissAction`. Code
  that builds a `ChromeStrings` must now pass `bulletin`; the presets and
  `ChromeStringsSnapshot` include it.

### Added (pack sheet strings)

- `PackSheetStrings`, the sixth group of `ChromeStrings` (`packSheet`,
  `ChromeStringsScope.packSheetOf`): a pack sheet's Add / Remove buttons by
  kind and count, the several-packs buttons and counts, Share and Copy Link,
  the not-found texts, and the added / removed / archived bulletins with
  Undo, in English. Existing code that builds a
  `ChromeStrings` must now pass `packSheet`; the presets and
  `ChromeStringsSnapshot` include it.

### Added (content preview strings)

- `PanelStrings` gains the content preview's menu (`sendStickerAction`,
  `sendEmojiAction`, `sendGifAction`, `sendWithoutSoundAction`,
  `addToFavouritesAction`, `removeFromFavouritesAction`, `viewPackAction`,
  `deleteFromRecentAction`, `copyEmojiAction`, `saveGifAction`,
  `deleteGifAction`) and the recent stickers' own clear confirmation
  (`clearRecentStickersTitle`, `clearRecentStickersMessage`). All required:
  a host's `PanelStrings` must add them. The presets carry English and Russian.

### Changed (glass look)

- The glass is frosted by default: `GlassQualityScope.quality` and a surface
  with no scope now mean `GlassQuality.frosted`. A host that relied on
  refraction without asking for it passes `quality: GlassQuality.fullLiquid`.
- The frosted look samples at an eighth of device resolution with a 40 dp
  blur radius and saturation x3, the tint at 0.76; the refracting look at a
  quarter with a 6 dp radius, the tint at 0.85. A flat glass paints its tint
  opaque (it was the translucent fill over unblurred content), except while
  only a moving route keeps it flat.
- `GlassMaterialColors.fill` is renamed `tint` (source-breaking) and is the
  material's surface colour: the glass sets its opacity per look, and the
  colour's own alpha multiplies it. `fromPalette` maps the panel button to
  `surface` (was `surfaceRaised`), the light shadows to the palette shadow at
  0x20 (a button 0x40), and the top panel's dark top edge to 0x20 white.
- `GlassMaterial` carries `strokeWidth` (0.5, 0.5, 0.55), `shadowBlur` and
  `shadowOffset`; the panel button's default corner radius is 18 (was 22).
- `GlassSource.captureScale` is 1/8 (was 1/4); `refractingCaptureScale` (1/4)
  is the scale a refracting glass captures at.
- A frosted surface no longer needs the glass shaders, and a failed shader
  load leaves surfaces frosted instead of on the scene filter.

### Added (favourite stickers)

- `PanelStrings.favouriteStickersTitle`, required, with English and Russian
  presets: the title of the stickers page's favourites section and the name
  of its strip tab. A host that builds `PanelStrings(...)` must pass it
  (source-breaking).

### Added (stickers page copy)

- `PanelStrings.stickersEmpty`, required, with English and Russian presets:
  the stickers page's placeholder when it has no recents and no pack. A host
  that builds `PanelStrings(...)` must pass it (source-breaking).
  `gifsEmpty` now also reads as the GIF page's placeholder when it has no clip
  to list at all.

### Added (GIF page copy)

- `PanelStrings.gifsEmpty`, `gifsFailed` and `retryAction`, required, with
  English and Russian presets: the GIF page's placeholders for a search that
  found nothing and for clips that could not be loaded, and the retry button.
  A host that builds `PanelStrings(...)` must pass them (source-breaking).

### Added (sticker pack strip label)

- `SemanticsStrings.stickerPackStripLabel`, the label of the stickers page's
  strip of packs, required, with English and Russian presets. A host that
  builds `SemanticsStrings(...)` field by field must pass it.

### Added (glass capture scale)

- `GlassSource.captureScale`: the scale, relative to the frame, at which a
  glass captures its source. A host that warms caches kept per scale (the
  engine's glyph atlas) before a glass first shows warms this scale too.

### Added (monospace face)

- `ChromeMonospace`: the system monospace family per platform and a fallback
  chain, the same mapping as `flutter_md`'s default, so code in the composer
  and in a sent message look alike. `ChromeMonospace.style` builds the style
  afresh, so a base in a host's packaged font does not turn the face into
  `packages/<package>/monospace`.

### Added (turned and scaled font glyphs)

- `ChromeIconPainter.font` takes `turn` (radians, clockwise) and `scale` (of
  the icon box). The box keeps its size. `AnimatedChromeIcon` animates both
  over the `iconMorph` role while the glyph morphs, so a tilted send still
  morphs into an upright confirm instead of cross-fading.
  The morph runs both ways: an upright glyph turning into a tilted one keeps
  its morph too, since the turned and the upright glyph share one tree shape.

### Changed (English wording in the presets)

- `ChromeStringsPresets.english`: the touch formatting page reads Code Block
  and Bulleted list, and the pointer menu's clear row reads Plain
  text. No API change.

### Changed (menu language)

- `EditMenuStrings` is now also the touch selection menu's source for Cut,
  Copy, Paste and Select all (it was the pointer menu's only): the composer no
  longer reads `MaterialLocalizations` for them. No API change. A host that put
  English there while its formatting rows were in its own language will see
  the touch menu's clipboard rows change to the `editMenu` strings; a `&`
  access mark in one is removed on the touch card (`Cu&t` reads "Cut"). The
  English preset's "Select All" now shows on the touch card where Material's
  "Select all" did.

### Added (pointer menu)

- `PointerMenu`, a popup list opened at the
  pointer: rows with a mnemonic label and a shortcut hint, greyed rows,
  separators, submenus that open on hover with a 300 ms aim hold, the
  arrow-key model, the grow-from-the-corner open animation and the linear
  fade out, a modal overlay that swallows the dismissing press, and focus kept
  as a child of a given node. With `PointerMenuEntry`, `PointerMenuItem`,
  `PointerMenuSeparator`, `PointerMenuMetrics` (every number marked verified,
  derived or unverified), `PointerMenuPlacements`, `PointerMenuReveal`,
  `PointerMenuAim`, `PointerMenuNavigation`, `PointerMenuTiming`,
  `EaseOutCirc` and the row and panel keys.
- `PointerMenuTokens` as a theme group (`ChromeThemeData.pointerMenu`,
  `ChromeThemeScope.pointerMenuOf`, `ChromeThemeAspect.pointerMenu`), derived
  from the palette, with the day and night colours as
  `referenceDay` and `referenceNight`. Source-breaking for hosts that build
  `ChromeThemeData` field by field or switch over `ChromeThemeAspect`.
- Motion roles `pointerMenuShow` (200 ms) and `pointerMenuHide` (150 ms).
- `EditMenuStrings` (`ChromeStrings.editMenu`, `ChromeStringsScope.editMenuOf`):
  the labels of the composer's pointer menu, with `&` mnemonics. Source-breaking for hosts that build
  `ChromeStrings`: the group is required; the English and Russian presets have
  it.

### Added

- `FormattingStrings` (`ChromeStrings.formatting`, `ChromeStringsScope.formattingOf`):
  the selection menu's item labels, the "More" and "Back" labels and the
  semantics labels of a bullet and a numbered list item. Source-breaking for
  hosts that build `ChromeStrings`: the group is required and has no English
  fallback; the English and Russian presets have it.
- `SelectionMenuTokens` (card, text, divider, shadow and page dim; elevation 3
  and corner radius 12 as constants) and `SpoilerTokens` (particle colour, null
  follows the text; `SpoilerParticleMotion`) as theme groups. The card is the
  palette's raised surface, the text its on-surface colour, the divider its
  separator at half opacity, the shadow black at 0.45, the page dim black at
  `0x18` on a light palette and `0x40` on a dark one. Source-breaking for
  hosts that build `ChromeThemeData` field by field or switch over
  `ChromeThemeAspect`; `ChromeThemeScope`, `AnimatedChromeThemeScope` and
  `ChromeThemeData.fromPalette` derive them like the other groups.
- Motion roles `menuEnter` (150 ms, ease out), `menuLeave` (220 ms, ease in),
  `menuPage` (300 ms on the CSS ease cubic `(0.25, 0.1, 0.25, 1)`) and
  `spoilerReveal`. Source-breaking for a host that builds `ChromeMotion(...)`
  field by field.
- `SpoilerParticleMotion`.

### Changed

- Source-breaking: the seven menu roles `menuEnter`, `menuExit`,
  `menuSizeEase`, `menuSizeAccelerate`, `menuMainFadeOut`, `menuMainFadeIn`
  and `menuOverflowFadeOut` are now three: `menuEnter` (150 ms, ease out),
  `menuLeave` (220 ms, ease in) and `menuPage` (300 ms, the CSS ease cubic).
  `ChromeMotion(...)`, `copyWith` and `MotionRole` switches change with them.
  `AccelerateDecelerateCurve`, `LogAccelerateCurve`,
  `ChromeMotion.linearOutSlowIn`, `ChromeMotion.fastOutLinearIn` and
  `SelectionMenuTiming` are removed.
- Source-breaking: `SelectionMenuTokens` drops `pressHighlight` (the menu uses
  the Material widgets' own press, hover and focus washes) and gains `shadow`
  and `pageDim`; `fromPalette` follows the palette's roles on both
  brightnesses, so the light card is the raised surface, not white.
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

- The preset strings' `categoryTitle` is keyed by the
  sections (`people`, `nature`, `food`, `activity`, `travel`, `objects`,
  `symbols`) in the preset wording, not by Unicode group slugs.

### Fixed

- Glass on a surface less than five pixels across (one growing from nothing)
  no longer throws from its rim thickness: the bound never falls below a
  pixel.

### Changed

- `MotionRole.popupHide` lasts 200 ms (was 150 ms), a fade-out;
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

# Changelog

All notable changes to `chrome_foundation` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Added

- `ChromeTapTiming.repeatGuard` (400 ms): the window in which a control
  that opens or removes something ignores a repeat tap.

### Added (press scale)

- `ChromeInk.scale` with `ChromeInkBounce` (a fixed factor, an overshoot on
  release; presets `card` 0.99 and `button` 0.98) and `ChromeInkInset` (to
  `(w - inset) / w` of the laid-out width; presets `card` and `button`). The
  scale follows the feedback's press, slop and cancel and is removed by an
  instant motion speed. Null by default: existing users are unchanged.

### Added (tooltip)

- `ChromeTooltip` and `ChromeTooltipMetrics` (`pointer`, `hint`): the
  chrome's one tooltip box, in the panel tokens' tooltip colours, with its
  own text root and an optional live region. The panel's tab hint and the
  catalogue's pointer tooltip draw it instead of their own boxes.

### Added (panel page availability, breaking)

- `PanelStrings.unavailableTab` (required): the spoken name of a type tab
  whose page is not available, from the tab's own label. In the English and
  Russian presets and the snapshot.
- `ChromeHintTiming.tabHint`: how long a hint at such a tab stays up
  (3.5 s), longer than a control's.

### Added (slow mode, breaking)

- `ComposerStrings.slowModeStarted` and `slowModeEnded` (required): what
  assistive technology announces when slow mode's countdown starts and
  ends. `ComposerStrings.slowModeCountdown` formats the wait, `m:ss` by
  default (`ComposerStrings.minutesSeconds`). In the English and Russian
  presets and the snapshot.
- `ChromeCountdownTiming`: how often a countdown redraws in a control, in a
  polled control and in a placeholder.

### Added (denied forms, breaking)

- `ComposerStrings.unavailableAction` (required): the label of an action
  the chat does not allow, from the action's own label. In the English and
  Russian presets and the snapshot.
- `ChromeIconId.lock` (a stock icon) and `ChromeHintTiming.controlHint`,
  how long a hint at a control stays up.

### Added (the selection header, breaking)

- `AttachStrings.selectedPhotos`, `selectedVideos` and `selectedMedia`
  (required plurals) for the Gallery's selection header,
  `selectionPreviewTitle` for its title over the selected-items preview,
  and `closeSheet` for the pinned bar's close button. They are in the
  English and Russian presets and the snapshot.

### Added (the capture flow, breaking)

- `AttachStrings.capturedPhotos`, `capturedVideos` and `capturedMedia`
  (required plurals) for the shots counter, and `captionAddPhoto` (required)
  for the camera viewer's add-photo button, in the English and Russian
  presets and the snapshot.
- `ChromeIconId.addPhoto`, painted by the stock registry.

### Added (capture modes, breaking)

- `AttachStrings.captureVideoMode` and `capturePhotoMode` (required): the
  capture surface's mode names, in the English and Russian presets.

### Added (capture refusals, breaking)

- `AttachStrings.captureVideoNotAllowed` and `captureMicrophoneDenied`
  (required): the notices for a hold on the capture surface where videos
  may not be sent, and for a refused microphone, with where to allow it.
  The English and Russian presets carry them.

### Fixed (glass inside its source)

- A glass inside the `GlassSource` of its own scope no longer samples it.
  Its capture held the glass, whose compositing captured again, without
  end (a stack overflow each frame, the UI frozen). `GlassSourceLink.of`
  is null there: such a glass samples a `GlassSourceScope` nested inside
  the source, or filters the scene. A sampler composited while a capture
  renders gets no capture. `GlassSource` is a `StatelessWidget` now (its
  render object is still `RenderGlassSource`).

### Fixed (glass fade)

- A glass that fades in no longer shows its bare tint first. An `Opacity`
  above a scene-filtered glass gave the filter the opacity layer's empty
  content in place of the scene until the fade ended. `GlassSurface.opacity`
  fades the backdrop (inside the filter), the tint, the edges, the shadow
  and the child with no layer over the filter; at 0 no backdrop is read.
  The surface's own fade is a private render object, not an `Opacity`, so
  a host's fade around a glass (a popup's appear) stays the one `Opacity`
  above its content.

### Added (tab bar glass and colours, breaking)

- `GlassColorRole.tabs` and `GlassMaterial.tabs`: a tab bar floating over
  content (a 28 stadium, 0.4 edges, a 8/3 shadow 0.85 down). Its colours
  are `GlassMaterialTokens.tabs` (required): the surface tint, faint dark
  edges under a 0x20 shadow in light, faint white edges under a 0x04 white
  glow in dark.
- `AttachTokens` gains the tab bar's colours (required): `tabSelected`,
  `tabSelectedLabel` (the accent), `tabUnselected` (the text colour),
  `tabIndicator` (the accent at 9 %) and `tabPressed` (the text colour at
  0x0F).

### Changed (glass materials, breaking)

- `GlassMaterial` is an immutable value (`colorRole`, `cornerRadius`,
  `strokeWidth`, `shadowBlur`, `shadowOffset`, `refracts`, `blurRadius`)
  with `copyWith`, `==` and `lerp`, not an enum. Presets by role:
  `island`, `button`, `bar`, `menu`, `panel`, `bubble`. Before / after:
  `composerIsland` → `island`, `panelButton` → `button`, `topPanel` → `bar`,
  `messageMenu` → `menu`; the geometry is unchanged.
- `GlassMaterialTokens` holds colours per `GlassColorRole` (`island`,
  `button`, `bar`, `menu`, `panel`, `bubble`; `of(role)`, `colorsOf(material)`
  by the material's role). Before / after: `.composerIsland` → `.island`,
  `.panelButton` → `.button`, `.topPanel` → `.bar`, `.messageMenu` → `.menu`;
  `panel` defaults to the island's colours, `bubble` to the bar's.
- `GlassSurface` takes `colors` (a surface's own `GlassMaterialColors`) and
  `borderRadius` (corners of its own for the clip and shadow; the effect
  keeps `cornerRadius`).

### Added

- `MotionRole.counterShow` (100 ms) and `MotionRole.digitRoll` (150 ms).

### Added (text root)

- `ChromeTextRoot`: the chrome face as the inherited text style, for the
  root of every route, overlay and popup (and above a host's navigator);
  `ChromeSheetRoot` builds on it.
- `expectChromeText` in `testing.dart`: fails on text in the fallback style
  (underlined, monospace).

### Added (bottom sheet)

- `ChromeSheetRoute`: the chrome's modal bottom sheet, the touch counterpart
  of `ChromeBoxLayer`. It opens by `ChromeSheetOpening.slide` (the route
  slides it) or `ChromeSheetOpening.byContent` (the content runs its own
  motion), takes no focus, and with a `ChromeSheetDragSpec` closes on a pull
  (`ChromeSheetDrag`, `ChromeSheetPull`, `ChromeSheetRelease`).
- `ChromeSheetRoot`: the chrome text style (no inherited debug style under a
  popup route) and room for the keyboard, for any sheet or box page.

### Added (attach sheet group)

- `AttachTokens` (scrim, sheet background, grabber, pinned header), derived from the palette and carried by `ChromeThemeData.attach`, `ChromeThemeScope(attach:)`, `ChromeThemeScope.attachOf` and `AnimatedChromeThemeScope`.
- `AttachStrings` (the two discard questions and their actions, the stock Gallery and Files tab labels, the spoken name of a missing-permission badge, the caption placeholder, the send and overflow menu entries, the send and more buttons' spoken labels) as `ChromeStrings.attach` and `ChromeStringsScope.attachOf`, with English and Russian presets.

### Breaking

- `ChromeStrings` takes a required `attach` group, and `ChromeThemeData` a required `attach` group in its unnamed constructor. A host that builds `ChromeStrings` itself adds an `AttachStrings`; `ChromeThemeData.fromPalette` derives the tokens on its own.

### Added (backdrop snapshot)

- `BackdropSnapshotSource`, `BackdropSnapshot` and `BackdropSnapshotView`: a small still of what the source last painted, captured once at a fraction of its device pixels (`downscale`), then laid over an opaque `background`, stack-blurred (`blurRadius`) and toned (`tone`, `BackdropSnapshot.toneMatrix`) once on the CPU, off the UI isolate where there is one, and drawn stretched (bilinear) with only its opacity animated. For a scrim over a background that holds still while it is up, in place of a live full-window `BackdropFilter`. The still is made a few frames after the capture: the snapshot is a `Listenable` whose `image` is null until then (`ready` completes then too), and the view draws nothing until then. The still is opaque, smooth and blurred evenly out to its edges on every backend: the edges repeat the capture's own edge pixels. The caller disposes the snapshot; one disposed before its still is made lets the still go as it comes.

### Added (chrome buttons)

- `ChromeIconButton`, `ChromePillButton`, `ChromeBarButton` (with `ChromeBarButtonMetrics`), `ChromeBadgeButton` (with `ChromeBadgeButtonMetrics`), `ChromeSpinner`, `ChromeCrossPainter`, `ChromeDotsPainter`, and `ChromeButtonInks` (the press and hover colours of a button on the surface or on the accent). The pack sheet's buttons, spinner and glyphs, made reusable; they draw as the sheet drew them.

### Fixed (ink takes the primary button only)

- `ChromeInk` presses with the primary button only: a secondary click neither taps nor draws, and reaches the host's context handlers.

### Added (pack strings)

- `PanelStrings.removePackAction`, and `PackSheetStrings.addStickersLabel`, `addEmojiLabel`, `removeStickersLabel`, `removeEmojiLabel` (the pack box's button words beside its count badge). Required: hosts that build their own sets add them.

### Breaking

- `PointerMenuTokens.referenceDay` is `PointerMenuTokens.day`, and `PointerMenuTokens.referenceNight` is `PointerMenuTokens.night`.
- `BulletinTokens.referenceAndroid` is `BulletinTokens.android`, and `BulletinTokens.referenceDesktop` is `BulletinTokens.desktop`. The rename covers the unreleased `BulletinTokens` group too; no alias is kept.
- `AppearMotion.bloom` is `AppearMotion.burst` (`AppearMotion$Burst`), and `AppearMotion.pop` is `AppearMotion.zoom` (`AppearMotion$Zoom`): the corner popup variants are named by the motion they play, not by the surface that first used them. Same values; no alias is kept.

### Added (chrome typography)

- `ChromeTypography.of`: the base style of chrome text, the host theme's
  body face at the regular weight, not inheriting. Chrome drawn outside a
  `Material` (an overlay entry, a popup route) reads its face here instead of
  the framework's debug style. `PointerMenu` reads its face through it.

### Added (bulletins)

- `BulletinTokens`, a token group (`ChromeThemeData.bulletin`,
  `ChromeThemeScope.bulletinOf`, `ChromeThemeAspect.bulletin`): a bulletin's
  card, text, accent and countdown colours. `fromPalette` gives the
  dark card (`android`) on every palette but the
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

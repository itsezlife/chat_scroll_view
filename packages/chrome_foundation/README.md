# chrome_foundation

Leaf foundation of the chat chrome: a semantic colour palette, per-component
token groups, a required, nestable, animatable theme scope, **motion roles**
with a speed scale, a required **chrome strings** scope and a **chrome icon**
registry. It depends on no workspace package (`scripts/check` enforces that),
only on Flutter, `meta` and `morphnext` (used by the icon registry alone).
Composer, panel and page packages read their colours, durations, strings and
icons from here; none of them carries a default of its own.

Also here: the **glass stack**, named glass materials drawn by `GlassSurface`
under a host quality policy
([ADR 027](../../docs/adr/027-foundation-theme-glass-motion.md)).

## Types

| Type | Role |
| --- | --- |
| `ChromePalette` | The **chrome palette**: 15 semantic colour roles (surfaces, text, icons, accent, separator, ...) plus a brightness. Constructors: custom (every role), `light`, `dark`, `highContrastLight`, `highContrastDark`, `forBrightness`, `fromColorScheme`. |
| `ComposerTokens`, `PanelTokens`, `ActionTokens`, `PlaceholderTokens`, `GlassMaterialTokens` | **Token groups**: immutable colours per component, each derived from a palette by `fromPalette`, with `copyWith` and `lerp`. `GlassMaterialTokens.colorsOf(material)` is what `GlassSurface` reads. |
| `ChromeThemeData` | A palette plus one value of every group: what a root scope carries and what two themes are interpolated between. |
| `ChromeThemeScope` | The **chrome theme scope** (`InheritedModel`). Required: a lookup with no supplier fails. Nested scopes override only the parts they supply. `of`, `paletteOf`, `composerOf`, ... |
| `AnimatedChromeThemeScope` | A scope that interpolates to new tokens with each part's `lerp`. |
| `ChromeContrast` | WCAG contrast ratio and the AA thresholds, for palette tests. |
| `MotionRole`, `MotionSpec`, `ChromeMotion` | The **motion role** table: one duration and curve per named thing chrome animates (list transition 250 ms on the Android cubic, panel slide, search, header reveal, press, release, fade, popup show / hide, presentation switch, theme switch). Immutable, overridable with `copyWith`. |
| `ChromeMotionSpeed`, `ChromeMotionScope`, `ChromeMotionData` | The speed scale (`normal`, `times(n)`, `instant`) and the nestable scope that supplies roles and speed. Components call `ChromeMotionScope.of(context).specOf(role)`. |
| `ScalePressable`, `OvershootCurve` | Press-scale hit target driven by the `press` / `release` roles, and the overshoot easing (Android's `OvershootInterpolator`). |
| `ChromeStrings` (`PanelStrings`, `ComposerStrings`, `SemanticsStrings`) | The **chrome strings**: grouped, host-provided text, with functions for plural and data-dependent wording. |
| `ChromeStringsScope` | Required scope supplying `ChromeStrings`; a lookup with no scope fails in debug builds. |
| `ChromeIconId`, `ChromeIconPainter`, `ChromeIconRegistry` | A **chrome icon** is a semantic id; the registry maps ids to painters (font glyph or paint callback). `ChromeIconRegistry.stock` paints the chrome's own ids; an unknown id draws a neutral fallback glyph. |
| `ChromeIconScope`, `ChromeIcon`, `AnimatedChromeIcon` | Scope adding host painters, the widget that draws an id, and the variant that morphs (font to font) or cross-fades (custom painter) when the id changes. |
| `GlassSurface`, `GlassMaterial` | A **glass material** (`composerIsland`, `panelButton`, `topPanel`) drawn over what is behind it. Colours come from `GlassMaterialTokens` in the chrome theme scope; the shape of the effect and the backdrop strategy are internal. |
| `GlassQuality`, `GlassQualityScope`, `GlassCapabilities` | The host's **glass quality** policy (`fullLiquid`, `frosted`, `flat`, `off`), a lite-mode flag, and the capabilities (shader filter, sampled backdrop, backdrop filter) that the strategy chain reads. `GlassCapabilities.detect()` is the default; a host or test can force a row of the matrix. |
| `GlassSourceScope`, `GlassSource` | Marks the content that sampled glass reads. A scope above the content and the surfaces, a source around the content. |
| `package:chrome_foundation/testing.dart` | `ChromeStringsPresets.english` / `.russian` and `describeChromeStrings` for completeness checks. Tests and demos only. |

Geometry is not a token here: metrics taken from the reference client stay constants owned by
the component that draws them. Labels are host strings, never tokens. Motion is
a role table with a speed scale, not a colour-style group, so it has no `lerp`.

## Using it

```dart
ChromeThemeScope(
  palette: const ChromePalette.dark(),           // every group derived
  child: ChromeThemeScope(
    composer: myChatComposerTokens,              // overrides only the composer
    child: ...,
  ),
)
// in a component:
final composer = ChromeThemeScope.composerOf(context);
```

- A scope that passes a `palette` supplies every group: the ones it does not
  pass are derived from that palette. A scope that passes only groups supplies
  just those; the rest resolve at the nearest outer scope that supplies them.
- A widget depends on the one group it reads (`InheritedModel` aspects), so a
  change to the panel group does not rebuild composer widgets.
- `AnimatedChromeThemeScope` takes the same parts and animates to new values
  (default 250 ms). Switching a part between supplied and absent is not
  interpolated.
- `ChromePalette.fromColorScheme` builds a palette from a Material
  `ColorScheme`; nothing else here reads `ThemeData`.

### Motion, strings and icons

```dart
ChromeMotionScope(
  // Reduce motion: the one input. The package never reads the platform flag.
  speed: MediaQuery.disableAnimationsOf(context)
      ? ChromeMotionSpeed.instant
      : ChromeMotionSpeed.normal,
  child: ChromeStringsScope(
    strings: myChromeStrings,                    // from the host l10n
    child: ChromeIconScope(
      icons: {const ChromeIconId('star'): ChromeIconPainter.font(Icons.star)},
      child: ...,
    ),
  ),
)
// in a component:
final spec = ChromeMotionScope.of(context).specOf(MotionRole.fade);
final hint = ChromeStringsScope.panelOf(context).searchHint;
AnimatedChromeIcon(ChromeIconId.keyboard);       // morphs on id change
```

- Components hold no literal durations (a test scans `lib/src` outside
  `lib/src/motion/`). A scope's `speed` scales every role, including an
  explicit duration given to `AnimatedChromeThemeScope`.
- `ChromeMotionScope` is optional: with none, widgets run the shipped roles at
  normal speed. Scopes nest; an inner one overrides only the `motion` or
  `speed` it names. Overriding one role is `motion.copyWith(search: ...)`.
- `ChromeStringsScope` is required and has no default language. Required
  constructor parameters make a missing string a compile error; run
  `describeChromeStrings(strings)` in a host test to check none is empty.
- `ChromeIconScope` adds painters to the enclosing registry (default
  `ChromeIconRegistry.stock`). Between two font glyphs the icon morphs through
  morphnext; any change involving a painted icon cross-fades over the `fade`
  role; under instant speed it swaps at once.

## Host contract

| The host provides | The host must not |
| --- | --- |
| A `ChromeThemeScope` above every chrome widget, with a `palette` (or every group). | Rely on a default theme: a lookup with no supplier throws in debug builds. There is no silent light fallback. |
| A palette that keeps the contrast of the pairings it draws (text 4.5:1, icons 3:1, WCAG AA). The presets do; `ChromeContrast.ratio` measures a custom one. | Assume a custom palette or `fromColorScheme` is accessible: only the presets are tested. |
| Brightness changes by supplying another palette, or by `AnimatedChromeThemeScope` for a cross-fade. | Mutate tokens or keep its own light/dark flag in a chrome widget. |
| Per-surface variation (a per-conversation look) as a nested scope naming only the groups that differ. | Wrap a group in a second theme mechanism (a `ThemeData` extension, a per-widget colour parameter). |
| Wallpaper-dependent colours through the groups (for example `ComposerTokens.contentFade`). | Expect tokens to read the wallpaper. |
| High-contrast mode by choosing `highContrastLight` / `highContrastDark` (the package does not read `MediaQuery.highContrast`). | Expect geometry here: it stays with the component that draws it. |
| A `ChromeStringsScope` above every chrome widget, filled from its own localisation or server language packs, including plural rules for `searchResultCount`. | Expect a default language, or import `testing.dart` from production code. Packages ship no translation. |
| A `ChromeMotionScope` with `ChromeMotionSpeed.instant` when `MediaQuery.disableAnimations` or its lite mode is on. | Assume the package honours the platform reduce-motion flag by itself: only the host maps it. |
| A `GlassSourceScope` over the content and the glass surfaces when sampled glass is wanted, and a `GlassQualityScope` to cap quality (low-power flag mapped by the host). | Import or name a strategy; the chain is not API. Put a fade or wash inside the `GlassSource` it should not frost. |
| Painters for its own icon ids through `ChromeIconScope` (or `ChromeIconRegistry.withPainters`). | Name an icon by glyph in a descriptor, or import morphnext to animate chrome icons. |

### Glass

```dart
GlassSourceScope(                       // chat screen: over content + chrome
  child: Stack(children: [
    GlassSource(child: messageList),    // what the glass frosts
    GlassSurface(material: GlassMaterial.composerIsland, child: composer),
  ]),
)
// Host policy (optional; the default is fullLiquid on detected capabilities):
GlassQualityScope(quality: GlassQuality.frosted, liteMode: batterySaver, child: ...)
```

`GlassSurface` picks how to draw its backdrop each build from four inputs: the
host's `GlassQuality` (lite mode caps it at flat), `GlassCapabilities`, whether a
`GlassSourceScope` is above it, and route motion. The chain is internal and not
exported:

| Quality | Source + sampling backend | No source, filter backend | Route moves, no source | No filters |
| --- | --- | --- | --- | --- |
| `fullLiquid` | sampled liquid (capture, refraction) | backdrop filter (liquid shader filter where supported, else blur) | flat | flat |
| `frosted` | sampled frost (capture, no refraction) | backdrop filter (blur) | flat | flat |
| `flat` | flat | flat | flat | flat |
| `off` | nothing | nothing | nothing | nothing |

- A sampled surface renders a downscaled, blurred copy of the source region
  once per frame for every surface in the scope (regions close enough merge
  into one capture) and never reads back the onscreen target, so route motion
  does not matter to it.
- A backdrop filter re-reads and re-filters everything under it on every frame
  it moves, so a surface paints flat while its route is pushed, popped, dragged
  by a back gesture, or covered by another route moving.
- Shaders load on first need. Until they load a sampled surface paints its fill
  flat; if loading fails the shader paths are dropped and the chain falls back
  to the blur-only filter.
- `GlassMaterial` fixes what does not vary with the theme (blur, saturation,
  refraction, stroke widths, default corner radius); `topPanel` never refracts.
  Pass `cornerRadius` for a different size (half the height makes a stadium).
- Keep content fades and washes outside the `GlassSource` (or cut them out
  under the surface) so they are not sampled into the glass.

**Glass capture cost: not yet measured.** The per-frame cost of the shared
capture on a mid-range device (frame time with and without glass, by surface
count) needs a device run; none has been done, so this package states no number.
[docs/chrome/glass-device-checklist.md](../../docs/chrome/glass-device-checklist.md)
lists what to measure and fills in the fallback matrix (Impeller, web,
Android, Windows, Linux).

## Palette values

Presets keep the text and icon pairings at WCAG AA (4.5:1 text, 3:1 icons;
7:1 text in the high-contrast presets). Where an earlier flat colour class
failed that, the preset uses the nearest value that passes. The values were
not re-derived from a reference client, so a fidelity review of the shipped
colours is open. The field-by-field mapping from that class, with the old and
shipped value of each, is in
[docs/chrome/palette-migration.md](../../docs/chrome/palette-migration.md).

New roles with no earlier counterpart: `ActionTokens.onSend` (glyph on the
send button), `PlaceholderTokens.skeleton`, `ChromePalette.destructive` and the
glass material colours (`GlassMaterialTokens`).

## Consolidated copies

`OvershootCurve` and `ScalePressable` live here, and `panel_shell`,
`chat_composer` and hosts use these copies. `panel_catalog` keeps
its own `OvershootCurve` because the dependency rules forbid it from reaching
this package.

## Tests and goldens

- Lerp, `copyWith`, equality, nesting, per-aspect rebuilds and missing-scope
  tests cover every group and the scope.
- `palette_contrast_test.dart` checks every text and icon pairing in the four
  presets (AA), and text again at 7:1 in the high-contrast presets.
- Motion: speed scale (scaled, instant, per-role override, nesting), role
  table, overshoot curve, press / release timing and a scan that no component
  spells a literal `Duration`.
- Strings: scope missing-scope assert and nesting, preset completeness (every
  key non-empty in each preset, same keys in both, snapshot lists every
  declared member) and plural wording.
- Icons: registry lookup, custom registration, fallback, scope nesting and
  morph between two ids (same state morphs; instant skips it; painted icons
  cross-fade over the `fade` role).
- Glass: strategy-selection table (`GlassQuality` x capabilities x source x
  route motion, lite mode), surface behaviour per quality, theme colours per
  material, the shared capture and route-motion tests, and a check that the
  barrel exports no strategy, shader or resolved-style file.
  `glass_flat_<material>.png` goldens cover the flat path (light and dark over
  a striped backdrop, 1% pixel tolerance for anti-aliased edges, pinned to
  macOS); sampled and filtered output is device-dependent and covered by the
  device checklist.
- `test/goldens/` holds one swatch per preset. The swatch is solid rectangles
  on whole pixels with no text, so it renders identically on macOS and Linux
  with no tolerance. Regenerate with
  `flutter test --update-goldens test/palette`.

## Decisions

- [ADR 027: Foundation theme tokens, glass and motion](../../docs/adr/027-foundation-theme-glass-motion.md)
  (token structure, delivery, palettes)
- [ADR 031: Localization, accessibility and input](../../docs/adr/031-localization-accessibility-and-input.md)
  (contrast rule, strings scope, reduce motion)
- Glossary: [chrome CONTEXT](../../docs/chrome/CONTEXT.md) (chrome palette,
  token group, chrome theme scope, motion role, chrome icon, chrome strings)

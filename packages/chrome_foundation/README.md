# chrome_foundation

Leaf foundation of the chat chrome: a semantic colour palette, per-component
token groups, a required, nestable, animatable theme scope, **motion roles**
with a speed scale, a required **chrome strings** scope and a **chrome icon**
registry. It depends on no workspace package (`scripts/check` enforces that),
only on Flutter, `meta` and `morphnext` (used by the icon registry alone).
Composer, panel and page packages read their colours, durations, strings and
icons from here; none of them carries a default of its own.

Scope of this release: palette, token groups, theme scope, motion, strings and
icons. The glass stack is part of the same package's roadmap
([ADR 027](../../docs/adr/027-foundation-theme-glass-motion.md)) and is not
here yet.

## Types

| Type | Role |
| --- | --- |
| `ChromePalette` | The **chrome palette**: 15 semantic colour roles (surfaces, text, icons, accent, separator, ...) plus a brightness. Constructors: custom (every role), `light`, `dark`, `highContrastLight`, `highContrastDark`, `forBrightness`, `fromColorScheme`. |
| `ComposerTokens`, `PanelTokens`, `ActionTokens`, `PlaceholderTokens`, `GlassMaterialTokens` | **Token groups**: immutable colours per component, each derived from a palette by `fromPalette`, with `copyWith` and `lerp`. The glass group is data only; the glass stack that paints it is a later addition. |
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
| `package:chrome_foundation/testing.dart` | `ChromeStringsPresets.english` / `.russian` and `describeChromeStrings` for completeness checks. Tests and demos only. |

Geometry is not a token here: Telegram-derived metrics stay constants owned by
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
| Painters for its own icon ids through `ChromeIconScope` (or `ChromeIconRegistry.withPainters`). | Name an icon by glyph in a descriptor, or import morphnext to animate chrome icons. |

## Migration: `ChatChromeColors` to token groups

Every field of the old flat class has one home. Colours are `AARRGGBB`; the
old default (light / dark) is beside the value the presets ship.

| `ChatChromeColors` | Old default | New home (palette role) | Shipped |
| --- | --- | --- | --- |
| `panelBackground` | `FFF0F2F5` / `FF20242A` | `PanelTokens.background` (`surfaceDim`) | `FFF0F2F5` / `FF20242A` |
| `panelIcon` | `FF9DA4AB` / `80FFFFFF` | `PanelTokens.categoryIcon` (`iconIdle`) | `FF7A8189` / `80FFFFFF` |
| `panelIconSelected` | `FF5E6976` / `FFFFFFFF` | `PanelTokens.categoryIconSelected` (`iconActive`) | `FF5E6976` / `FFFFFFFF` |
| `panelBackspace` | `FF8C9197` / `7DFFFFFF` | `ActionTokens.backspace` (`iconIdle`) | `FF7A8189` / `80FFFFFF` |
| `panelShadowLine` | `12000000` / `1E000000` | `PanelTokens.hairline` (`separator`) | `12000000` / `1E000000` |
| `panelTabSelector` | `FFE2E5E7` / `0ACDEAFF` | `PanelTokens.tabSelector` (`surfaceTint`) | `FFE2E5E7` / `0ACDEAFF` |
| `panelTabSelectorLine` | `FF56ABF0` / `FF64B5EF` | `PanelTokens.tabSelectorLine` (`accent`) | `FF2874B0` / `FF54A1DB` |
| `panelStickerSetName` | `FF8B9197` / `73FFFFFF` | `PanelTokens.sectionTitle` (`onSurfaceMuted`) | `FF5F666D` / `99FFFFFF` |
| `panelEmptyText` | `FF949BA1` / `FF7D7D7E` | `PlaceholderTokens.emptyState` (`onSurfaceMuted`) | `FF5F666D` / `99FFFFFF` |
| `panelFloatingFill` | `FFE8EAED` / `FF2C2C2E` | `ActionTokens.floatingFill` (`surfaceRaised`) | `FFE8EAED` / `FF2C2C2E` |
| `panelFloatingSelected` | `FFFFFFFF` / `FF3A3A3C` | `ActionTokens.floatingSelectedFill` (`surfaceSelected`) | `FFFFFFFF` / `FF3A3A3C` |
| `panelFloatingText` | `FF000000` / `FFFFFFFF` | `ActionTokens.floatingLabel` (`onSurface`) | `FF000000` / `FFFFFFFF` |
| `panelFloatingTextMuted` | `99000000` / `99FFFFFF` | `ActionTokens.floatingLabelMuted` (`onSurfaceMuted`) | `FF5F666D` / `99FFFFFF` |
| `emojiSearchFill` | `0F000000` / `0FFFFFFF` | `PanelTokens.searchFill` (`onSurface at alpha 0x0F`) | `0F000000` / `0FFFFFFF` |
| `emojiSearchIcon` | `66000000` / `66FFFFFF` | `PanelTokens.searchIcon` (`iconIdle`) | `FF7A8189` / `80FFFFFF` |
| `emojiSearchHint` | `73000000` / `73FFFFFF` | `PlaceholderTokens.fieldHint` (`onSurfaceMuted`) | `FF5F666D` / `99FFFFFF` |
| `emojiSearchText` | `CC000000` / `CCFFFFFF` | `PanelTokens.searchText` (`onSurface`) | `FF000000` / `FFFFFFFF` |
| `messagePanelBackground` | `FFFFFFFF` / `FF20242A` | `ComposerTokens.background` (`surface`) | `FFFFFFFF` / `FF20242A` |
| `messagePanelText` | `FF000000` / `FFFFFFFF` | `ComposerTokens.text` (`onSurface`) | `FF000000` / `FFFFFFFF` |
| `messagePanelHint` | `FF858A84` / `99FFFFFF` | `PlaceholderTokens.fieldHint` (`onSurfaceMuted`) | `FF5F666D` / `99FFFFFF` |
| `messagePanelCursor` | `FF54A1DB` / `FFFFFFFF` | `ComposerTokens.cursor` (`accent`) | `FF2874B0` / `FF54A1DB` |
| `messagePanelIcons` | `FF8E959B` / `E6FFFFFF` | `ActionTokens.icon` (`iconIdle`) | `FF7A8189` / `80FFFFFF` |
| `messagePanelSend` | `FF54A1DB` / `FF54A1DB` | `ActionTokens.send` (`accent`) | `FF2874B0` / `FF54A1DB` |
| `messagePanelShadow` | `FF000000` / `FF000000` | `ComposerTokens.shadow` (`shadow`) | `FF000000` / `FF000000` |
| `contentBottomFade` | `FFFFFFFF` / `FF15191E` | `ComposerTokens.contentFade` (`contentFade`) | `FFFFFFFF` / `FF15191E` |
| `replyLine` | `FF54A1DB` / `FF54A1DB` | `ComposerTokens.replyLine` (`accent`) | `FF2874B0` / `FF54A1DB` |
| `replyName` | `FF54A1DB` / `FF54A1DB` | `ComposerTokens.replyName` (`accent`) | `FF2874B0` / `FF54A1DB` |
| `replyText` | `FF8A8A8A` / `99FFFFFF` | `ComposerTokens.replyText` (`onSurfaceMuted`) | `FF5F666D` / `99FFFFFF` |
| `ChatChromeTheme` (silent light fallback) | | `ChromeThemeScope` (required) | |
| `ChatChromeColors.forBrightness` | | `ChromePalette.forBrightness` + `ChromeThemeData.fromPalette` | |

New, with no old counterpart: `ActionTokens.onSend` (glyph on the send button),
`PlaceholderTokens.skeleton`, `ChromePalette.destructive`, and the glass
material colours (`GlassMaterialTokens`, replacing the colour half of the old
`LiquidGlassStyle` factories).

Several old fields collapse onto one role (the idle greys, the muted text
colours, the two blues); that is the point of a palette. A host that wants the
old distinction overrides the one token with `copyWith`.

### Why some shipped values differ from the old ones

The ticket requires AA contrast for text and icon tokens in every palette. The
old light greys (`9DA4AB`, `8B9197`, `858A84`) reach 2.1 to 3.5:1 on their
surfaces, the old light blue `54A1DB` reaches 2.8:1 as text and under a white
glyph, and some dark muted greys fall to 2.8 to 3.8:1. The presets keep the
old colour where it passes and use the nearest value that passes where it does
not (the table shows each change). The old numbers are the `ChatChromeColors`
defaults as ported; they were not re-derived from the Telegram sources, which
are not part of this checkout, so a fidelity review of the shipped values is
still open.

## Consolidated copies

`OvershootCurve` and `ScalePressable` live here. `chat_chrome` and the example
app use these; `panel_catalog` keeps its own `OvershootCurve` because the
dependency rules forbid it from reaching this package (the catalog takes its
curve from the page that adapts it).

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

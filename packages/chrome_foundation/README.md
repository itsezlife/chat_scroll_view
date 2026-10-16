# chrome_foundation

Leaf foundation of the chat chrome: a semantic colour palette, per-component
token groups and a required, nestable, animatable theme scope. It depends on no
workspace package (`scripts/check` enforces that), only on Flutter and `meta`.
Composer, panel and page packages read their colours from here; none of them
carries a colour default of its own.

## Types

| Type | Role |
| --- | --- |
| `ChromePalette` | The **chrome palette**: 15 semantic colour roles (surfaces, text, icons, accent, separator, ...) plus a brightness. Constructors: custom (every role), `light`, `dark`, `highContrastLight`, `highContrastDark`, `forBrightness`, `fromColorScheme`. |
| `ComposerTokens`, `PanelTokens`, `ActionTokens`, `PlaceholderTokens`, `GlassMaterialTokens` | **Token groups**: immutable colours per component, each derived from a palette by `fromPalette`, with `copyWith` and `lerp`. The glass group is data only; the glass stack that paints it is a later addition. |
| `ChromeThemeData` | A palette plus one value of every group: what a root scope carries and what two themes are interpolated between. |
| `ChromeThemeScope` | The **chrome theme scope** (`InheritedModel`). Required: a lookup with no supplier fails. Nested scopes override only the parts they supply. `of`, `paletteOf`, `composerOf`, ... |
| `AnimatedChromeThemeScope` | A scope that interpolates to new tokens with each part's `lerp`. |
| `ChromeContrast` | WCAG contrast ratio and the AA thresholds, for palette tests. |

Geometry, motion, strings and icons are not tokens here: Telegram-derived
metrics stay constants owned by the component that draws them; labels are host
strings, never tokens.

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

## Host contract

| The host provides | The host must not |
| --- | --- |
| A `ChromeThemeScope` above every chrome widget, with a `palette` (or every group). | Rely on a default theme: a lookup with no supplier throws in debug builds. There is no silent light fallback. |
| A palette that keeps the contrast of the pairings it draws (text 4.5:1, icons 3:1, WCAG AA). The presets do; `ChromeContrast.ratio` measures a custom one. | Assume a custom palette or `fromColorScheme` is accessible: only the presets are tested. |
| Brightness changes by supplying another palette, or by `AnimatedChromeThemeScope` for a cross-fade. | Mutate tokens or keep its own light/dark flag in a chrome widget. |
| Per-surface variation (a per-conversation look) as a nested scope naming only the groups that differ. | Wrap a group in a second theme mechanism (a `ThemeData` extension, a per-widget colour parameter). |
| Wallpaper-dependent colours through the groups (for example `ComposerTokens.contentFade`). | Expect tokens to read the wallpaper. |
| High-contrast mode by choosing `highContrastLight` / `highContrastDark` (the package does not read `MediaQuery.highContrast`). | Expect labels, icons or motion here: they are separate concerns. |

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

## Tests and goldens

- Lerp, `copyWith`, equality, nesting, per-aspect rebuilds and missing-scope
  tests cover every group and the scope.
- `palette_contrast_test.dart` checks every text and icon pairing in the four
  presets (AA), and text again at 7:1 in the high-contrast presets.
- `test/goldens/` holds one swatch per preset. The swatch is solid rectangles
  on whole pixels with no text, so it renders identically on macOS and Linux
  with no tolerance. Regenerate with
  `flutter test --update-goldens test/palette`.

## Decisions

Token structure, delivery, palettes (ADR candidate
`foundation-theme-glass-motion`) and the contrast rule (ADR candidate
`l10n-a11y-input`) are proposed and move to `docs/adr/` with the architecture
documentation.

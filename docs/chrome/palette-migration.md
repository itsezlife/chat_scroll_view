# Palette migration: `ChatChromeColors` to token groups

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

## Why some shipped values differ from the old ones

The foundation requires AA contrast for text and icon tokens in every palette. The
old light greys (`9DA4AB`, `8B9197`, `858A84`) reach 2.1 to 3.5:1 on their
surfaces, the old light blue `54A1DB` reaches 2.8:1 as text and under a white
glyph, and some dark muted greys fall to 2.8 to 3.8:1. The presets keep the
old colour where it passes and use the nearest value that passes where it does
not (the table shows each change). The old numbers are the `ChatChromeColors`
defaults as ported; they were not re-derived from the reference client's
sources, which are not part of this checkout, so a fidelity review of the
shipped values is still open.

The palette and token groups themselves are described in
[`chrome_foundation`](../../packages/chrome_foundation/README.md).

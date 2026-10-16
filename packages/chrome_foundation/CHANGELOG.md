# Changelog

All notable changes to `chrome_foundation` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Added

- `ChromePalette` (custom, light, dark, high-contrast, `fromColorScheme`).
- Token groups `ComposerTokens`, `PanelTokens`, `ActionTokens`,
  `PlaceholderTokens`, `GlassMaterialTokens`, each with `fromPalette`,
  `copyWith` and `lerp`; `ChromeThemeData` bundles them.
- `ChromeThemeScope` (required, nestable `InheritedModel`) and
  `AnimatedChromeThemeScope`.
- `ChromeContrast` for WCAG contrast checks.

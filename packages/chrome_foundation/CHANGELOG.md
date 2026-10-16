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
- `ChromeMotion` role table (`MotionRole`, `MotionSpec`), `ChromeMotionSpeed`
  (normal, `times(n)`, instant) and the optional, nestable `ChromeMotionScope`.
- `ScalePressable` and `OvershootCurve`, moved here from `chat_chrome`.
- `ChromeStrings` (`PanelStrings`, `ComposerStrings`, `SemanticsStrings`) and
  the required `ChromeStringsScope`; English and Russian presets in
  `testing.dart` only.
- `ChromeIconId`, `ChromeIconRegistry` (stock painters, host registration,
  fallback glyph), `ChromeIconScope`, `ChromeIcon` and `AnimatedChromeIcon`
  (morph between font glyphs, cross-fade for painted icons).

### Changed

- `AnimatedChromeThemeScope` takes its default duration and curve from the
  `themeSwitch` motion role (`duration` and `curve` are now optional) and its
  duration is scaled by the motion speed. Explicit values still apply.

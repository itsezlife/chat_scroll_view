# ADR 027: Foundation theme tokens, glass and motion

`chrome_foundation` is a leaf package holding the semantic palette, per-component token groups, a required nestable theme scope, named glass materials with a quality policy, motion roles and a stock icon registry. It has no dependency on composer, panel or data code.

**Status**: Accepted  
**Date**: 2026-10-16  
**Relates to**: [ADR 020](020-package-topology.md), [ADR 031](031-localization-accessibility-and-input.md)

## Decided

| Area | Decision |
| ---- | -------- |
| Token structure | A small semantic `ChromePalette` (surface, onSurface, accent, separator, destructive, placeholder, ...) with light, dark and custom constructors. Per-component token groups derive from it by default: `ComposerTokens`, `PanelTokens`, `GlassMaterials`, `ActionTokens`, and so on. Each group is immutable with `copyWith` and `lerp`, and individually overridable. The panel catalog theme (adapted in `panel_pages`) and the glass style derive from the same palette, so there is one brightness mechanism. |
| Delivery | `ChromeThemeScope` (an `InheritedModel`) in foundation. Lookup asserts without a scope, with no silent light fallback. Scopes nest: a per-chat or per-surface scope overrides only the groups it supplies. The scope animates between two themes through `lerp`. It is independent of `ThemeData`, with an optional adapter from `ColorScheme`. |
| Glass seam | `GlassSurface(material: ...)` with named `GlassMaterials` (composer island, panel button, top panel, ...) inside an optional `GlassSourceScope`. A host-provided `GlassQuality` policy (full liquid, frosted, flat, off) combines detected capabilities (Impeller shader availability, web and desktop support), a host lite-mode flag and the transient route-motion rule. An internal strategy chain (sampled liquid, sampled frost, `BackdropFilter`, flat fill) is not public API. Glass and its three shaders live in foundation. |
| Motion | A `ChromeMotion` token group by semantic role (list transition 250 ms with the Android cubic, panel slide, search, header reveal, press, fade, presentation open and close, ...). Components read roles and hold no literal durations. A scope-level speed factor, including instant, implements reduce-motion and lite mode. |
| Metrics | Telegram-derived geometry stays component-owned as documented constants. Only colours, materials and motion are tokens. |
| Icons | A stock `ChromeIcon` registry (semantic id to painter) with a morph-transition helper; the `morphnext` dependency is isolated in foundation. Hosts register painters for custom ids. Composer actions and panel tabs refer to icons by semantic id. |
| Strings | Labels are never tokens. See [ADR 031](031-localization-accessibility-and-input.md). |
| Palettes | Telegram-derived light and dark palettes ship as defaults and apply only when supplied explicitly. |
| Wallpaper | Tokens are independent of wallpaper. A per-chat theme is a nested scope, and the host feeds the glass source from chat content. |
| Fallback matrix | The per-platform glass fallback (Impeller, web, Android, Windows, Linux) is established by capability detection and device testing, and is not decided here. |

## Why

- The old chrome colours were one flat 28-colour class with a silent light fallback, and three independent theming mechanisms (colours, patched catalog theme, glass style).
- Telegram Android uses key groups with fallback chains and a per-chat `ResourcesProvider` with animating colours; glass is a separate module with named presets chosen by capability and lite mode. iOS uses an immutable theme group tree and a one-entry glass update. No client has a central motion registry; role-based motion generalises the common practice.
- Glass cost is dominated by capture-based sampling shared per frame, and flat paint while a route moves avoids it.

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| One flat token class; a flat key map with fallback chains | Cannot be overridden per component or nested cheaply |
| Flutter `ThemeExtension`; an explicit theme parameter on every widget | Ties chrome to `ThemeData`; prop drilling |
| A public `GlassRenderer` interface; public flag-driven glass widgets | Strategy details would become API |
| Caller-passed transitions; component-owned motion constants | No global speed scale |

## Related

- Glossary: [Chat chrome](../chrome/CONTEXT.md)

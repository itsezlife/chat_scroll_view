# ADR 031: Localization, accessibility and input modalities

Chrome strings come from a required host-filled scope, layout is directional by
default, the painted catalog exposes semantics for its visible window, and
keyboard and pointer input run through Flutter intents and actions. These are
public-seam decisions because windowed semantics, roving focus and grid text
direction are expensive to add later.

**Status**: Accepted  
**Date**: 2026-10-16  
**Relates to**: [ADR 024](024-panel-catalog-seams.md), [ADR 025](025-panel-shell-and-pages.md), [ADR 027](027-foundation-theme-glass-motion.md), [ADR 028](028-panel-presentation.md)

This ADR rests on Flutter norms and the earlier decisions. The Telegram
reference clients were not studied for it.

## Decided

| Concern | Decision |
| ------- | -------- |
| Strings | One required `ChromeStringsScope` in `chrome_foundation`, asserting when missing. `ChromeStrings` is grouped as `PanelStrings`, `ComposerStrings`, `SemanticsStrings`, with functions for plural and data-dependent wording. The host fills it from its own localization or server language packs. Packages ship no translations and no production default language; English and Russian presets live in `testing.dart` and the demo app. Descriptors carry semantic ids and the scope maps them to strings. |
| RTL | Directional primitives everywhere (start and end). Strips and scroll direction, bottom bar, action placement, popup anchor and docked side mirror. The catalog grid orders cells start to end through `Grid.textDirection` (default `Directionality`). Glyphs, stickers and GIF content are never mirrored. Direction-sensitive geometry (bottom-bar hide slide, page swipe, section jump) is direction-aware. RTL goldens and widget tests are part of the definition of done. |
| Semantics | The viewport emits semantic nodes only for the visible window of leaves plus a small overscan. The label is the descriptor's spoken name, the tap action goes through the same `ContentPicked` path, and variants are custom actions. The keyword pack carries a spoken CLDR `tts` name per locale; stickers use the set title or emoji alt, and custom emoji use the inline-ref alt. Sections get header semantics. The shell announces open and close, page changes and search result counts. Descriptors (tabs, actions, sections) require a semantic label, enforced by a test rule. Focus enters the popup on open and returns to the composer on close (`PanelFocusPolicy`). |
| Input | `Intent`s and `Actions` in shell, pages, popup and composer. Default `Shortcuts` maps follow the `$Mobile` / `$Desktop` policy and hosts can override them. Grid roving focus: arrows move across leaves and sections, Enter and Space pick, and the focused leaf paints with the press-highlight token and scrolls into view. Tab order: strip, grid, bottom bar, search. Esc clears search, then closes the popup. A search shortcut focuses the field, and backspace in the search field edits it, not the composer. Leaves and actions use the click cursor, and hover highlight uses press-highlight tokens. Popup hover-open applies only to `PointerDeviceKind.mouse`; touch and stylus click. Composer entity edits commit on finished IME composition. |
| Reduce motion | The foundation speed scale is the single input. The host maps `MediaQuery.disableAnimations` to instant mode; the Host contract documents this. |
| Contrast | Palette tests check text and icon token contrast (AA). A high-contrast palette is a constructor. |
| Text scale | Text in the search field, section headers, the composer field and strings respects `TextScaler`. Telegram-derived geometry constants stay fixed with documented clamps. |
| Language | The UI locale (strings) is independent of the search language set ([ADR 023](023-data-layering-and-persistence.md)). |

### API additions per package

| Package | Additions |
| ------- | --------- |
| `chrome_foundation` | `ChromeStrings` and scope, speed scale, contrast tests, direction helpers |
| `content_model` and the generator | Spoken name on the descriptor and in keyword packs |
| `panel_catalog` | `Grid.textDirection`, windowed semantics, roving-focus controller API, focus highlight token, cursor |
| `panel_shell`, `panel_pages` | Required semantic labels, `PanelFocusPolicy`, intents and default shortcut maps |
| `chat_composer` | Required semantic labels on `ActionDescriptor`, IME composition guard, directional layout |
| `panel_presentation` | Mouse-only hover, Esc and outside click through actions, mirrored anchor, announcements |

## Why

- The old code had one `Semantics` widget and three `semanticsLabel`s across four packages, RTL handling in two files, no cursors or hover, shortcuts only in the bottom actions, and a labels class with hard-coded English and Russian defaults plus English stubs.
- Retrofitting windowed semantics and roving focus into a painted viewport, and `Grid.textDirection` into a public seam, costs more than building them in.

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| Per-package label classes; packages shipping translations or delegates | Every host would fill several classes, and packages would own languages |
| Mirroring chrome only; deferring RTL | The grid order is a public seam |
| Page-level semantics only; one semantic node per leaf | Page-level gives no per-item access; per-leaf nodes cost too much for a catalog of thousands |
| Hard-coded key handlers; touch and pointer only | Hosts cannot override; keyboard users are excluded |

## Related

- Glossary: [Chat chrome](../chrome/CONTEXT.md), [Panel Catalog](../panel-catalog/CONTEXT.md)

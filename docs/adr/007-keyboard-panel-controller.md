# ADR 007: KeyboardPanel controller as chrome source of truth

Chat chrome’s keyboard-replacement surface is **KeyboardPanel**, driven by a
host-owned **KeyboardPanelController** — not Telegram’s imperative `EmojiView`
/`GlobalKey<State>` model. The controller is the source of truth for open/tab/
search (and related chrome intents); the widget projects that state. Extent
scroll stays on page-local [PanelCatalogController].

**Status**: Accepted  
**Date**: 2026-08-25

## Decided

| Topic | Decision |
| ----- | -------- |
| Name | **KeyboardPanel** / **KeyboardPanelController** — role is IME-slot chrome; avoids CatalogPanel↔PanelCatalog mirror and lasting `EmojiPanel` / `EmojiView` API |
| Rename scope | Chrome types → `KeyboardPanel*` (incl. [KeyboardPanelStore]); unicode page / glyph / `emoji_data` stay `Emoji*`; prefs keys → `keyboard_panel_*` with **no** legacy dual-read |
| SoT | Controller holds desired chrome state; commands commit and notify even when unbound; bound panel projects into motion/layout |
| Listeners | Typed listeners (+ optional sealed panel events): dedup-on-add, snapshot dispatch, silent no-ops after dispose — same house pattern as [PanelCatalogController] / [ChatScrollController], not `ChangeNotifier` / app `StateController` |
| Inset | Controller ctor takes bottom-inset arbiter + [KeyboardPanelStore]; `open`/`close` claim or release the slot — host MUST NOT dual-call `openPanel` + panel open |
| Non-ownership | Inset math, composer text, insert/backspace, clear-recents UI — widget/host callbacks and [ChatBottomInsetController], not the panel controller |
| Catalog scroll | [PanelCatalogController] remains **page-local**; not exposed through KeyboardPanelController unless a real host navigation need appears |
| Widget API | One panel controller + presentation config (`allow`, `labels`, actions) + effect callbacks; no declarative lasting `open:` flag; no GlobalKey for open/close/search/tab |
| Recents store | Drop `_migrateLegacyList` and dual-read of `chat_chrome_emoji_*` history keys; read/write only `emoji_data_use_history` |

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| CatalogPanel naming | Mirrors Panel Catalog package / controller; footgun in pub API |
| Keep Telegram `EmojiView` / GlobalKey on State | Imperative, not usable cleanly outside composer; locks logic in State |
| Merge chrome into ChatBottomInsetController | Mixes occupancy math with tabs/search/motion |
| Merge chrome into PanelCatalogController | Wrong layer — extent scroll ≠ panel chrome |
| Command-only silent no-op while unbound | Breaks deterministic control before/after mount |
| Put insert/backspace on the controller | Couples chrome SoT to composer / BuildContext |
| Expose page catalog controller on panel API | No host use-case; collapses page and chrome boundaries |
| Keep legacy recents migrate | Package not a stable published migrate contract; dead weight |

## Related

- Panel catalog viewport / former “catalog shell”: [ADR 006](006-panel-catalog-viewport.md) (shell term → **KeyboardPanel**)
- Glossary: [docs/panel-catalog/CONTEXT.md](../panel-catalog/CONTEXT.md)

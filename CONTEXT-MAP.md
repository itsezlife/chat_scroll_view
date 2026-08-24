# Context Map

## Contexts

- [Chat Scroll Viewport](./CONTEXT.md) — anchor-based bidirectional chat list (message-id origin)
- [Panel Catalog Viewport](./docs/panel-catalog/CONTEXT.md) — keyboard-panel catalog body (emoji / stickers / GIFs)

## Relationships

- **Chat Scroll ↔ Panel Catalog**: Shared *idea* of **stitch** (far-path continuity illusion). Shared **global catalog asset cache** for document-backed emoji/stickers/GIFs (panel grid and chat inline/attachment leaves). Different identity and geometry models — do not share message-id origin, chunks, or navigation load-gate.
- **Chat Scroll ↛ Panel Catalog**: Message attachment media (photo/video galleries in the chat) is **not** Panel Catalog. That surface stays under Chat Scroll / future attachment chrome.
- **Panel Catalog → chat_chrome shell**: The catalog shell hosts the viewport and supplies [PanelCatalogTheme]. Category jumps call [PanelCatalogController.jumpToSection]; hosts gate strip sync on [isSectionJumpActive]. Leaf tap/long-press are viewport callbacks; eligibility and picker UI are shell policy (glossary: *Panel catalog theme*, *Section jump*, *Leaf long-press callback*, *Long-press eligibility*).
- **Packages**: Repo-root `packages/` holds shared ecosystem libs — `catalog_assets`, `panel_catalog`, `emoji_data`, `chat_chrome`. `keyboard_insets*` stay under `example/packages`. `chat_scroll_view` remains at repo root. `example/` is the app only.
- **ADR**: [006 — Panel Catalog Viewport](./docs/adr/006-panel-catalog-viewport.md)
- **Placeholder TRACE**: [docs/panel-catalog/leaf-placeholder.md](./docs/panel-catalog/leaf-placeholder.md) — circle vs thumb-first vs shaped wash (Telegram).

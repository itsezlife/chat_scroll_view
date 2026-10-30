# ADR 040: Chat wallpaper package and resize behaviour

What a chat draws behind its messages is a leaf package, `chat_wallpaper`: a
value model with a string codec, a deterministic freeform renderer, motion, the
view and service fills. A patterned wallpaper is painted in one fragment
shader pass every frame, and its pattern is rasterized once per display, so
motion, resizing, rotation and page transitions rasterize and snapshot
nothing.

**Status**: Accepted  
**Date**: 2026-10-31  
**Relates to**: [ADR 020](020-package-topology.md), [ADR 027](027-foundation-theme-glass-motion.md), [ADR 029](029-host-integration.md)

## Context

The wallpaper was built in a host app and moves here so that every host
paints the same background, with the same motion and service-chrome colours,
and so that the example app and its on-device suites can measure it next to
the chat, the composer and the glass that sample it.

The host measured the cost of a patterned wallpaper on a 120 Hz phone. The
soft-light and mask blends redo a full-box offscreen pass on every frame the
box moves, so the composite is painted from one snapshot of itself. That
snapshot is a GPU pass over the whole box in physical pixels: 38 to 56 ms full
screen on that phone.

Both rasters were keyed by the window. The pattern raster's width was the
window's shorter side, and the snapshot was dropped on any size change. Every
step of a desktop window drag therefore rasterized the artwork again, dropped
the pattern until the new raster landed (the bare fill flashed, then the
pattern faded in) and snapshotted the whole box again.

Telegram does neither:

- Desktop keeps one bitmap of the whole background, draws it stretched while
  the window is resized, rebuilds it on a worker thread 200 ms after the last
  size change (not while a mouse button is held) and crossfades it in over
  200 ms.
- Android rasterizes the pattern once at the display's portrait size and
  draws it cover-fit into whatever bounds the view has, so rotation,
  split-screen and folding rasterize nothing.
- iOS re-renders at the exact size, hiding the cost behind the animated
  frame change of the old image.

## Decided

| Concern | Decision |
| ------- | -------- |
| Package | `chat_wallpaper`, a leaf: it depends on no workspace package (only `flutter`, `vector_graphics` and `equatable`). It owns the model (`ChatWallpaper` sealed by fill kind, `WallpaperPattern`), its codec, the service tone and shade, the freeform renderer and keyframes, the motion controller and scope, the view, the warm-up host, the theme scope and `WallpaperServiceFill`. Pattern artwork is the host's: it registers vector loaders by slug. |
| Pattern raster | Keyed by slug and width, the width being the display's shorter side in physical pixels. The raster is drawn cover-fit into the box, never smaller than cover-fit into the window, so a thumbnail crops instead of shrinking and a resize only rescales the draw. Where the platform reports no display size, the window's shorter side stands in. |
| Composite | One fragment shader (`shaders/patterned_fill.frag`) computes the fill (freeform keyframes with their crossfade, linear or solid) and blends the pattern over it per pixel: mask onto black, or W3C soft light of black or white ink. No offscreen layer, no snapshot, no composite cache. Until the pattern raster and the program have both landed the bare fill paints; the warm-up loads the program. |
| Gradient | Unchanged: a 60 × 80 raster drawn cover-fit with bilinear upscale, as on both mobile platforms. A resize costs nothing. |
| Diagnostics | `chat_wallpaper_diagnostics.dart` counts pattern rasterizations and gradient rasters. Observation only, kept in profile and release builds so that on-device suites can attribute raster cost. |

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| Pattern raster per window size (as before) | A desktop drag rasterizes the artwork per step and flashes the bare fill |
| A square raster of the display's longer side | Twice the texture for a crop nobody sees; the shorter side cover-fit already covers a rotated window |
| No composite snapshot: blend live every frame | Measured as the transition jank source on the host; the snapshot is what made route transitions fit the budget |
| Snapshot on every size change | One full-box GPU pass per drag step |
| Snapshot the composite, stretched during a resize and retaken once it settles (Telegram Desktop) | Built and measured first. The snapshot (`toImageSync`) costs 28 to 63 ms of raster-thread time per settle on a 120 Hz phone, hidden from frame raster times; and the first live frame after any still period re-allocates the blend's offscreen layer, a 30 to 48 ms frame at the start of every gradient motion. Ablation: with the pattern removed both costs vanish; with glass off they stay |
| Fill painted by its own widget, pattern blended over it with a layer | The blend reads the pixels under it, so it needs the offscreen layer above every frame it paints |
| Debouncing on a held mouse button, as Desktop does | Nothing is retaken on a resize, so there is nothing to debounce; Flutter would not see the OS's window-frame drag anyway |

## Consequences

- Every frame of a patterned wallpaper costs one full-box shader draw:
  still, moving, resized or sliding under a route. Nothing is cached per
  size, so a resize needs no settle and shows no stretch.
- The shader loads asynchronously once per process; a view mounted before
  it lands paints the bare fill and fades the pattern in.
- A freeform fill under a pattern holds the motion controller's keyframes
  itself (the bare fill it replaces held them too), so the composite and the
  service fills move frame for frame together.

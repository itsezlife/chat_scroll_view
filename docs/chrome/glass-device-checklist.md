# Glass device checklist

Manual release checklist for the glass stack in `chrome_foundation`. Unit tests
cover strategy selection (`GlassQuality` x capabilities x source x route motion)
and the flat path; sampled and filtered output depends on the device, so this
list produces the measurements and the **fallback matrix** that the package
cannot decide on its own ([ADR 027](../adr/027-foundation-theme-glass-motion.md),
[ADR 030](../adr/030-testing-policy.md)).

Force a row with `GlassQualityScope(capabilities: ...)` and a quality, or leave
both at their defaults to test detection.

## Per device

Record device model, OS version, engine (Impeller or not), platform, build mode
(profile, never debug).

| Check | How | Record |
| ----- | --- | ------ |
| Detected capabilities | Print `GlassCapabilities.detect()` | the three flags |
| Sampled liquid draws | `GlassSourceScope` + `GlassSource` over scrolling content, `fullLiquid` | looks right: tint, rim refraction, strokes; no black or stale frames |
| Sampled frost draws | Same, `frosted` | no refraction, same blur and tint |
| Backdrop filter draws | No `GlassSourceScope`, `fullLiquid` then `frosted` | looks right |
| Flat draws | `flat`, and lite mode on | fill, strokes, shadow only |
| Off draws nothing | `off` | only the child |
| Shaders load | Cold start, first frame with glass | first frame flat is acceptable; no flicker after load |
| Route motion | Push, pop and back-gesture a route holding a no-source surface | flat while moving, glass on settle, no jump larger than the tint |
| Sampled stays on | Same with a source | no flat flash |
| Brightness switch | Light to dark through `AnimatedChromeThemeScope` | material colours animate |

## Capture cost (spec risk: acceptance criterion)

Profile build, mid-range device, scrolling content under the composer island.

| Scenario | Record |
| -------- | ------ |
| No glass (`off`) | raster and UI frame time, p50 and p99 |
| Flat | same |
| `frosted`, sampled, 1 surface | same |
| `fullLiquid`, sampled, 1 surface | same |
| `fullLiquid`, sampled, 3 surfaces (island, button, top panel) | same; note whether the capture merged |
| `fullLiquid`, backdrop filter, 1 surface | same |
| Panel opening or keyboard animating with glass | dropped frames |

Enter the sampled `fullLiquid` 1-surface result in the Glass section of
`packages/chrome_foundation/README.md` ("Glass capture cost").

## Fallback matrix

Fill one row per platform; the result decides `GlassCapabilities.detect()` (for
example, web is currently detected as no sampling) and any default quality a
host should ship.

| Platform | Engine | Best working strategy | Quality to ship | Notes |
| -------- | ------ | --------------------- | --------------- | ----- |
| iOS | Impeller | | | |
| Android (Impeller) | Impeller | | | |
| Android (no Impeller) | Skia | | | |
| Web | CanvasKit / Skwasm | | | |
| macOS | | | | |
| Windows | | | | |
| Linux | | | | |

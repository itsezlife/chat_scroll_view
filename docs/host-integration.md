# Host integration guide

How a host app assembles the chat chrome packages: which to depend on, what to
create in which order, who owns and disposes each object, and what the host
wires itself. It follows [ADR 029](adr/029-host-integration.md): there is no
facade package and no service locator, every package has plain constructors and
a scope widget, and the host builds one composition root.

Each package README ends its contract in a **Host contract** table (what the
host provides, what it must not do). This guide is the order those tables
apply in. The reference host is the demo app under `example/`; the last section
maps each step to its file.

Terms: [Chat chrome](chrome/CONTEXT.md), [Content and Assets](content/CONTEXT.md),
[Panel Catalog](panel-catalog/CONTEXT.md).

## 1. Packages for an emoji-only host

```yaml
dependencies:
  chrome_foundation:      # theme, motion, strings, icons, glass
  content_model:          # keys, collections, stores, RichText
  listen:                 # Listenable, ValueListenable, ChangeNotifier, ValueNotifier (pub.dev)
  catalog_assets:         # asset cache, glyph atlas
  emoji_data:             # emoji sources, glyph probe
  emoji_catalog_pack:     # bundled emoji assets (declare it so Flutter bundles them)
  kv_shared_preferences:  # KeyValueStore over shared_preferences
  panel_shell:            # pages, shell controller, pager, tabs, search
  panel_pages:            # CatalogPage, EmojiPage
  panel_presentation:     # keyboard replacement, popup, dock, occupancy
  chat_composer:          # composer view and controllers
```

`listen` is the pure-Dart package behind every change signal in the seams and
controllers (the same `Listenable` family as `package:flutter/foundation`,
standalone). Depend on it to name its types or to own a notifier; no package
re-exports it.

`panel_catalog` arrives through `panel_pages`; depend on it directly only to
name its types (the controller's events, `CatalogSnapshot`). Nothing re-exports
another package, so import what you use.

Dependency direction is enforced by `scripts/check`
([ADR 020](adr/020-package-topology.md)): `panel_shell`, `panel_pages` and
`panel_presentation` never reach `emoji_catalog_pack`, a codec or a fetcher, so
the host (not a panel package) reads payloads and hands data in.

| Add this | When |
| --- | --- |
| A fetcher and decoder adapter package of your own | Stickers, GIFs, custom emoji or any content that is not a unicode glyph |
| `flutter_md` and the `content_model/markdown.dart` helper | Sending and loading composer text as a markdown body |
| Your own `CollectionSource` / `SearchSource` | A kind of content other than emoji |

## 2. Composition root

Create these once, in this order. Each step needs only what the steps above it
made. Whoever creates an object disposes it, in the reverse order.

0. **Listener errors.** Before anything notifies, set `Listenable.onError`
   from `package:listen` (see below). The packages never set it.
1. **Key-value adapter.** `await SharedPreferencesKeyValueStore.open()`.
2. **Stores, loaded.** `KeyValueRecentsStore.load` and
   `KeyValuePreferenceStore.load` (one namespace per package, each awaited once
   at startup), `KeyboardHeightStore.open`. A store never exists unloaded.
3. **Asset cache.** `PageAssets.createScope(memoryPressure: SystemMemoryPressure())`.
   Add a `producer:` (an `AssetPipeline` over your fetcher and decoders) when
   content is more than unicode glyphs. Feed the clock your pause layers
   (section 8).
4. **Data sources.** `EmojiCatalogLoader(rootBundle.loadString)`, `EmojiCatalog`,
   `BundledKeywordSource`, `EmojiCollectionSource` and `EmojiSearchSource`
   over the stores. Pass the language set with the app language first.
5. **Optional bake parts.** The glyph probe, the glyph cache and the art
   version (section 7).

```dart
final storage = await SharedPreferencesKeyValueStore.open();
final (recents, preferences, keyboardHeights) = await (
  KeyValueRecentsStore.load(storage, namespace: 'recents'),
  KeyValuePreferenceStore.load(storage, namespace: 'preferences'),
  KeyboardHeightStore.open(storage),
).wait;

final memoryPressure = SystemMemoryPressure();
final assets = PageAssets.createScope(memoryPressure: memoryPressure);

final loader = EmojiCatalogLoader(rootBundle.loadString);
final catalog = EmojiCatalog(await loader.structure());
final emojiSource = EmojiCollectionSource(
  catalog: catalog,
  recents: recents,
  preferences: preferences,
);
final emojiSearch = EmojiSearchSource(
  catalog: catalog,
  keywords: BundledKeywordSource(loader),
  languages: const ['en'],
  recents: recents,
  preferences: preferences,
);
```

**`Listenable.onError` is yours to set.** A listener that throws during a
notification is reported to this one static hook, whose default rethrows: the
notification stops at that listener, the others are never called, and the
notifier is left mid-dispatch. Set it once at startup to report and not
rethrow, so one faulty listener cannot starve the rest or interrupt the code
that changed the state. The reference host routes it to
`FlutterError.reportError` (`reportListenerErrors`, installed by `bootApp`).
The same hook receives the debug assertions `package:listen` adds for a
notifier used after `dispose`. Typed events (the panel event, scroll events)
are `Stream`s instead, where a throwing listener is reported to the zone and
the others still run.

Other differences from the homemade primitive this repository used to have,
all in the seams' and controllers' dartdoc and in
[ADR 023](adr/023-data-layering-and-persistence.md):

- A listener added twice is called twice and must be removed twice.
- After `dispose`, `addListener` and a signal assert in debug builds
  (`removeListener` is always allowed). Dispose an owner once, outside its own
  listeners.
- A `package:listen` `Listenable` is not Flutter's: `ListenableBuilder`, a
  `Listenable.merge` of Flutter and `AnimatedBuilder` do not accept it. Read
  one in the widget tree with a small builder over `addListener` (the
  reference host has `ListenValueBuilder`) or adapt it (`ListenableBridge`).
  A file that imports Flutter imports `package:listen/listen.dart as listen`.
- There is no batching: a mutation that changes several things assigns the
  final value once.

The package set has no content resolver consumer in an emoji-only host: unicode
keys resolve to glyphs without one. Supply a `ContentResolver` (to the
`AssetPipeline`) when bare `document` or `external` keys can occur.

## 3. App-level scopes

Above every chrome widget, once. Order does not matter except that each scope
sits above what reads it.

```dart
ChromeThemeScope(
  palette: const ChromePalette.dark(),
  child: ChromeStringsScope(
    strings: myChromeStrings,                      // from your localisation
    child: ChromeMotionScope(
      speed: MediaQuery.disableAnimationsOf(context)
          ? ChromeMotionSpeed.instant
          : ChromeMotionSpeed.normal,
      child: GlassQualityScope(                    // liteMode: your low-power flag
        child: EmojiTabIconScope(
          child: AssetCacheProvider(scope: assets, child: app),
        ),
      ),
    ),
  ),
)
```

| Scope | Required | Notes |
| --- | --- | --- |
| `ChromeThemeScope` | Yes | A lookup with no scope throws in debug. Pick a palette (`light`, `dark`, high-contrast) or supply token groups |
| `ChromeStringsScope` | Yes | No default language. `ChromeStringsPresets` in `chrome_foundation/testing.dart` is for tests and demos |
| `ChromeMotionScope` | No | Without it, roles run at normal speed. Reduce motion is only this scope's `speed` (section 6) |
| `GlassQualityScope` | No | Default is the best strategy the device supports |
| `EmojiTabIconScope` | With `EmojiCategoryStrip` | Registers the strip's icon painters |
| `AssetCacheProvider` | With `ContentView`, `contentSpanBuilder()` without a `scope:`, inline embeds | Hands the host-created scope down; never disposes it |

The chat screen adds `GlassSourceScope` over its content and glass surfaces,
with a `GlassSource` around the message list, when sampled glass is wanted.

Material localisations must be available above the composer (its selection
menu uses them). `PanelShell` builds on `EditableText` and needs no Material
ancestor.

## 4. Per-chat controller set

A chat screen creates these when it opens and disposes them when it closes.
Creation order:

1. `ImeInput` (the keyboard port) and a `ValueNotifier<PanelWindow>` (from
   `package:listen`).
2. `ComposerTextController(inlineContentBuilder: contentSpanBuilder(scope: assets))`
   and `ComposerController(text: ...)`.
3. The strategies: `KeyboardReplacementStrategy(ime:, heights:, window:)`,
   `AnchoredPopupStrategy(style:, composerFocus:)`,
   `DockedStrategy(style:, composerFocus:)`. Register the kinds your policy can
   pick on your platforms; a kind with no strategy takes no space and draws
   nothing.
4. `PanelShellController(pages: [...], preferences:)`. One page per kind of
   content, in tab order.
5. `PanelPresentationController(shell:, strategies:, window:, preferences:)`.

```dart
final page = PanelPage(
  id: 'emoji',
  tab: const PanelTab(icon: ChromeIconId.emoji, labelKey: 'emoji'),
  capabilities: EmojiPagePolicy.pageCapabilities,
  builder: (context, host) => EmojiPage(
    host: host,
    source: emojiSource,
    searchSource: emojiSearch,
    preferences: preferences,
    entryOf: emojiSource.entryOf,
    assets: assets,
    deferChrome: pacedMount,        // section 7
  ),
);
final shell = PanelShellController(pages: [page], preferences: preferences);
```

`PanelStrings.tabLabel` must answer the `labelKey`. Dispose in reverse:
presentation, strategies, shell (it disposes the page controllers it holds,
among them the emoji page's atlas host), the IME port and window value, the
composer and its text controller. Nothing here disposes the app-level objects
from section 2.

### The one panel event handler

`PanelShellController.events` is the single outward effect. The panel inserts
nothing and writes no recents; the host does both.

```dart
void onPanelEvent(PanelEvent event) {
  switch (event) {
    case ContentPicked(:final key, :final kind, :final source):
      if (key is ContentKey$Unicode && kind == SemanticKind.unicodeEmoji) {
        composer.insertContent(
          InlineContentRef(key: key, alternativeText: key.sequence),
        );
      }
      unawaited(recents.record(key, kind: kind, source: source));
    case BackspaceRequested():
      composer.backspace();
    case ClearRecentsRequested(:final kind):
      unawaited(confirmThenClear(kind));
    case ContentCopyRequested(:final key):
      if (key is ContentKey$Unicode) {
        unawaited(Clipboard.setData(ClipboardData(text: key.sequence)));
      }
    case RecentRemoveRequested(:final key, :final kind):
      unawaited(recents.remove(key, kind: kind));
    case SearchOpened() || SearchClosed() || ActionInvoked() || PageChanged():
      break;
  }
}

final panelEvents = shell.events.listen(onPanelEvent); // cancel with the screen
```

`events` is a synchronous broadcast `Stream`. A handler may answer an event by
calling the shell (selecting a page, closing search): the events that causes
are delivered after the one being handled has reached every listener, before
the call returns. Cancel the subscription when the chat screen goes away.

`record` ignores `PickSource.search`; the host decides that a pick counts.

A right click on a recent (the pointer arrangement of a popup or a docked
section) opens a menu whose items arrive as `ContentCopyRequested`,
`RecentRemoveRequested` and `ClearRecentsRequested`. The panel copies nothing
and removes nothing: the host does, and asks the user before clearing. The menu
labels are `PanelStrings.copyAction`, `removeRecentAction` and
`clearRecentAction`, supplied with the rest of the strings. A finger keeps the
clear button in the recents header instead. Which emoji have variants, and
whether the user has chosen one, is the page's business; the host only
supplies the `PreferenceStore` the page remembers it in (choosing the emoji as
it is is remembered as the base itself).
A host that lists the recents through a `DeferredRecentsStore` view (so a pick
does not reorder the grid under the pointer) routes `remove` and `clear` through
the view: the emoji leaves the list at once and nothing else in it moves.

## 5. Layout and the keyboard

### Occupancy and extent into the viewport

The host owns aggregation ([host insets](architecture/14-host-chrome-insets.md)):

```text
bottomPadding = composer.extent + presentation.occupancy.bottom
inlineEnd     = presentation.occupancy.inlineEnd   // layout, mirrored in RTL
```

`composer.extent` already holds the composer's own bottom pad; a keyboard
presentation's `occupancy.bottom` already holds the live keyboard. Do not add
either twice. Until the composer publishes its first extent (zero), reserve a
seed so the first frame is not empty.

Mount `PanelPresentationView(controller: presentation)` in the box the host
reserves. Where the panel replaces the keyboard that box is
`SizedBox(height: occupancy.bottom)` under the composer. Where it is a popup or
dock, fill the area it floats over; apply `inlineEnd` as end padding on the
chat region (a dock takes width, it does not cover the chat).

### IME port

The presentation package reads no platform channel. The host feeds one port,
`ImeInput`, frame by frame:

```dart
ime.report(ImeSample(
  height: keyboardHeight,        // with the bottom safe area counted in; zero when hidden
  animating: keyboardIsMoving,   // honest: a settled reading ends the hand-off
  safeAreaBottom: viewPadding.bottom,
));
```

**The height counts the bottom safe area.** The slot measures the keyboard as
the space it takes at the bottom of the window. iOS reports it that way (the
distance from the keyboard's top edge to the screen's bottom); the Android
inset plugin reports the IME without the system bars. A host whose platform
leaves the band out adds it back while the keyboard shows any height, and
leaves zero as zero. Skipped, the composer sinks behind a keyboard that is the
band taller than the slot believes. The example's `SoftKeyboardPort` states
which kind of platform it is on (`heightsIncludeSafeArea`).

Report `animating` truthfully. The hand-off to the keyboard waits for a
settled reading (`animating` false, height up) and closes cold after one
second. Do not filter or smooth the samples.

While a keyboard-replacement panel is on screen, give the composer
`setSoftKeyboard(SoftKeyboardMode.suppressed)`; every other time `auto`. The
field then keeps focus and caret without raising the keyboard. To return to the
keyboard call `presentation.hide(waitForIme: true)`, keep composer focus, close
search, and ask the platform to show the keyboard once on the next frame.

Declaring no soft keyboard does not lower one that is already showing. When the
panel opens over a raised keyboard, ask the platform to hide it once after the
frame (focus stays in the field); the slot's replace hand-off keeps the space
meanwhile.

### Recents while the panel is open

The panel lists the recents first, so a pick that updated them at once would
reorder the grid under the finger that is picking from it. Give the panel's
sources a `DeferredRecentsStore` over the real store, record picks in the real
store, and `commit()` the view when the panel opens and when search ends. A
clear commits at once.

### Composer wiring

Build a `ComposerSpec` from chat state whenever it changes (header, actions,
busy). Every `ActionDescriptor` needs a `semanticLabel`; mark the action that
submits `primary`. Pass the spec to `ComposerView`, and pass
`safeAreaBottom: keyboard.composerSafeInset.value` while a keyboard presentation
owns the bottom band (null otherwise keeps the default pad).

### Popup anchor

For an anchored popup, tell the controller where the composer is, in the
coordinates of the box the presentation view fills, after layout and on every
composer extent change:

```dart
presentation.anchor(composerRect);
presentation.updateWindow(PanelWindow(width: size.width, height: size.height)); // resize, rotation
```

Wrap the composer in `AnchoredPopupActions(controller: presentation, ...)` under
`Shortcuts(shortcuts: AnchoredPopupShortcuts.standard)` so Escape and the toggle
shortcut work while focus is in the composer. A popup that holds the shell
must bind Escape itself (the shell forwards `DismissIntent` outward only after
it has closed search).

**The toggle and the composer.** Two wrappers connect the popup to the
composer, neither of which the composer package knows about:

1. The panel button in `AnchoredPopupToggleRegion(strategy:, controller:)`, put
   there through `ActionDescriptor.wrap` (a widget the composer builds around
   the rendered button). A mouse over it opens the popup at once; its press is
   never an outside press; and the popup's hover area reaches down to its top
   edge, so place the toggle under the popup (at the composer's end edge, where
   the popup anchors) and the pointer crosses without leaving both.
2. The composer in `AnchoredPopupExemptRegion(strategy:)`: a press inside it
   does not dismiss the popup, so a click back into the input to keep typing
   leaves it open. Every other outside press dismisses at once.

The button's click is the host's: `popup` shown and the window can dock ->
`presentation.dock()`; docked -> `undock()`; shown and cannot dock -> `hide()`;
else `show()`. Give the descriptor `active: true` while docked and keep the one
glyph in every state of a desktop kind.

**Holds.** Anything that must keep the popup open while the pointer is
elsewhere takes `presentation.holdAutoHide()` and releases the hold when it
closes. Search focus is not one. The panel's own menu and variant picker stand
outside its box, and pages and the shell cannot reach the presentation, so the
host forwards them: listen to `shell.autoHideHolds` (a count of the pages'
holds) and keep one presentation hold while it is above zero.

```dart
PanelAutoHideHold? hold;
void onPageHolds() {
  if (shell.autoHideHolds.value > 0) {
    hold ??= presentation.holdAutoHide();
  } else {
    hold?.release();
    hold = null;
  }
}
shell.autoHideHolds.addListener(onPageHolds); // release the hold on dispose
```

### Back

Route the system back press to `presentation.handleBack()`: search closes first,
then the panel. A host that raises the keyboard over an open search field may
hide the keyboard before calling it.

## 6. Accessibility, text and motion

**Reduce motion.** No chrome package reads the platform flag. Map
`MediaQuery.disableAnimationsOf(context)` to `ChromeMotionSpeed.instant` in
`ChromeMotionScope`; every role then runs at zero duration. Also pass your
low-power flag to `GlassQualityScope(liteMode:)` and set the clock's
`PlaybackPauseLayer.lowPower`.

**Text scale.** The shell's search field and bottom bar clamp the platform text
scale at 1.3x (their pill heights are fixed). The composer field and the
strings follow the platform scale; cap it with
`MediaQuery.withClampedTextScaling` above the composer if the island must not
grow past a limit. Catalog section headers are fixed-extent and unscaled on
purpose: the grid's layout reserves one header height, and the viewport paints
the title at that size whatever the platform scale. Nothing is lost for a
reader who needs larger text or a screen reader: every leaf and every header
carries its spoken name in the semantics tree, and the search field scales as
above.

**Strings and directions.** Every user-visible string comes from
`ChromeStrings` (required constructor parameters, so a missing one is a compile
error; run `describeChromeStrings` in a test to catch empty ones). Directional
primitives mirror the layout under a right-to-left `Directionality`; content
(glyphs, stickers, GIFs) is never mirrored.

**Screen readers.** Leaves expose windowed semantics labelled by the
descriptor's spoken name. The shipped emoji sources set none, so a screen
reader reads the glyph itself; a host that wants CLDR spoken names reads them
from the keyword pack (`EmojiKeywordPack`) and puts them on its descriptors.

## 7. Emoji specifics

**Baked glyphs.** On platforms that bake, pass `EmojiPage.atlasHostFactory`: a
function that builds a `GlyphAtlasHost` from the parts only the host has (a
`BakeFrameSource` such as `SchedulerBakeFrameSource(view:)`, the page's
`devicePixelRatio`, `glyphBoxExtent`, `visible` and `opening` listenables,
memory pressure, optional `GlyphAtlasPersistence` and glyph probe observer).
The page plans the atlas from its collections, registers it on the shared
`assets` scope while mounted, and clears it after. Without a factory (the web)
glyphs draw as text through `PageAssets.createScope`'s `TextGlyphProducer`.

**Glyph probe.** To hide emoji the system cannot draw, build a
`MissingGlyphProbe`, pass it as `glyphSupport:` to both sources, plan the
atlas over the unfiltered catalogue (`EmojiPage.planner`) so a verdict never
changes the cache key, and bridge the bake to the probe with
`CallbackGlyphBakeObserver`. `emoji_data` and `catalog_assets` never import
each other, so this composition is the host's. See the `emoji_data` README.

**Paced mount.** A panel that grows into free space mounts its page over a few
frames: pass `deferChrome: true` to `EmojiPage` and `deferSearchField: true` to
`PanelShell` while the panel opens with an animation, and leave both off when
the panel replaces a keyboard already on screen (`KeyboardReplacementStrategy.keyboardIsUp`).

## 8. Message bodies, connectivity and pause layers

### `RichText` and markdown

Bodies stay markdown ([ADR 017](adr/017-body-linkify-host-invoked.md)). The
composer produces a `RichText`; the host converts it at two moments with
`RichTextMarkdown` from `package:content_model/markdown.dart`:

- **Send or save an edit:** `RichTextMarkdown.encode(composer.richText)`.
- **Load a message into the composer:** `composer.restore(RichTextMarkdown.decode(body))`.

Inline content travels as `![alt](unicode:1F44D)` (`ContentKey.encoded`
spelling); mentions as `[@name](mention:id)`. `RichText` shares its name with
Flutter's widget: `import 'package:flutter/widgets.dart' hide RichText;`.

The viewport does not paint inline embeds yet (a follow-up recorded in ADR 029),
so a host that wants emoji visible in bodies today strips unicode inline content
to its characters before `encode` and keeps the `![alt](scheme:id)` form only for
other content. Neither helper detects bare URLs or names; linkify is a separate
host step.

### Connectivity

The cache never touches the network. When the connection returns, call
`assets.connectivityRestored()` from your connectivity listener: attempts that
failed for a transient reason are retried for entries still attached. A host
with no fetcher (unicode glyphs only) has nothing to retry.

### Pause layers

Set host-owned layers on `assets.clock.setPaused(layer, paused: ...)`:
`routeMoving` while a route transition runs, `fastScroll` during a fling,
`lowPower` from the battery saver, `surfaceHidden` when the app is hidden.
Animated content stops playing while any layer is set.

## 9. Ownership and lifetime

| Object | Created by | Lifetime | Disposed by |
| --- | --- | --- | --- |
| `KeyValueStore` adapter, stores, fetcher, decoders, resolver | Host | App or account | Host |
| `AssetCacheScope` | Host | App-wide | Host (scopes and `AssetCacheProvider` never dispose it) |
| Pause layers, connectivity signal | Host, fed into the cache | App | Host |
| Emoji and other data sources | Host | Account | Host |
| `ChromeThemeScope`, strings, motion, glass quality | Host | App, plus nested per-chat scopes | Host |
| `GlassSourceScope` | Chat screen | Chat screen | Chat screen |
| `ComposerController` (and the focus node, scroll controller and text controller it was handed) | Chat screen | Chat screen | Chat screen |
| `PanelShellController`, `PanelPresentationController`, the strategies, `ImeInput` | Chat screen | Chat screen | Chat screen |
| Page controllers (catalogue offset, atlas host) | The shell's registry | Chat screen | The shell controller |
| `ComposerSpec`, the page list | Host, rebuilt from chat state | Chat screen | Host |
| Panel event handler (a subscription to the shell's `events`), inset aggregation | Host | Chat screen | Host (cancel the subscription) |
| `Listenable.onError` | Host | App | Never reset |

The creator disposes. A package never disposes what it was handed; where a
class creates a part itself (the composer's default focus node, the shell's
default registry) its dartdoc says so.

## 10. What changes for a sticker, GIF or custom emoji host

Everything above stays. Add:

1. **Fetcher and decoders.** A `ContentFetcher` that owns network, file refs and
   the disk tier, and one `Decoder` per `MediaForm` it shows (still, vector
   animation, video), registered in a `DecoderRegistry`. Build
   `AssetPipeline(fetcher:, decoders:, resolver:)` and pass it as the scope's
   `producer:`. Run the `runAssetFetcherContract` and `runDecoderContract`
   suites against your adapters.
2. **Sources.** A `CollectionSource` (sets, trending, recents) and a
   `SearchSource` for each kind. Failure is a state on the collection, never an
   exception. Hand descriptors over eagerly where known (`pipeline.know`).
3. **A page.** `CatalogPage` with a `CatalogPagePolicy` subclass: layout
   (`SectionLayout.grid(spanCount:, cellAspect:)`), what a tap picks, long-press
   preview, header actions, a top strip. The shell gets one more `PanelPage`
   with its `PanelTab` (a `ChromeIconId`, and a `PanelStrings.tabLabel` answer).
4. **Events.** Handle `ContentPicked` for the new `SemanticKind` (send a
   sticker, insert a GIF) and record it under its own kind.
5. **Presets.** `AssetPresets` for stickers in the panel and inline content;
   animated content gets the shared playback clock and its pause layers.
6. **Connectivity.** Wire `connectivityRestored()`.

The atlas stays an emoji concern: stickers and GIFs bind through the cache's
fetch and decode path and never touch it.

## 11. Verifying your host

- `scripts/check` is the gate this repo runs; a host app runs `dart analyze`
  and its own tests.
- Use the fakes (`content_model/testing.dart`, `panel_shell/testing.dart`,
  `panel_presentation/testing.dart`, `catalog_assets/testing.dart`) in host
  tests; production code never imports a `testing.dart`.
- For each seam you implement, run the matching `run...Contract` suite from the
  package that defines the seam.
- Device-only checks (keyboard hand-off frame budget, glass fallback matrix,
  bake cost) are in [qa-keyboard-handoff](panel-presentation/qa-keyboard-handoff.md),
  [glass-device-checklist](chrome/glass-device-checklist.md) and
  [qa-glyph-cache](panel-catalog/qa-glyph-cache.md); none has a measured result
  yet.

## 12. Reference host map

The demo app under `example/` is the reference. It registers the emoji page
only, has no fetcher, decoder or resolver, and does not use the hover-open
toggle region.

| Step | File |
| --- | --- |
| Composition root, disposal | `example/lib/src/app/app_services.dart` |
| `Listenable.onError` policy, installed at boot | `example/lib/src/app/listener_errors.dart`, `example/lib/src/app/boot.dart` |
| App scopes | `example/lib/src/app/app_chrome.dart` |
| Per-chat controller set, event handler, back, hand-off | `example/lib/src/features/chat/input/chat_input_set.dart` |
| Emoji page composition (atlas host factory, planner) | `example/lib/src/features/chat/input/emoji_panel_page.dart` |
| Composer spec | `example/lib/src/features/chat/input/chat_composer_spec.dart` |
| Inset aggregation | `example/lib/src/features/chat/utils/chat_viewport_insets.dart` |
| IME readings and keyboard commands | `example/lib/src/common/soft_keyboard_port.dart` |
| Glyph probe and atlas wiring | `example/lib/src/common/emoji_glyph_probe.dart` |
| `RichText` and markdown | `example/lib/src/features/chat/utils/chat_body_markdown.dart` |
| Popup anchor, composer view | `example/lib/src/features/chat/widgets/chat_composer.dart` |
| Panel box and shortcuts | `example/lib/src/features/chat/widgets/chat_bottom_chrome.dart` |

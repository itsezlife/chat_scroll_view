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
| `AssetCacheProvider` | With `ContentView`, `ContentViewSpans.builder()` without a `scope:`, inline embeds | Hands the host-created scope down; never disposes it |

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
2. `ComposerTextController(inlineContentBuilder: ContentViewSpans.builder(scope: assets))`
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
`clearRecentAction`, supplied with the rest of the strings. A finger's long
press on a recent asks the same (`ClearRecentsRequested`), and the recents
header has no button. Which emoji have variants, and
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
bottomPadding = composer.extent + max(safeBottom, presentation.occupancy.bottom)
inlineEnd     = presentation.occupancy.inlineEnd   // layout, mirrored in RTL
```

`composer.extent` leaves out the composer's bottom safe-area pad: the host adds
the bottom band itself, as the larger of the safe area and the occupancy. A
keyboard presentation's `occupancy.bottom` already holds the live keyboard,
safe area included, so the keyboard is not added twice. Computing the band
from the occupancy matters: the extent is measured after layout and arrives a
frame late, so a sum that relied on the composer's own pad to grow as the slot
shrinks dipped by up to the band at the end of every close. Until the
composer publishes its first extent (zero), reserve a seed so the first frame
is not empty.

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
settled reading (`animating` false, height up) to stand for a short
confirmation (`KeyboardReplacementTuning.settleConfirmation`) and closes cold
after one second. Do not filter or smooth the samples; the slot discounts the
lone settled spike a crossing hide and show report.

The panel button acts on what the previous press asked for, not on how far
its motion has come. A press while the panel leaves for the keyboard (search
still shrinking, or the keyboard still rising) keeps or brings back the panel
and lowers the keyboard again; the toggle's glyph follows the press at once.

While a keyboard-replacement panel is on screen, give the composer
`setSoftKeyboard(SoftKeyboardMode.suppressed)`; every other time `auto`. The
field then keeps focus and caret without raising the keyboard. To return to the
keyboard, in this order: set `auto` and call `composer.requestKeyboard()`; if
search is open, wait until the composer holds focus, close search and wait for
the slot to stop moving (`KeyboardReplacementStrategy.animating`); then call
`presentation.hide(waitForIme: true)`. Search collapses to the panel's height
first and the keyboard takes the slot from there; done at once, the panel
vanishes from its expanded height and the keyboard drops while focus moves.
For a tap on the field, lift the suppression on the press
(`ComposerView.onFieldPointerDown`) and put it back if the press ends without
a tap, so the tap's focus attaches with the keyboard allowed.

Android keeps the input type a field attached with, so a composer that took
focus while suppressed holds a connection with no keyboard type. Changing the
mode alone raises nothing: a panel closed with back leaves focus in the field
and the keyboard down. `composer.requestKeyboard()`, the first step above, is
what raises it: the field focuses, or attaches again with the current type,
after the frame. A tap on the field does the same by itself.

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

Set `ComposerSpec.messageLengthLimit` from the server's `message_length_max`
(4096 until it publishes one): the composer counts code points of the plain
text, shows the remaining count at 100 or fewer and refuses the `primary`
action while it is negative. To send, apply the host's own trim (skip it for an
emoji-only text), encode `composer.sendableText` (not `richText`: it downgrades
the mentions this draft did not resolve; pass `confirmMention` to confirm
pasted ones against your users) with `RichTextMarkdown.encode`, and `clear()`.
A draft is the markdown of `richText`, written to the `KeyValueStore` under the
chat id (and the edited message's id) debounced on change, removed on send, and
loaded with `restore(RichTextMarkdown.decode(...))`.

### Formatting menu, shortcuts and suggestions

The selection menu is the composer's own; the host chooses what it offers and
supplies the rest through `ComposerSpec`:

- `formatting` is the set of items (`ComposerFormattingOption.all` offers every
  one; the list items still wait for `ComposerTextController(lists: true)`, and
  an item whose command cannot apply to the selection is left out, not greyed).
  Labels come from `ChromeStrings.formatting`.
- `linkPrompt` is your dialog for Create and Edit Link. It gets the composer's
  `BuildContext` and the current target (null when creating) and completes with
  the URL, or null to cancel. The shortcut for links asks the same prompt.
- `backPriority` takes the system Back ahead of the soft keyboard while the menu
  is open. Back then closes the overflow page, then the menu, and only after
  that anything below. Route it into the host's own back-claim stack and return
  the function that gives the claim back.

The default key map follows the platform (`ComposerShortcutPolicy`); Ctrl or
Cmd with B, I, U and K format, with Shift also X, M, P, `.`, N, 7 and 8. A host
that wants other keys passes a map to `ComposerView.shortcuts`; there is no
merging, so start from the policy's map and change what differs:

```dart
final defaults = ComposerShortcutPolicy.forPlatform(defaultTargetPlatform);
final shortcuts = {
  for (final MapEntry(:key, :value) in defaults.shortcuts.entries)
    // Bold on Ctrl+Shift+B instead of Ctrl/Cmd+B.
    if (value is! ToggleStyleIntent || value.style != EntityStyle.bold)
      key: value,
  const SingleActivator(LogicalKeyboardKey.keyB, control: true, shift: true):
      const ToggleStyleIntent(EntityStyle.bold),
};
```

A chat leaves lists off; a form field that wants them builds its controller
with `lists: true` (the reference host's notes field does).

Three things stay the host's, because they are feedback or data:

- **Apply formatting.** `ComposerController.onPaste` reports each paste. For a
  plain paste (`wasRich` false) whose `RichTextMarkdown.decode(text)` differs
  from `RichText.plain(text)`, offer to apply it (the reference desktop
  client's toast, nine seconds): applying replaces the reported range with the
  decoded text through `ComposerTextController.replaceRange`. Any edit
  withdraws the offer, and it never holds the paste back.
- **Suggestions.** Register `ComposerQueryKind`s (`@`, `#`), build the panel from
  `composer.query` (the reference host puts it in the header strip with
  `ComposerHeader.suggestion`), and on a pick call `replaceQuery` with a real
  mention atom or hashtag. Answer `confirmMention` from your own members so a
  pasted mention survives the send.
- **Link preview.** Listen to the composer's text, wait one second after the
  last keystroke (none when the text jumped by more than two characters or the
  caret follows a space), detect with `DetectionPolicy.urlsOnly` on a copy and
  show the first URL in the header strip. The listener writes nothing into the
  composer.

### Popup anchor

For an anchored popup, tell the controller where the composer is, in the
coordinates of the box the presentation view fills, whenever it moves: read it
after every frame and report a change (an equal rectangle is ignored). A
composer extent change and a rebuild are not enough: a dock that comes or goes
moves a composer held at its greatest width without either, and a popup opened
later would anchor where it had been.

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
error; run `ChromeStringsSnapshot.of` in a test to catch empty ones). Directional
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

Bodies stay markdown ([ADR 034](adr/034-rich-text-wire-and-persistence.md)). The
composer produces a `RichText`; the host converts it at two moments with
`RichTextMarkdown` from `package:content_model/markdown.dart`:

- **Send or save an edit:** `RichTextMarkdown.encode(composer.richText)`, after
  detection (next section) and after rewriting every mention the host did not
  resolve in this draft to a `Username`.
- **Load a message into the composer:** `composer.restore(RichTextMarkdown.decode(body))`,
  after stripping detected entities.

Inline content travels as `![alt](document:5368)` (`ContentKey.encoded`
spelling; `unicode:1F44D` is legal, but a host sends a unicode emoji as its
characters, [Emoji-only messages](#emoji-only-messages)); mentions as `[@name](mention:id)`, usernames as
`[@name](username:name)`, hashtags as `[#tag](hashtag:tag)`. `RichText` shares
its name with Flutter's widget: `import 'package:flutter/widgets.dart' hide RichText;`.

The viewport paints inline embeds ([ADR 029](adr/029-host-integration.md)),
spoilers and mentions ([Inline embeds, spoilers and mentions](#inline-embeds-spoilers-and-mentions)).
Neither `RichTextMarkdown` nor the viewport detects bare URLs, names or tags;
detection is a separate host step.

The length budget is a code-point count of `RichText.plain`, not of the
markdown source: set `ComposerSpec.messageLengthLimit` from the server
configuration and let the composer count. A server guard on raw source and its
scheme and mention checks are described in the wire ADR; after every send or
edit, replace the optimistic message with the body the server returns.

### Detection

Detection ([ADR 017](adr/017-body-linkify-host-invoked.md)) turns bare URLs,
emails, `@name` and `#tag` in a `RichText` into link, `Username` and `Hashtag`
entities. It is a pure `content_model` transform,
`EntityDetection.apply(richText, policy)`, that the host calls at four moments
and the viewport never calls:

| Moment | Step |
| ------ | ---- |
| Send | Rewrite unresolved mentions, **detect**, then encode. The stored body carries the links every other viewer receives. |
| Receive | When you build the message model, decode the body. If it has no link-class entity (link, mention, username, hashtag), detect once and keep the result with the model. A body that has any such entity is trusted and not detected again. Never detect in a build or paint method. |
| Edit | Decode, strip the detected entities back to text (the inverse operation in `content_model`), restore into the composer. Saving detects again, so a stored body round-trips. |
| Link preview | Optional. Listen to the composer text, debounce, detect with `urls` only to pick the URL to preview, and show the result in the composer's header slot. Fetching and caching the preview is yours. |

Policy is yours: a `DetectionPolicy` chooses the families (urls, usernames,
hashtags) and the URL schemes. A host that resolves usernames only on its own
terms leaves `usernames` off and gets plain text for `@name`. Taps arrive as
inline hits (`mention`, `hashtag`, `link`); the hit says whether a mention is a
resolved user or a typed username, and what a tap means is the host's. The
composer does not detect while typing; offer `@` and `#` suggestions through
input queries and insert a real mention or hashtag on pick.

If your server detects on ingest, nothing changes in the client: it already
reconciles with the stored body.

### Inline embeds, spoilers and mentions

What the host wires so a markdown body paints and reports the inline layer
([ADR 029](adr/029-host-integration.md), [ADR 037](adr/037-spoiler-and-mention-inline-styles.md)):

1. **Embeds.** Create one `ContentEmbedResolver(scope: assets)` per chat screen
   and pass it as `ChatMarkdownBody.embedResolver`. Keep the instance: a
   different one disposes and re-resolves every embed of the body. A `document:`
   key the cache cannot produce keeps its placeholder (no failed stage is ever
   shown); a target no resolver knows (a scheme that is not content) paints its
   alt text. Do not filter image spans out of the markdown theme: that hid them
   before the viewport painted embeds.
2. **Embed taps.** Pass `ChatSelectionController(handlesEmbedHits: true)` when
   `ChatEmbedActivated` means something to the host (a pack sheet). Without it
   an embed is only part of the text.
3. **Spoilers.** The facade holds which messages are revealed, so it survives a
   row leaving and re-entering the viewport. Pass `spoilerClock: assets.clock`
   so the dust moves on the cache's frames and pause layers. A host that
   follows reduce-motion creates the `MarkdownSpoilerController` itself
   (`spoilers:`) and sets `animate` from `SpoilerTokens.particles.tickAt(speed)`;
   the particle colour follows the hidden text, and the engine takes no other.
   While a message selection is live a tap toggles the row and the spoiler
   stays hidden (the facade drives `spoilers.tapReveals`; do not write it). A
   press held past `spoilers.tapTimeout` (500 ms) is a long press and reveals
   nothing; a desktop host with a mouse sets `tapTimeout = null`.
4. **Mentions, usernames and hashtags.** Colour them with
   `MarkdownThemeData.mentionColor` (they follow the link colour otherwise).
   Taps are `ChatResolvedMentionActivated` (with the user's `id`) or
   `ChatUsernameMentionActivated` (no id), both a `ChatMentionActivated`,
   and `ChatHashtagActivated`; a link inside a hidden spoiler reveals it and
   reports nothing, and a tap that reveals a spoiler is not an idle message tap
   (`onIdleMessageTap` stays silent for it; the next tap is).

### Emoji-only messages

A message of nothing but emoji is shown without a bubble, large
([ADR 038](adr/036-emoji-only-message-presentation.md)). The viewport lays out
`ChatEmojiBody`; the host decides when:

1. **Classify once**, when the message model is made:
   `EmojiOnlyText.of(RichTextMarkdown.decode(body))` gives the emoji and the
   line breaks between them, or null. The viewport never re-detects, and a body
   is not classified in a build method. Unicode emoji travel as characters, not
   as `unicode:` inline content, which would disqualify the message.
2. **Pick the platform's policy once**, `ChatEmojiPolicy.forPlatform()`
   (`$Android`, `$Ios`, `$Desktop`; web is desktop), and use that one policy for
   the body and for the chrome around it. The three differ almost completely
   (sizes, inset, where the time and the reply sit, what a right-to-left chat
   mirrors), so the platform is a strategy, not a flag.
3. **Weigh the host's facts**: the **large-emoji setting** (on until the user
   turns it off, kept in the `KeyValueStore`), the message having no media (a
   link preview counts as media), and what the policy says: on Android the
   chat's permission gates the feature (stickers allowed in the chat, or the
   user is an admin; `gatesOnStickerPermission`), on desktop an enlarged run
   holds at most three regular emoji (`admits`; more is an ordinary bubble). Fold
   them into one decision and listen to it, so the setting applies while a chat
   is open.
4. **Mount `ChatEmojiBody`** instead of the bubble with:
   - `embedFactory: (content, preset) => ContentEmbed(scope: assets, content:
     content, preset: preset)`, stable for the screen. It is not an
     `InlineEmbedResolver`: the body sizes by count with presets of its own;
   - `sticker`: for a lone emoji, the document it is shown as, from the host's
     own `unicode` to `document` map (an animated-emoji pack's) or the custom
     emoji's own document; none gives the text layout;
   - `playback` (`ChatStickerPlayback`): how the sticker plays, from the asset
     kind and the user's animation settings. Null is the reference default (a
     lone unicode emoji plays once and rests on the first frame, a custom emoji
     loops). The body reads no setting;
   - `playLedger` (`ChatStickerPlayLedger`): the played-once memory, **per open
     chat** (not in the cache or the body, not persisted). The body asks it
     when it mounts, keeps the answer for that mount and records the play when
     the animation is playing, so a recycled row mounts again and rests. A
     tap replays through the body;
   - `isActive`: the one visibility input, row visibility combined with app
     lifecycle, route focus and the power policy;
   - `tapPolicy`: only to change the replay tap slop (zero: a tap must land on
     the drawn sticker) or the mobile long press;
   - `policy`: the one picked above;
   - `hasHeader` when a reply or forward header is shown with the text layout:
     the text then wraps by the policy's rule (Android 65 % of the parent width,
     iOS 45 pt less, desktop unchanged);
   - `parentWidth` when the chat is not the whole window (the width that share is
     of; the viewport's by default);
   - `bottomReserve`: the strip the chrome needs under the items.
5. **Place the chrome** from the body's geometry, per platform. Ask
   `ChatEmojiBody.geometryFor` (the same code the body lays out with, so a host
   places chrome before the body is built) for the box, the text rectangle and
   its trailing edge, the last line, the sticker's art rectangle (inside the
   policy's inset: none on Android and desktop, 10 pt on iOS) and the reserved
   strip. The pill, header and reactions then go where the platform puts them:

   | | Android | iOS | Desktop |
   | --- | --- | --- | --- |
   | Time | always; a strip under the text (3 dp gap, 17 dp pill, 3 dp), over the sticker's bottom | always; 4 pt inside the frame's end and bottom | beside the content (incoming) or under or over it (outgoing); on hover, last own, sending, failed; an outgoing large emoji always |
   | Pill | 17 dp, radius 12, 6 dp padding, 12 dp text | fully rounded, 11 pt | radius about 6, 8 x 2 padding, 13 px |
   | Ticks and edited | 12 dp checks 4.8 dp apart, clock, error; `edited 09:05` is one string | 11 x 9 pt vector checks 6 pt apart; one string | Android's glyphs; one string |
   | Reply | above the text, beside the sticker | beside both, at the screen edge away from the message | beside when it fits, else above |
   | RTL | no mirror | no mirror | mirrors wholly |
   | Selection | the viewport's row tint | checkbox only | glyphs recoloured |

   The service colour behind pill and headers is derived from the chat's
   wallpaper, a **host input** (its average colour; none gives a documented
   default). The example's `EmojiChrome` is a working, tested implementation; it
   is host code, not a package, and its divergences are the table in the ADR.
6. **Do not trim on send** a draft that is emoji-only (`EmojiOnlyText.of` over
   the text once unicode inline content is dropped to characters): the blank
   lines and spaces around the emoji are the sender's arrangement.
7. **Taps** are `ChatEmbedActivated` for a custom emoji and `ChatStickerActivated`
   for the lone sticker; what they mean is the host's.

#### Sticker interaction seams

A tap on the sticker is a replay (the body's, never rewinding a running pass)
and an interaction (the host's). The viewport ships the seams, not the effect:

- **The event**: `ChatStickerActivated` carries the emoji (`content`,
  `isCustomEmoji`), the message id, the drawn `stickerRect` in global
  coordinates and `tapTime` on the facade's injected `monotonicClock`, for every
  tap on a hit, playing or not. A long press is told too and carries no effect.
  Whether the message is the user's, the chat kind and the gates (a private
  chat, not Saved Messages, not secret, sent) are the host's facts.
- **Where to draw**: `ChatSelectionController.stickerRectOf(messageId)` is the
  live rectangle, null for a row that shows no sticker; read it while the
  effect plays, since the row scrolls. The effect is three times the sticker
  and crosses neighbouring rows, so the host draws it above the list.
- **A peer's interaction**: `playRemoteInteraction(messageId)` restarts the
  sticker and returns the rectangle, or null (not mounted, scrolled out,
  inactive) so the host drops it and sends no acknowledgement.
- **Batching and the wire** are the host's: a debounce after the last tap
  (500 ms) bounded by a window from the first (1.0 s), offsets in seconds from
  the first tap, a random effect index from an injected source, and the JSON
  `{"v":1,"a":[{"i":n,"t":seconds}]}` carried with the emoji and message id.
  Keep the window at 1.0 s so every offset is within `[0, 1]` and increasing,
  which the strictest receiving client requires. The example's
  `StickerInteractionStub` shows the batch it would send and sends nothing.

Surfaces that share one cache entry (the same content at the same size) share
one playback and replay together; two identical emoji-only messages visible at
once play in step.

### Drafts

A draft is markdown in the wire's dialect, kept in the host's
`KeyValueStore`:

- **Key:** derived from the chat id, with the id of the message being edited
  stored beside it when an edit is in progress.
- **Write:** debounced on composer change, from
  `RichTextMarkdown.encode(composer.richText)` (no detection: a draft is what
  the user typed).
- **Restore:** when the chat opens, `composer.restore(RichTextMarkdown.decode(draft))`;
  restore into edit mode when an edited message id is stored.
- **Clear:** on send, and when an edit is cancelled or saved.

Do not store `RichText.toJson` as a draft; it is the rich clipboard's payload.
A later server draft sync carries the same string.

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
   `producer:`. Run the `AssetFetcherContract.run` and `DecoderContract.run`
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

## 12. Migrating a host from a pre-ADR 020 pin

A host that pins a commit from before the package split ([ADR 020](adr/020-package-topology.md):
one chrome package plus the root package) usually also vendors a markdown
renderer, a markdown text editor and a forked editable. Move in four steps, each
shippable alone. Do not combine them: the riskiest round trip (lists in stored
text) must not ride with the chat send path.

| Step | Lands | Gate |
| ---- | ----- | ---- |
| 0. Chrome | The host moves off the old chrome package onto the packages of sections 1 to 11 (composition root, scopes, composer spec, panel presentation, theme tokens). The composer renders its stock field and sends plain text. | The chat renders and sends |
| 1. Dependencies | The markdown engine comes from its fork by git ref ([ADR 035](adr/035-markdown-engine-fork.md)); the vendored renderer is deleted. The vendored markdown editor and the forked editable are frozen into one legacy package of the host's own, because a form field still uses them. The composer, `composer_editable` and `content_model` come by git ref. No `dependency_overrides` outside this repository's workspace root. | Analyze is clean; existing markdown renders unchanged (goldens) |
| 2. Chat rich text | The chat composer runs on `ComposerTextController`. Send is detect then encode; edit-load is decode, strip detected entities, restore; the budget counts plain code points ([ADR 034](adr/034-rich-text-wire-and-persistence.md)); every raw-length cut on the send and edit paths and the host's bare-URL rewrite helper are deleted; bodies decode their links and entity-less bodies get the receive-time fallback ([Detection](#detection)); the selection menu is on; drafts, if adopted, are markdown in the `KeyValueStore`. | Send round trip; edit-load (stored `[url](url)` decodes, strips and re-detects to the same body); receive fallback on a stored bare-URL body; length (the budget sends with heavy formatting, one over is refused, nothing truncates) |
| 3. Form fields | A form field that formats text moves to `ComposerTextController(lists: true)` with the selection menu; its limit counts plain code points; the legacy package is deleted. Stored text in the old editor's dialect is repaired on edit-load by a client-side, idempotent step run before `decode` (it splits styles that cross line breaks, re-pairs overlapping-style sequences, drops marks the dialect has no spelling for); the repaired string is stored on the next save, and rows nobody edits keep their bytes. Remove the repair one release later. | Round trip over every shape the old encoder stored, lists and repair cases included; a device row for the menu and handles |

Steps 2 and 3 are independent. Doing step 2 first lets a server contract change
([ADR 034](adr/034-rich-text-wire-and-persistence.md)) ship with it.

Decisions a migrating host makes once:

- **Custom emoji by configuration.** A host with no custom emoji registers no
  `document` resolver and offers no custom emoji page. A `document:` key can then
  arrive only from foreign HTML, which the rich clipboard's trust rule strips
  ([ADR 032](adr/032-rich-clipboard.md)), and an escaped key paints its alt text.
- **No rewrite of stored chat bodies.** The receive-time fallback is the
  migration; bodies with raw URLs and bodies with edited `[url](url)` links both
  decode.
- **Copy in non-chat surfaces.** Selection hosts built on the markdown engine
  alone get its default copy formatter, which writes the codec's dialect back;
  they change nothing.

## 13. Reference host map

The demo app under `example/` is the reference. It registers the emoji page
only, fetches nothing from a network (its animated emoji are bundled), and does
not use the hover-open toggle region.

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
| `RichText`, markdown and detection | `example/lib/src/features/chat/utils/chat_body_markdown.dart` |
| Embed seams, sticker lookup, playback policy, played-once ledger | `example/lib/src/features/chat/utils/chat_body_host.dart`, `sticker_play_memory.dart` |
| Stand-in for the peer broadcast of a sticker tap | `example/lib/src/features/chat/utils/sticker_interaction_stub.dart` |
| Large-emoji setting and gate | `example/lib/src/features/chat/data/large_emoji_setting.dart`, `utils/large_emoji_policy.dart` |
| Emoji-only message chrome | `example/lib/src/features/chat/widgets/demo_emoji_message.dart` and `emoji_message/` (placement per platform: `emoji_chrome.dart`) |
| Message bodies, interaction handlers | `example/lib/src/features/chat/widgets/demo_message.dart`, `view/widget_chat_screen.dart` |
| Showcase conversation (`--dart-define=CHAT_SOURCE=showcase`) | `example/lib/src/features/chat/data/showcase_bodies.dart` |
| Popup anchor, composer view, apply-formatting toast | `example/lib/src/features/chat/widgets/chat_composer.dart` |
| Link prompt dialog, notes field with lists | `example/lib/src/features/chat/widgets/link_url_dialog.dart`, `example/lib/src/features/chat/widgets/notes_dialog.dart` |
| Suggestion panels, link preview, apply-formatting offer | `example/lib/src/features/chat/widgets/chat_suggestion_bar.dart`, `example/lib/src/features/chat/input/chat_link_preview.dart`, `example/lib/src/features/chat/input/chat_format_offer.dart` |
| Panel box and shortcuts | `example/lib/src/features/chat/widgets/chat_bottom_chrome.dart` |

import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/glyph_atlas.dart';
import 'package:chat_scroll_view_example/src/common/emoji_glyph_probe.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/animated_emoji_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/chat_center_band_store.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/joined_collection_source.dart';
import 'package:content_model/content_model.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image_decoder/image_decoder.dart';
import 'package:kv_shared_preferences/kv_shared_preferences.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_presentation/panel_presentation.dart';
import 'package:rich_clipboard/rich_clipboard.dart';

/// The app's long-lived services: the composition root of the reference host.
///
/// [create] builds them once, in dependency order, and [dispose] frees what
/// [create] made, in the reverse order. Nothing here is a service locator:
/// every consumer is handed what it needs by constructor, and the per-chat
/// controllers (`ChatInputSet`) take this object as their one argument.
///
/// ## Order
///
/// 1. the [KeyValueStore] adapter (`kv_shared_preferences`);
/// 2. the stores, which arrive loaded: [recents], [preferences],
///    [keyboardHeights], [dockWidths] and [centerBands];
/// 3. the asset cache [assets] with its pause layer and memory pressure, and
///    behind the glyph path an `AssetPipeline` for the [animatedEmoji] pack:
///    the pack's bundle fetcher and an `ImageCodecDecoder` for its animated
///    WebP. The pipeline is told every descriptor of the pack up front, so it
///    needs no content resolver;
/// 4. the data sources: [catalog], [keywords], [emojiSource], [emojiSearch],
///    under the [glyphProbe] that hides what the system cannot draw, the
///    animated emoji pack, and [emojiPageSource], which lists the pack after
///    the catalogue's categories;
/// 5. the [clipboard]: the `rich_clipboard` adapter every copy and paste
///    goes through, so text keeps its entities (ADR 032).
///
/// ## Ownership
///
/// What the caller hands in (the key-value store, the glyph cache, the asset
/// loader) stays the caller's: it is used, never closed or cleared here.
/// Everything [create] makes is disposed by [dispose]. Per-chat objects are
/// the chat screen's, and a disposed [ChatInputSet] leaves all of this
/// usable.
final class AppServices {
  AppServices._({
    required this.clipboard,
    required this.keyValueStore,
    required this.recents,
    required this.recentsShown,
    required this.preferences,
    required this.keyboardHeights,
    required this.dockWidths,
    required this.centerBands,
    required this.memoryPressure,
    required this.assets,
    required this.catalog,
    required this.keywords,
    required this.emojiSource,
    required this.emojiSearch,
    required this.emojiPageSource,
    required CollectionSource animatedEmoji,
    required this.glyphProbe,
    required this.glyphArtVersion,
    required this.glyphBakeObserver,
    required this.glyphCache,
    required AppLifecycleListener lifecycle,
    required PacedGlyphProbePass? webProbePass,
    required Future<bool> Function() glyphFontsSettled,
    required ValueNotifier<bool> glyphFontsReady,
    required AssetPipeline pipeline,
  }) : _animatedEmoji = animatedEmoji,
       _pipeline = pipeline,
       _lifecycle = lifecycle,
       _webProbePass = webProbePass,
       _glyphFontsReady = glyphFontsReady {
    // The panel's collections, loaded now as the reference client loads its
    // emoji at start: everything is in memory, so the first open lays every
    // section out at its size, not a row of placeholders that then jumps.
    for (final collection in emojiPageSource.collections.value) {
      unawaited(emojiPageSource.load(collection.id));
    }
    // Started now, the emoji font downloads while the app boots. Glyphs drawn
    // as text show once it came, or once the wait gave up (text then, not
    // placeholders for good). The web probe pass runs only over the font:
    // without it there is nothing to judge the glyphs by.
    unawaited(
      glyphFontsSettled().then((arrived) {
        if (_disposed) return;
        _glyphFontsReady.value = true;
        if (arrived && webProbePass != null) unawaited(webProbePass.run());
      }),
    );
  }

  /// The key-value namespace of the recents store.
  static const String recentsNamespace = 'recents';

  /// The key-value namespace of the preference store.
  static const String preferencesNamespace = 'preferences';

  /// Builds the services in dependency order.
  ///
  /// [keyValueStore] is the platform adapter unless a host (a test) passes its
  /// own. [assetLoader] reads the bundled emoji catalogue (the app bundle
  /// unless a test passes its own). [glyphCache] is where baked emoji pages
  /// are kept between launches; null bakes in memory every launch.
  /// [glyphArtVersion] replaces the probe's fingerprint as the cache's art
  /// version (see `createExampleEmojiGlyphCache`). [languages] is the ordered
  /// language set of emoji search, the app language first.
  static Future<AppServices> create({
    KeyValueStore? keyValueStore,
    EmojiAssetLoader? assetLoader,
    GlyphCacheStore? glyphCache,
    GlyphArtVersionSource? glyphArtVersion,
    List<String> languages = const <String>['ru', 'en'],
    RichClipboard clipboard = const SystemRichClipboard(),
  }) async {
    // What each step made, to free in reverse if a later one fails: a failed
    // boot must not leave a lifecycle listener or a pressure signal behind.
    final unwind = <void Function()>[];
    T owned<T>(T value, void Function(T value) dispose) {
      unwind.add(() => dispose(value));
      return value;
    }

    try {
      // 1. The adapter.
      final storage =
          keyValueStore ?? await SharedPreferencesKeyValueStore.open();

      // 2. Stores, loaded. Each registers as it arrives, so one that loaded
      // beside a sibling that failed is still freed.
      final (recents, preferences, keyboardHeights, dockWidths) = await (
        KeyValueRecentsStore.load(
          storage,
          namespace: recentsNamespace,
        ).then((store) => owned(store, (store) => store.dispose())),
        KeyValuePreferenceStore.load(
          storage,
          namespace: preferencesNamespace,
        ).then((store) => owned(store, (store) => store.dispose())),
        KeyboardHeightStore.open(storage),
        DockWidthStore.open(storage),
      ).wait;
      final centerBands = ChatCenterBandStore(storage);

      // 3. The asset cache. Its memory pressure is shared with the glyph
      // atlas.
      final memoryPressure = owned(
        SystemMemoryPressure(),
        (pressure) => pressure.dispose(),
      );
      // The pack is animated WebP, which the engine's image codecs decode.
      final decoders = DecoderRegistry()
        ..register(MediaForm.animatedImage, const ImageCodecDecoder());
      final pipeline = owned(
        AssetPipeline(
          fetcher: AnimatedEmojiPack.fetcher(rootBundle),
          decoders: decoders,
        ),
        (pipeline) => pipeline.dispose(),
      );
      AnimatedEmojiPack.descriptors.forEach(pipeline.know);
      // Whether the fonts that draw emoji as text are there: on the web the
      // emoji font downloads, and the grid shows placeholders, not
      // missing-glyph boxes, until it is (set once the probe's wait ends).
      final glyphFontsReady = owned(
        ValueNotifier<bool>(!kIsWeb),
        (ready) => ready.dispose(),
      );
      final assets = owned(
        PageAssets.createScope(
          producer: pipeline,
          memoryPressure: memoryPressure,
          systemFonts: PaintingBinding.instance.systemFonts,
          textGlyphsReady: glyphFontsReady,
        ),
        (scope) => scope.dispose(),
      );
      var hidden = false;
      final lifecycle = owned(
        AppLifecycleListener(
          onHide: () {
            hidden = true;
            assets.clock.setPaused(
              PlaybackPauseLayer.surfaceHidden,
              paused: true,
            );
          },
          onShow: () {
            hidden = false;
            assets.clock.setPaused(
              PlaybackPauseLayer.surfaceHidden,
              paused: false,
            );
          },
        ),
        (listener) => listener.dispose(),
      );

      // 4. Data sources over the stores.
      final loader = EmojiCatalogLoader(assetLoader ?? rootBundle.loadString);
      final catalog = EmojiCatalog(await loader.structure());
      final keywords = BundledKeywordSource(loader);
      // The probe's verdicts and the atlas plan are over the same glyphs: the
      // catalogue's, unfiltered.
      final glyphs = <String>[
        for (final entry in catalog.entries) entry.base.sequence,
      ];
      final probe = wireSystemEmojiGlyphProbe(glyphs: glyphs, store: storage);
      owned(probe.probe, (probe) => probe.dispose());
      // What the panel lists is a view that catches up with the store when the
      // panel opens and when search ends, not on every pick (see
      // [recentsShown]).
      final recentsShown = owned(
        DeferredRecentsStore(recents),
        (view) => view.dispose(),
      );
      final emojiSource = owned(
        EmojiCollectionSource(
          catalog: catalog,
          recents: recentsShown,
          preferences: preferences,
          glyphSupport: probe.probe,
          keywords: keywords,
          // The codes the pointer arrangement's tooltip shows.
          shortcodes: loader.shortcodes,
          // The recents hold the pack's emoji too, picked on the same page.
          resolver: AnimatedEmojiPack.resolver(),
          languages: languages,
        ),
        (source) => source.dispose(),
      );
      final emojiSearch = owned(
        EmojiSearchSource(
          catalog: catalog,
          keywords: keywords,
          languages: languages,
          recents: recentsShown,
          preferences: preferences,
          glyphSupport: probe.probe,
          shortcodes: loader.shortcodes,
        ),
        (source) => source.dispose(),
      );
      final animatedEmoji = owned(
        AnimatedEmojiPack.source(),
        (source) => source.dispose(),
      );
      final emojiPageSource = owned(
        JoinedCollectionSource([emojiSource, animatedEmoji]),
        (source) => source.dispose(),
      );

      return AppServices._(
        keyValueStore: storage,
        recents: recents,
        recentsShown: recentsShown,
        preferences: preferences,
        keyboardHeights: keyboardHeights,
        dockWidths: dockWidths,
        centerBands: centerBands,
        memoryPressure: memoryPressure,
        assets: assets,
        catalog: catalog,
        keywords: keywords,
        emojiSource: emojiSource,
        emojiSearch: emojiSearch,
        emojiPageSource: emojiPageSource,
        animatedEmoji: animatedEmoji,
        glyphProbe: probe.probe,
        glyphArtVersion: glyphArtVersion ?? probe.artVersion,
        glyphBakeObserver: probe.bakeObserver,
        glyphCache: glyphCache,
        lifecycle: lifecycle,
        webProbePass: kIsWeb
            ? _webPass(probe.probe, isPaused: () => hidden)
            : null,
        glyphFontsSettled: probe.fontsSettled,
        glyphFontsReady: glyphFontsReady,
        pipeline: pipeline,
        clipboard: clipboard,
      );
    } on Object {
      for (final undo in unwind.reversed) {
        undo();
      }
      rethrow;
    }
  }

  /// The adapter every store writes through.
  final KeyValueStore keyValueStore;

  /// The clipboard every copy and paste goes through: plain text for other
  /// apps, and the text with its entities for this one. Not disposed: it
  /// holds nothing.
  final RichClipboard clipboard;

  /// What the user picked, per kind of content.
  final RecentsStore recents;

  /// The recents as the panel shows them: those of [recents] as of the last
  /// `commit`. A pick is recorded in [recents] at once and listed here when
  /// the host commits, so the grid does not reorder under the finger that is
  /// picking from it.
  final DeferredRecentsStore recentsShown;

  /// The variant chosen per emoji, the selected panel page and the dock
  /// choice.
  final PreferenceStore preferences;

  /// The keyboard height remembered per orientation.
  final KeyboardHeightStore keyboardHeights;

  /// The width the user dragged the docked panel to.
  final DockWidthStore dockWidths;

  /// The saved reading position of each chat.
  final ChatCenterBandStore centerBands;

  /// Fires when the system asks for memory; the glyph atlas shares it.
  final SystemMemoryPressure memoryPressure;

  /// The asset cache the panel pages and the composer's inline content draw
  /// through. Glyphs are baked sprites where an atlas is registered with it
  /// and text where none is.
  final AssetCacheScope assets;

  /// The emoji structure.
  final EmojiCatalog catalog;

  /// The shipped keyword packs.
  final KeywordSource keywords;

  /// The emoji collections.
  final EmojiCollectionSource emojiSource;

  /// Emoji search.
  final EmojiSearchSource emojiSearch;

  /// What the emoji page lists: the collections of [emojiSource], then the
  /// pack of animated emoji. It owns neither.
  final CollectionSource emojiPageSource;

  /// Which glyphs the system cannot draw.
  final MissingGlyphProbe glyphProbe;

  /// The art version in the atlas cache key: the probe's, unless the host
  /// overrode it.
  final GlyphArtVersionSource glyphArtVersion;

  /// Shows the probe each cell the bake draws.
  final GlyphBakeObserver glyphBakeObserver;

  /// Where baked pages persist, or null to bake in memory every launch.
  final GlyphCacheStore? glyphCache;

  final CollectionSource _animatedEmoji;
  final AssetPipeline _pipeline;
  final AppLifecycleListener _lifecycle;
  final PacedGlyphProbePass? _webProbePass;
  final ValueNotifier<bool> _glyphFontsReady;
  var _disposed = false;

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;

  /// The glyphs the emoji atlas is planned for, in the order that decides
  /// where each is baked: the catalogue as the page shows it (each emoji as
  /// its chosen variant), then recents the catalogue lacks, sorted.
  ///
  /// Unlike [GlyphPlan.of] this does not follow the glyph probe: an emoji the
  /// system cannot draw stays in the plan, so a verdict never changes the
  /// cache key and never re-bakes a page (ADR 006). `null` while the page's
  /// collections are not all loaded.
  GlyphPlan? planGlyphs(List<Collection> collections) {
    final shown = GlyphPlan.of(collections);
    if (shown == null) return null;
    final catalogue = <String>[
      for (final entry in catalog.entries)
        emojiSource.shownKeyOf(entry).sequence,
    ];
    final known = catalogue.toSet();
    final extras = <String>[
      for (final glyph in shown.glyphs)
        if (!known.contains(glyph)) glyph,
    ]..sort();
    return GlyphPlan([...catalogue, ...extras]);
  }

  /// Frees what [create] made, in the reverse of the order it made it.
  /// Idempotent. What was handed in is left as it is.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _webProbePass?.cancel();
    emojiPageSource.dispose();
    _animatedEmoji.dispose();
    emojiSearch.dispose();
    emojiSource.dispose();
    recentsShown.dispose();
    glyphProbe.dispose();
    _lifecycle.dispose();
    assets.dispose();
    _glyphFontsReady.dispose();
    _pipeline.dispose();
    memoryPressure.dispose();
    preferences.dispose();
    recents.dispose();
  }

  // The web bakes nothing, so the probe has no bake to share: it draws its
  // own cells, a few a frame, once the engine has the fonts that draw them
  // (the probe also distrusts a pass in which every cell is flagged).

  static PacedGlyphProbePass _webPass(
    MissingGlyphProbe probe, {
    required bool Function() isPaused,
  }) {
    final reader = GlyphPixelReader(ParagraphGlyphRasteriser());
    return PacedGlyphProbePass(
      probe: probe,
      cellOf: reader.pixelsOf,
      nextFrame: () => SchedulerBinding.instance.endOfFrame,
      isPaused: isPaused,
      glyphsPerFrame: () => 8,
    );
  }
}

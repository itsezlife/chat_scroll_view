import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/glyph_atlas.dart';
import 'package:chat_scroll_view_example/src/common/emoji_glyph_probe.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/chat_center_band_store.dart';
import 'package:content_model/content_model.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kv_shared_preferences/kv_shared_preferences.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_presentation/panel_presentation.dart';

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
///    [keyboardHeights] and [centerBands];
/// 3. the asset cache [assets] with its pause layer and memory pressure
///    (this host has no fetcher or decoder: its content is emoji glyphs, so
///    the cache has no producer behind the glyph path and the content
///    resolver has no consumer);
/// 4. the emoji data sources: [catalog], [keywords], [emojiSource],
///    [emojiSearch], under the [glyphProbe] that hides what the system cannot
///    draw.
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
    required this.keyValueStore,
    required this.recents,
    required this.preferences,
    required this.keyboardHeights,
    required this.centerBands,
    required this.memoryPressure,
    required this.assets,
    required this.catalog,
    required this.keywords,
    required this.emojiSource,
    required this.emojiSearch,
    required this.glyphProbe,
    required this.glyphArtVersion,
    required this.glyphBakeObserver,
    required this.glyphCache,
    required AppLifecycleListener lifecycle,
    required PacedGlyphProbePass? webProbePass,
  }) : _lifecycle = lifecycle,
       _webProbePass = webProbePass {
    if (webProbePass != null) {
      _webProbeStart = Timer(
        _webProbeDelay,
        () => unawaited(webProbePass.run()),
      );
    }
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
      final (recents, preferences, keyboardHeights) = await (
        KeyValueRecentsStore.load(
          storage,
          namespace: recentsNamespace,
        ).then((store) => owned(store, (store) => store.dispose())),
        KeyValuePreferenceStore.load(
          storage,
          namespace: preferencesNamespace,
        ).then((store) => owned(store, (store) => store.dispose())),
        KeyboardHeightStore.open(storage),
      ).wait;
      final centerBands = ChatCenterBandStore(storage);

      // 3. The asset cache. Its memory pressure is shared with the glyph
      // atlas.
      final memoryPressure = owned(
        SystemMemoryPressure(),
        (pressure) => pressure.dispose(),
      );
      final assets = owned(
        PageAssets.createScope(memoryPressure: memoryPressure),
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
      final emojiSource = owned(
        EmojiCollectionSource(
          catalog: catalog,
          recents: recents,
          preferences: preferences,
          glyphSupport: probe.probe,
          keywords: keywords,
          languages: languages,
        ),
        (source) => source.dispose(),
      );
      final emojiSearch = owned(
        EmojiSearchSource(
          catalog: catalog,
          keywords: keywords,
          languages: languages,
          recents: recents,
          preferences: preferences,
          glyphSupport: probe.probe,
        ),
        (source) => source.dispose(),
      );

      return AppServices._(
        keyValueStore: storage,
        recents: recents,
        preferences: preferences,
        keyboardHeights: keyboardHeights,
        centerBands: centerBands,
        memoryPressure: memoryPressure,
        assets: assets,
        catalog: catalog,
        keywords: keywords,
        emojiSource: emojiSource,
        emojiSearch: emojiSearch,
        glyphProbe: probe.probe,
        glyphArtVersion: glyphArtVersion ?? probe.artVersion,
        glyphBakeObserver: probe.bakeObserver,
        glyphCache: glyphCache,
        lifecycle: lifecycle,
        webProbePass: kIsWeb
            ? _webPass(probe.probe, isPaused: () => hidden)
            : null,
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

  /// What the user picked, per kind of content.
  final RecentsStore recents;

  /// The variant chosen per emoji, the selected panel page and the dock
  /// choice.
  final PreferenceStore preferences;

  /// The keyboard height remembered per orientation.
  final KeyboardHeightStore keyboardHeights;

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

  /// Which glyphs the system cannot draw.
  final MissingGlyphProbe glyphProbe;

  /// The art version in the atlas cache key: the probe's, unless the host
  /// overrode it.
  final GlyphArtVersionSource glyphArtVersion;

  /// Shows the probe each cell the bake draws.
  final GlyphBakeObserver glyphBakeObserver;

  /// Where baked pages persist, or null to bake in memory every launch.
  final GlyphCacheStore? glyphCache;

  final AppLifecycleListener _lifecycle;
  final PacedGlyphProbePass? _webProbePass;
  Timer? _webProbeStart;
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
    _webProbeStart?.cancel();
    _webProbePass?.cancel();
    emojiSearch.dispose();
    emojiSource.dispose();
    glyphProbe.dispose();
    _lifecycle.dispose();
    assets.dispose();
    memoryPressure.dispose();
    preferences.dispose();
    recents.dispose();
  }

  // The web bakes nothing, so the probe has no bake to share: it draws its
  // own cells, a few a frame, once the page has had time to load its emoji
  // font (there is no signal for that, hence the delay; the probe distrusts a
  // pass in which every cell is flagged).
  static const Duration _webProbeDelay = Duration(seconds: 3);

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

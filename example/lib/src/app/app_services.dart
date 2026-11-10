import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/glyph_atlas.dart';
import 'package:chat_scroll_view_example/src/app/lottie_playback.dart';
import 'package:chat_scroll_view_example/src/app/media_disk_cache.dart';
import 'package:chat_scroll_view_example/src/app/scrolling_surfaces.dart';
import 'package:chat_scroll_view_example/src/app/system_reduced_motion.dart';
import 'package:chat_scroll_view_example/src/app/video_playback.dart';
import 'package:chat_scroll_view_example/src/common/constant/demo_config.dart';
import 'package:chat_scroll_view_example/src/common/emoji_glyph_probe.dart';
import 'package:chat_scroll_view_example/src/common/lab_net.dart';
import 'package:chat_scroll_view_example/src/common/scroll_lab.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/animated_emoji_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/bundled_packs.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/byte_cache.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/chat_center_band_store.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/chat_draft_store.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/corpus_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/deferred_library_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/frame_counter_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/giphy_client.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/giphy_content.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/giphy_gif_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/installed_packs_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/joined_collection_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/large_emoji_setting.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/library_content_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/lottie_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/shipped_packs_seed.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/static_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/video_sticker_pack.dart';
import 'package:content_model/content_model.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:frame_texture/frame_texture.dart';
import 'package:http/http.dart' as http;
import 'package:image_decoder/image_decoder.dart';
import 'package:kv_shared_preferences/kv_shared_preferences.dart';
import 'package:l/l.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_presentation/panel_presentation.dart';
import 'package:rich_clipboard/rich_clipboard.dart';

/// The app's long-lived services: the composition root of the demo host.
///
/// [create] builds them once, in dependency order, and [dispose] frees what
/// [create] made, in the reverse order. Nothing here is a service locator:
/// every consumer is handed what it needs by constructor, and the per-chat
/// controllers (`ChatInputSet`) take this object as their one argument.
///
/// ## Order
///
/// 1. the [KeyValueStore] adapter (`kv_shared_preferences`);
/// 2. the stores, which arrive loaded: [recents] (the emoji's), the content
///    [library] (recent and favourite stickers, saved GIFs, packs; ADR 044),
///    [preferences], [keyboardHeights], [dockWidths], [centerBands], [drafts]
///    and [largeEmoji];
/// 3. the asset cache [assets] with its pause policies ([activity]: the app's
///    focus and visibility, the [lowPower] switch, the system's reduced-motion
///    setting and the overlays over the chat) and memory pressure, and
///    behind the glyph path an `AssetPipeline` for the bundled packs: one
///    bundle fetcher, an `ImageCodecDecoder` for the animated emoji's WebP
///    and, when the platform can run one, the Lottie decoder for the
///    stickers and, likewise, the video decoder for the WebM, MP4 and GIF
///    packs. The pipeline is told every descriptor of the packs up front,
///    so it needs no content resolver. The order inside this step is the
///    playback clock (made here so the Lottie frame scheduler can follow it
///    before the scope exists; the scope then does not own it), memory
///    pressure, the Lottie playback (probed by starting its render engine; a
///    platform without the library, or a failed probe, registers nothing and
///    logs once), the video playback (probed and skipped the same way), the
///    pipeline, the scope;
/// 4. the data sources: [catalog], [keywords], [emojiSource], [emojiSearch],
///    under the [glyphProbe] that hides what the system cannot draw, the
///    animated emoji pack, and [emojiPageSource], which lists that pack after
///    the catalogue's categories, and the [stickerPageSource] and
///    [gifPageSource] of the two dedicated pages, over the favourite and
///    recent stickers and the saved GIFs ([libraryShown], a view of the
///    library that catches up when the panel opens), and the [packs] source
///    over the bundled packs and the corpus.
///    The panel lists only real content: the stickers page the local corpus,
///    the GIF page Giphy. The bundled demo stickers and clips stay known to
///    the pipeline, for the showcase chat and the recents, but no page lists
///    them;
/// 5. the [clipboard]: the `rich_clipboard` adapter every copy and paste
///    goes through, so text keeps its entities (ADR 032).
///
/// ## Ownership
///
/// What the caller hands in (the key-value store, the glyph cache, the asset
/// loader) stays the caller's: it is used, never closed or cleared here.
/// Everything [create] makes is disposed by [dispose], the Lottie playback
/// after the scope and the pipeline that use its decoder, then the video
/// playback the same way, and the clock after them. Per-chat objects are
/// the chat screen's, and a disposed [ChatInputSet] leaves all of this
/// usable.
final class AppServices {
  AppServices._({
    required this.clipboard,
    required this.keyValueStore,
    required this.recents,
    required this.recentsShown,
    required this.library,
    required this.libraryShown,
    required this.packs,
    required this.preferences,
    required this.keyboardHeights,
    required this.dockWidths,
    required this.centerBands,
    required this.drafts,
    required this.largeEmoji,
    required this.memoryPressure,
    required this.assets,
    required this.activity,
    required this.lowPower,
    required this.catalog,
    required this.keywords,
    required this.emojiSource,
    required this.emojiSearch,
    required this.emojiPageSource,
    required this.stickerPageSource,
    required this.gifPageSource,
    required this.gifSearch,
    required this.gifSuggestions,
    required this.giphy,
    required this.corpus,
    required this.describe,
    required this.scrolling,
    required List<CollectionSource> pageParts,
    required PlaybackClock clock,
    required LottiePlayback? lottiePlayback,
    required VideoPlayback? videoPlayback,
    required this.glyphProbe,
    required this.glyphArtVersion,
    required this.glyphBakeObserver,
    required this.glyphCache,
    required WidgetsPlaybackLifecycleSource lifecycleSource,
    required ValueNotifier<bool> reducedMotion,
    required PacedGlyphProbePass? webProbePass,
    required Future<bool> Function() glyphFontsSettled,
    required ValueNotifier<bool> glyphFontsReady,
    required AssetPipeline pipeline,
    required MediaDiskCache? mediaCache,
  }) : _mediaCache = mediaCache,
       _pageParts = pageParts,
       _clock = clock,
       _lottiePlayback = lottiePlayback,
       _videoPlayback = videoPlayback,
       _pipeline = pipeline,
       _lifecycleSource = lifecycleSource,
       _reducedMotion = reducedMotion,
       _webProbePass = webProbePass,
       _glyphFontsReady = glyphFontsReady {
    // The panel's collections are loaded now, at start: everything is in
    // memory, so the first open lays every
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

  /// The key-value namespace of the content library.
  static const String libraryNamespace = 'library';

  /// The limits of the content library without a subscription: 5 favourite
  /// stickers and 200 saved GIFs, and the 30 recent stickers it keeps.
  static const LibraryLimits libraryLimits = LibraryLimits(
    favouriteStickers: 5,
    savedGifs: 200,
  );

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
  /// language set of emoji search, the app language first. [startLottie]
  /// starts the Lottie decoder (the platform's unless a test passes its own);
  /// it answers null where there is none, and then nothing is registered.
  /// [startVideo]
  /// does the same for the video decoder: the platform's unless a test passes
  /// its own, and null where there is none.
  ///
  /// [giphyApiKey] turns the GIF page's Giphy source on (see
  /// [giphyApiKeyDefine]); empty leaves the page with the saved GIFs alone.
  /// [giphyHttpClient] is the transport it sends through, closed by the
  /// services only if they made it. [corpus] is the local sticker corpus;
  /// null looks for one in the app bundle and in the `CHAT_CORPUS_DIR`
  /// directory.
  ///
  /// [mediaCache] is where animated media is kept between launches: Giphy's
  /// stills and clips in its `giphy` folder, the rendered Lottie frames in
  /// its `lottie_frames` folder (null: in memory only, as in a test). Its
  /// keep period and size limit are the host's, set where it is made; the
  /// services start its sweeps and stop them on [dispose].
  ///
  /// [diskCache] is the one switch over every disk tier (see
  /// [DemoConfig.diskCache]): false ignores [glyphCache] and [mediaCache],
  /// which is then neither used nor swept, and everything is kept in memory
  /// for this launch only.
  static Future<AppServices> create({
    KeyValueStore? keyValueStore,
    EmojiAssetLoader? assetLoader,
    GlyphCacheStore? glyphCache,
    GlyphArtVersionSource? glyphArtVersion,
    List<String> languages = const <String>['ru', 'en'],
    RichClipboard clipboard = const SystemRichClipboard(),
    LottiePlaybackStarter startLottie = LottiePlayback.start,
    VideoPlaybackStarter startVideo = VideoPlayback.start,
    String giphyApiKey = giphyApiKeyDefine,
    http.Client? giphyHttpClient,
    Future<MediaDiskCache?>? mediaCache,
    CorpusStickerPack? corpus,
    bool diskCache = DemoConfig.diskCache,
  }) async {
    if (!diskCache) {
      l.i(
        'Disk caches are off (--dart-define=DISK_CACHE=false): glyph pages, '
        'Lottie frames and Giphy files are kept in memory only',
      );
    }
    final glyphDisk = diskCache ? glyphCache : null;
    final mediaDisk = diskCache ? mediaCache : null;
    // What each step made, to free in reverse if a later one fails: a failed
    // boot must not leave a lifecycle listener or a pressure signal behind.
    final unwind = <void Function()>[];
    T owned<T>(T value, void Function(T value) dispose) {
      unwind.add(() => dispose(value));
      return value;
    }

    try {
      // 0. The media store, swept now (off the frame path) and hourly; a
      // tier never waits for a sweep.
      final media = switch (await mediaDisk) {
        final media? => owned(media..start(), (media) => media.dispose()),
        null => null,
      };

      // 1. The adapter.
      final storage =
          keyValueStore ?? await SharedPreferencesKeyValueStore.open();

      // 2. Stores, loaded. Each registers as it arrives, so one that loaded
      // beside a sibling that failed is still freed.
      final (
        recents,
        library,
        preferences,
        keyboardHeights,
        dockWidths,
        largeEmoji,
        packSeed,
      ) = await (
        KeyValueRecentsStore.load(
          storage,
          namespace: recentsNamespace,
        ).then((store) => owned(store, (store) => store.dispose())),
        StoredContentLibrary.load(
          KeyValueLibraryStorage(storage, namespace: libraryNamespace),
          limits: libraryLimits,
        ).then((library) => owned(library, (library) => library.dispose())),
        KeyValuePreferenceStore.load(
          storage,
          namespace: preferencesNamespace,
        ).then((store) => owned(store, (store) => store.dispose())),
        KeyboardHeightStore.open(storage),
        DockWidthStore.open(storage),
        LargeEmojiSetting.load(
          storage,
        ).then((setting) => owned(setting, (setting) => setting.dispose())),
        ShippedPacksSeed.load(storage),
      ).wait;
      final centerBands = ChatCenterBandStore(storage);
      final drafts = ChatDraftStore(storage);

      // 3. The asset cache. Its memory pressure is shared with the glyph
      // atlas.
      final memoryPressure = owned(
        SystemMemoryPressure(),
        (pressure) => pressure.dispose(),
      );
      // The clock is the host's, not the scope's: the Lottie frame scheduler
      // follows it, and it must exist before the decoder does, which is
      // before the scope.
      final clock = owned(PlaybackClock(), (clock) => clock.dispose());
      // Whether the chat list or the panel scrolls: the pool creates no
      // texture while one does. The chat screen and the input set report
      // into it.
      final scrolling = owned(
        ScrollingSurfaces(),
        (scrolling) => scrolling.dispose(),
      );
      // The platform's texture host (ADR 043), behind its switch: off, or
      // where the platform has none, there is no pool and every playing
      // asset keeps its page slot. The decoders write into its textures, so
      // it exists before them; it outlives the scope (it is disposed after
      // it) and gives its idle textures back on memory pressure, through the
      // scope.
      final platformTextureHost = DemoConfig.frameTextures
          ? PlatformFrameTextureHost.forPlatform()
          : null;
      // The lab counts the textures made while a surface scrolls.
      final textureHost = DemoConfig.scrollLab && platformTextureHost != null
          ? ScrollLab.textureHost = LabTextureHost(
              platformTextureHost,
              scrolling,
            )
          : platformTextureHost;
      final textures = textureHost == null
          ? null
          : owned(
              FrameTexturePool(host: textureHost, scrolling: scrolling),
              (pool) => pool.dispose(),
            );
      if (DemoConfig.scrollLab) ScrollLab.texturePool = textures;
      // The Lottie playback is probed by starting its engine. None (no
      // library here) leaves vector animations at their placeholder.
      final lottiePlayback = await startLottie(
        clock: clock,
        memoryPressure: memoryPressure,
        textures: textures,
        cacheDirectory: media?.folder(lottieFramesFolder),
      );
      if (lottiePlayback != null) {
        owned(lottiePlayback, _closePlayback);
      }
      // The video playback is probed the same way. None leaves video at its
      // placeholder.
      final videoPlayback = await startVideo(
        clock: clock,
        memoryPressure: memoryPressure,
        textures: textures,
      );
      if (videoPlayback != null) {
        owned(videoPlayback, _closeVideoPlayback);
      }
      // The emoji pack is animated WebP and the static stickers are PNG: both
      // are the engine's image codecs' work, whether or not Lottie runs here.
      final decoders = DecoderRegistry()
        ..register(MediaForm.still, const ImageCodecDecoder())
        ..register(MediaForm.animatedImage, const ImageCodecDecoder());
      if (lottiePlayback != null) {
        decoders.register(MediaForm.vectorAnimation, lottiePlayback.decoder);
      }
      if (videoPlayback != null) {
        decoders.register(MediaForm.video, videoPlayback.decoder);
      }
      // Content that is not bundled: the local corpus, found in the bundle
      // and in the directory the build was given, and Giphy, only with a key.
      final corpusPacks =
          corpus ??
          await CorpusStickerPack.load(
            bundle: rootBundle,
            directory: CorpusStickerPack.directoryDefine,
          );
      GiphyContent? giphy;
      if (giphyApiKey.isEmpty) {
        l.i(
          'Giphy GIFs are off: no GIPHY_API_KEY was given '
          '(--dart-define=GIPHY_API_KEY=...); the GIF page lists the saved '
          'GIFs alone',
        );
      } else {
        final live =
            giphyHttpClient ??
            owned<http.Client>(http.Client(), (client) => client.close());
        // The scroll lab records and replays Giphy's answers with its pointer
        // tape; every request of the Giphy code, API and media, goes through
        // this one client.
        final labNet = DemoConfig.scrollLab ? LabNet.instance : null;
        final transport = labNet == null ? live : LabNetClient(live, labNet);
        // The disk tier of the stills and the clips is the fetcher's (ADR
        // 022): one folder of the media store for both, their names apart by
        // kind. It sits under the transport, not over it: a file found on
        // disk is no request, so the lab's tape neither records nor replays
        // it (lab builds turn it off, see DemoConfig.diskCache).
        final disk = switch (media) {
          final media? => ByteCache.directory(media.folder(giphyFolder)),
          null => null,
        };
        giphy = GiphyContent(
          GiphyClient(apiKey: giphyApiKey, client: transport),
          stillDisk: disk,
          clipDisk: disk,
        );
      }
      final pipeline = owned(
        AssetPipeline(
          // Giphy first, then the corpus, then the bundle: each takes its own
          // keys and hands the rest on.
          fetcher: _contentFetcher(giphy, corpusPacks, rootBundle),
          decoders: decoders,
          resolver: giphy?.resolver(otherwise: BundledPacks.resolver()),
        ),
        (pipeline) => pipeline.dispose(),
      );
      BundledPacks.descriptors.forEach(pipeline.know);
      corpusPacks.descriptors.forEach(pipeline.know);
      // What a key is, for the recents: the bundled packs, the corpus and the
      // Giphy clips this session listed.
      ContentDescriptor? describe(ContentKey key) =>
          BundledPacks.describe(key) ??
          corpusPacks.of(key)?.descriptor ??
          giphy?.descriptorOf(key);
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
          clock: clock,
          memoryPressure: memoryPressure,
          systemFonts: PaintingBinding.instance.systemFonts,
          textGlyphsReady: glyphFontsReady,
          textures: textures,
        ),
        (scope) => scope.dispose(),
      );
      // The pause policies (ADR 022): one object turns what the app and the
      // platform report into layers of the clock the chat and the panel share.
      // Dust and emoji alike stop when the app is hidden or minimised, is
      // covered by a dialog, or the switch below says power is short, and on
      // desktop and the web when the window loses focus; a phone's system
      // sheet over the app (the shade, a permission dialog) leaves them be.
      final lifecycleSource = owned(
        WidgetsPlaybackLifecycleSource(),
        (source) => source.dispose(),
      );
      // A stub: nothing here detects the system's battery saver (the packages
      // take no battery plugin). A host feeds this from its own detection;
      // here it is a switch a test or a debug panel flips.
      final lowPower = owned(
        ValueNotifier<bool>(false),
        (switchValue) => switchValue.dispose(),
      );
      final reducedMotion = owned(
        SystemReducedMotion(),
        (setting) => setting.dispose(),
      );
      final activity = owned(
        PlaybackActivity(
          clock: assets.clock,
          lifecycle: lifecycleSource,
          lowPower: lowPower,
          reducedMotion: reducedMotion,
        ),
        (activity) => activity.dispose(),
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
          resolver: BundledPacks.resolver(),
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
      // A pack by the id a sticker's or custom emoji's descriptor names: the
      // bundled packs and the corpus, all in memory, so the fetch never
      // fails and the source's memory tier holds them once found.
      final packs = owned(
        CachingPackSource(
          (id) async => BundledPacks.packOf(id) ?? corpusPacks.packOf(id),
        ),
        (source) => source.dispose(),
      );
      // The panel lists the packs the user installed. The ones it listed
      // before there was a library (the corpus, the animated emoji) are
      // installed once, on the first run that ships each, and so are the
      // bundled demo sticker packs (an install from before them gets them on
      // its next run). A pack not shipped this way shows Add in its sheet.
      await packSeed.install(library, [
        for (final pack in corpusPacks.packs)
          (id: pack.packId, kind: PackKind.stickers),
        for (final id in [
          LottieStickerPack.packId,
          StaticStickerPack.packId,
          VideoStickerPack.packId,
        ])
          (id: id, kind: PackKind.stickers),
        (id: AnimatedEmojiPack.packId, kind: PackKind.emoji),
      ]);
      // Looked up now, so the panel's first open finds them loaded.
      await Future.wait([
        for (final kind in PackKind.values)
          for (final id in library.installedPacks(kind).value) packs.lookup(id),
      ]);
      // The emoji page: the catalogue, then the installed packs of custom
      // emoji after its categories, in the library's order.
      final installedEmoji = owned(
        InstalledPacksSource(
          kind: PackKind.emoji,
          library: library,
          packs: packs,
        ),
        (source) => source.dispose(),
      );
      final emojiPageSource = owned(
        JoinedCollectionSource([emojiSource, installedEmoji]),
        (source) => source.dispose(),
      );
      // The library as the panel lists it: caught up when the panel opens,
      // as the emoji recents are (see [libraryShown]).
      final libraryShown = owned(
        DeferredLibraryView(library),
        (view) => view.dispose(),
      );
      // The stickers page: the favourite stickers and the recent ones, then
      // the installed sticker packs in the library's order. Without a corpus
      // (as on CI) the bundled demo packs follow the favourites and the
      // recents; a pack added from a sheet joins them.
      final recentStickers = owned(
        LibraryContentSource.stickers(
          recentStickers: libraryShown.recentStickers,
          favouriteStickers: libraryShown.favouriteStickers,
          describe: describe,
        ),
        (source) => source.dispose(),
      );
      final installedStickers = owned(
        InstalledPacksSource(
          kind: PackKind.stickers,
          library: library,
          packs: packs,
        ),
        (source) => source.dispose(),
      );
      final stickerPageSource = owned(
        JoinedCollectionSource([recentStickers, installedStickers]),
        (source) => source.dispose(),
      );
      // The GIF page: the saved GIFs as its recents, then Giphy's trending
      // when there is a key. Offline, trending fails and the page shows its
      // failure line with a retry; without a key the saved GIFs are all it
      // lists. No bundled clip is listed beneath either; a build with
      // FRAME_COUNTER_GIFS lists the frame counter clips first.
      final recentGifs = owned(
        LibraryContentSource.gifs(
          savedGifs: libraryShown.savedGifs,
          describe: describe,
        ),
        (source) => source.dispose(),
      );
      final giphyTrending = giphy == null
          ? null
          : owned(
              GiphyGifSource(client: giphy.client, content: giphy),
              (source) => source.dispose(),
            );
      final gifSearch = giphy == null
          ? null
          : owned(
              GiphyGifSearch(client: giphy.client, content: giphy),
              (search) => search.dispose(),
            );
      // The frame counter clips first, to read a recording by, when the
      // build asks for them.
      final frameCounters = DemoConfig.frameCounterGifs
          ? owned(FrameCounterPack.source(), (source) => source.dispose())
          : null;
      final gifPageSource = owned(
        JoinedCollectionSource([?frameCounters, recentGifs, ?giphyTrending]),
        (source) => source.dispose(),
      );

      return AppServices._(
        keyValueStore: storage,
        recents: recents,
        recentsShown: recentsShown,
        library: library,
        libraryShown: libraryShown,
        packs: packs,
        preferences: preferences,
        keyboardHeights: keyboardHeights,
        dockWidths: dockWidths,
        centerBands: centerBands,
        drafts: drafts,
        largeEmoji: largeEmoji,
        memoryPressure: memoryPressure,
        assets: assets,
        activity: activity,
        lowPower: lowPower,
        catalog: catalog,
        keywords: keywords,
        emojiSource: emojiSource,
        emojiSearch: emojiSearch,
        emojiPageSource: emojiPageSource,
        stickerPageSource: stickerPageSource,
        gifPageSource: gifPageSource,
        gifSearch: gifSearch,
        gifSuggestions: giphyTrending,
        giphy: giphy,
        corpus: corpusPacks,
        describe: describe,
        scrolling: scrolling,
        pageParts: [
          recentStickers,
          recentGifs,
          ?giphyTrending,
          installedStickers,
          installedEmoji,
        ],
        clock: clock,
        lottiePlayback: lottiePlayback,
        videoPlayback: videoPlayback,
        glyphProbe: probe.probe,
        glyphArtVersion: glyphArtVersion ?? probe.artVersion,
        glyphBakeObserver: probe.bakeObserver,
        glyphCache: glyphDisk,
        lifecycleSource: lifecycleSource,
        reducedMotion: reducedMotion,
        webProbePass: kIsWeb
            ? _webPass(
                probe.probe,
                isPaused: () => assets.clock.pausedLayers.contains(
                  PlaybackPauseLayer.surfaceHidden,
                ),
              )
            : null,
        glyphFontsSettled: probe.fontsSettled,
        glyphFontsReady: glyphFontsReady,
        pipeline: pipeline,
        mediaCache: media,
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

  /// What the user picked, per kind of content: the emoji recents, by
  /// frequency. The recent stickers and the GIF recents are the [library]'s.
  final RecentsStore recents;

  /// The recents as the panel shows them: those of [recents] as of the last
  /// `commit`. A pick is recorded in [recents] at once and listed here when
  /// the host commits, so the grid does not reorder under the finger that is
  /// picking from it.
  final DeferredRecentsStore recentsShown;

  /// The user's own lists: recent and favourite stickers, saved GIFs (the
  /// GIF recents) and installed packs, kept to [libraryLimits] and persisted
  /// in [libraryNamespace]. Sending a sticker adds it to the recents, sending
  /// a GIF saves it.
  final ContentLibrary library;

  /// The panel's content previews: the one that is up (which back closes
  /// first) and the [library] their menus read.
  late final ContentPreviewController previews = ContentPreviewController(
    library: library,
  );

  /// The [library] as the panel shows it: as of the last
  /// [commitShownLists], except that what leaves the library leaves it at
  /// once and an edit the user asks for (`DeferredLibraryView.apply`) shows
  /// at once. The record of a send (`DeferredLibraryView.record`) waits.
  final DeferredLibraryView libraryShown;

  /// Every pack by its id, as a content's descriptor names it: the bundled
  /// packs and the local corpus.
  final PackSource packs;

  /// Lets the panel's lists catch up with what was picked: the emoji
  /// recents ([recentsShown]) and the library's lists ([libraryShown]).
  void commitShownLists() {
    recentsShown.commit();
    libraryShown.commit();
  }

  /// The variant chosen per emoji, the selected panel page and the dock
  /// choice.
  final PreferenceStore preferences;

  /// The keyboard height remembered per orientation.
  final KeyboardHeightStore keyboardHeights;

  /// The width the user dragged the docked panel to.
  final DockWidthStore dockWidths;

  /// The saved reading position of each chat.
  final ChatCenterBandStore centerBands;

  /// The unsent text of each chat's composer.
  final ChatDraftStore drafts;

  /// Whether an emoji-only message is shown large and without a bubble.
  final LargeEmojiSetting largeEmoji;

  /// Fires when the system asks for memory; the glyph atlas shares it.
  final SystemMemoryPressure memoryPressure;

  /// The asset cache the panel pages and the composer's inline content draw
  /// through. Glyphs are baked sprites where an atlas is registered with it
  /// and text where none is.
  final AssetCacheScope assets;

  /// Turns the app's focus and visibility, [lowPower], the system's
  /// reduced-motion setting and the overlays over the chat into pause layers
  /// of [assets]'s clock. `holdOverlay` is what the navigator observer calls.
  final PlaybackActivity activity;

  /// Whether the device is saving power; the clock pauses while it is true.
  ///
  /// A stub switch: the example detects nothing. A host sets it from the
  /// battery saver (macOS and Windows: Low Power Mode and Battery Saver; see
  /// docs/host-integration.md) and may combine several signals.
  final ValueNotifier<bool> lowPower;

  /// The emoji structure.
  final EmojiCatalog catalog;

  /// The shipped keyword packs.
  final KeywordSource keywords;

  /// The emoji collections.
  final EmojiCollectionSource emojiSource;

  /// Emoji search.
  final EmojiSearchSource emojiSearch;

  /// What the emoji page lists: the collections of [emojiSource], then the
  /// installed packs of custom emoji in the library's order. It owns none.
  final CollectionSource emojiPageSource;

  /// What the stickers page lists: the favourite stickers, the recent
  /// stickers, then the installed sticker packs in the library's order. It
  /// owns none.
  final CollectionSource stickerPageSource;

  /// What the GIF page lists: the saved GIFs, then Giphy's trending clips
  /// when there is a key. It owns none.
  final CollectionSource gifPageSource;

  /// Search of Giphy for the GIF page, or null without a key.
  final SearchSource? gifSearch;

  /// What the GIF page's search lists before anything is typed: Giphy's
  /// trending clips alone, the list the page shows under its recents (so no
  /// second request), or null without a key. It owns none.
  final CollectionSource? gifSuggestions;

  /// Whether the chat list or the panel scrolls now, as the chat screen and
  /// its input set report it: the texture pool of [assets] waits with its
  /// creations while it does (ADR 043, "Pool").
  final ScrollingSurfaces scrolling;

  /// The Giphy clips this session lists and plays, or null without a key.
  final GiphyContent? giphy;

  /// The local corpus of Lottie stickers; [CorpusStickerPack.none] when the
  /// build has none.
  final CorpusStickerPack corpus;

  /// What the host knows of a key beyond the bundled packs: the corpus and
  /// the Giphy clips this session listed.
  final DescribeContent describe;

  /// The Giphy API key the build was given with
  /// `--dart-define=GIPHY_API_KEY=...`, or empty. It is only ever read here,
  /// handed to the client, and never logged.
  static const String giphyApiKeyDefine = String.fromEnvironment(
    'GIPHY_API_KEY',
  );

  /// The line Giphy's terms ask to be shown with its content.
  static const String giphyAttribution = 'Powered by GIPHY';

  /// The media store's folder of Giphy's stills and clips.
  static const String giphyFolder = 'giphy';

  /// The media store's folder of the rendered Lottie frames.
  static const String lottieFramesFolder = 'lottie_frames';

  static ContentFetcher _contentFetcher(
    GiphyContent? giphy,
    CorpusStickerPack corpus,
    AssetBundle bundle,
  ) {
    final bundled = corpus.fetcher(otherwise: BundledPacks.fetcher(bundle));
    return giphy == null ? bundled : giphy.fetcher(otherwise: bundled);
  }

  /// Which glyphs the system cannot draw.
  final MissingGlyphProbe glyphProbe;

  /// The art version in the atlas cache key: the probe's, unless the host
  /// overrode it.
  final GlyphArtVersionSource glyphArtVersion;

  /// Shows the probe each cell the bake draws.
  final GlyphBakeObserver glyphBakeObserver;

  /// Where baked pages persist, or null to bake in memory every launch.
  final GlyphCacheStore? glyphCache;

  final List<CollectionSource> _pageParts;
  final PlaybackClock _clock;
  final LottiePlayback? _lottiePlayback;
  final MediaDiskCache? _mediaCache;
  final VideoPlayback? _videoPlayback;
  final AssetPipeline _pipeline;
  final WidgetsPlaybackLifecycleSource _lifecycleSource;
  final ValueNotifier<bool> _reducedMotion;
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

  /// Starts closing [playback] and reports a failure instead of leaving it
  /// to an unhandled future: a close is not awaited at shutdown, and one
  /// that fails has no caller to tell. Each path calls it once.
  static void _closePlayback(LottiePlayback playback) =>
      _closeReporting(playback.close(), 'the Lottie playback');

  /// [_closePlayback] for the video playback.
  static void _closeVideoPlayback(VideoPlayback playback) =>
      _closeReporting(playback.close(), 'the video playback');

  static void _closeReporting(Future<void> closing, String what) {
    unawaited(
      closing.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'chat_scroll_view_example',
              context: ErrorDescription('while closing $what'),
            ),
          );
        },
      ),
    );
  }

  /// Frees what [create] made, in the reverse of the order it made it.
  /// Idempotent. What was handed in is left as it is.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _webProbePass?.cancel();
    stickerPageSource.dispose();
    gifPageSource.dispose();
    for (final part in _pageParts) {
      part.dispose();
    }
    emojiPageSource.dispose();
    emojiSearch.dispose();
    emojiSource.dispose();
    recentsShown.dispose();
    libraryShown.dispose();
    packs.dispose();
    glyphProbe.dispose();
    // The activity first: it clears the layers it set on the clock.
    activity.dispose();
    _reducedMotion.dispose();
    lowPower.dispose();
    _lifecycleSource.dispose();
    assets.dispose();
    // The scope leaves its texture pool to its owner.
    assets.textures?.dispose();
    scrolling.dispose();
    _glyphFontsReady.dispose();
    _pipeline.dispose();
    // After the scope and the pipeline: dropping their entries frees the
    // animations the decoder made, through its engine.
    if (_lottiePlayback case final playback?) _closePlayback(playback);
    if (_videoPlayback case final playback?) _closeVideoPlayback(playback);
    // Its sweeps stop; its files stay for the next launch.
    _mediaCache?.dispose();
    _clock.dispose();
    memoryPressure.dispose();
    largeEmoji.dispose();
    preferences.dispose();
    previews.dispose();
    // Commits what is still in an undo window.
    library.dispose();
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

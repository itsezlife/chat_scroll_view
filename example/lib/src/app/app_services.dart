import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/glyph_atlas.dart';
import 'package:chat_scroll_view_example/src/app/lottie_playback.dart';
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
import 'package:chat_scroll_view_example/src/features/chat/data/giphy_client.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/giphy_content.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/giphy_gif_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/joined_collection_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/large_emoji_setting.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/recent_content_source.dart';
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
///    [keyboardHeights], [dockWidths], [centerBands], [drafts] and
///    [largeEmoji];
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
///    [gifPageSource] of the two dedicated pages, over the recent stickers
///    and GIFs (a view of the recents that catches up when the panel opens).
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
    required this.giphy,
    required this.corpus,
    required this.describe,
    required this.scrolling,
    required List<CollectionSource> pageParts,
    required CollectionSource animatedEmoji,
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
  }) : _animatedEmoji = animatedEmoji,
       _pageParts = pageParts,
       _clock = clock,
       _lottiePlayback = lottiePlayback,
       _videoPlayback = videoPlayback,
       _pipeline = pipeline,
       _lifecycleSource = lifecycleSource,
       _reducedMotion = reducedMotion,
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
  /// language set of emoji search, the app language first. [startLottie]
  /// starts the Lottie decoder (the platform's unless a test passes its own);
  /// it answers null where there is none, and then nothing is registered.
  /// [lottieCacheDirectory] is the folder its rendered frames are kept in
  /// between launches (null: in memory only, as in a test). [startVideo]
  /// does the same for the video decoder: the platform's unless a test passes
  /// its own, and null where there is none.
  ///
  /// [giphyApiKey] turns the GIF page's Giphy source on (see
  /// [giphyApiKeyDefine]); empty leaves the page with the recent GIFs alone.
  /// [giphyHttpClient] is the transport it sends through, closed by the
  /// services only if they made it. [giphyStillDirectory] is the folder the
  /// clips' stills are kept in between launches, up to [giphyStillDiskBytes]
  /// (null: in memory only, as in a test). [corpus] is the local sticker corpus; null
  /// looks for one in the app bundle and in the `CHAT_CORPUS_DIR` directory.
  static Future<AppServices> create({
    KeyValueStore? keyValueStore,
    EmojiAssetLoader? assetLoader,
    GlyphCacheStore? glyphCache,
    GlyphArtVersionSource? glyphArtVersion,
    List<String> languages = const <String>['ru', 'en'],
    RichClipboard clipboard = const SystemRichClipboard(),
    LottiePlaybackStarter startLottie = startLottiePlayback,
    String? lottieCacheDirectory,
    VideoPlaybackStarter startVideo = startVideoPlayback,
    String giphyApiKey = giphyApiKeyDefine,
    http.Client? giphyHttpClient,
    Future<String?>? giphyStillDirectory,
    CorpusStickerPack? corpus,
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
      final (
        recents,
        preferences,
        keyboardHeights,
        dockWidths,
        largeEmoji,
      ) = await (
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
        LargeEmojiSetting.load(
          storage,
        ).then((setting) => owned(setting, (setting) => setting.dispose())),
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
          ? createPlatformFrameTextureHost()
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
        cacheDirectory: lottieCacheDirectory,
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
          '(--dart-define=GIPHY_API_KEY=...); the GIF page lists the recent '
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
        // The stills' disk tier is the fetcher's (ADR 022). It sits under
        // the transport, not over it: a still found on disk is no request,
        // so the lab's tape neither records nor replays it.
        final stillDirectory = await giphyStillDirectory;
        giphy = GiphyContent(
          GiphyClient(apiKey: giphyApiKey, client: transport),
          stillDisk: stillDirectory == null
              ? null
              : ByteCache.directory(
                  stillDirectory,
                  budgetBytes: giphyStillDiskBytes,
                ),
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
      // Dust and emoji alike stop when the window loses focus, is minimised,
      // is covered by a dialog, or the switch below says power is short.
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
      final animatedEmoji = owned(
        AnimatedEmojiPack.source(),
        (source) => source.dispose(),
      );
      // The animated emoji are emoji (custom emoji, picked on this page), not
      // stickers: they stay. The demo sticker packs are not listed here.
      final emojiPageSource = owned(
        JoinedCollectionSource([emojiSource, animatedEmoji]),
        (source) => source.dispose(),
      );

      // The stickers page: the recent stickers, then the local corpus, a pack
      // each. Without a corpus (as on CI) the recents are all it lists; the
      // bundled demo packs are content of the showcase chat, not of the panel.
      final recentStickers = owned(
        RecentContentSource(
          recents: recentsShown,
          kind: SemanticKind.sticker,
          describe: describe,
        ),
        (source) => source.dispose(),
      );
      final corpusSources = [
        for (final source in corpusPacks.sources())
          owned(source, (source) => source.dispose()),
      ];
      final stickerPageSource = owned(
        JoinedCollectionSource([recentStickers, ...corpusSources]),
        (source) => source.dispose(),
      );
      // The GIF page: the recent GIFs, then Giphy's trending when there is a
      // key. Offline, trending fails and the page shows its failure line with
      // a retry; without a key the recents are all it lists. No bundled clip
      // is listed beneath either.
      final recentGifs = owned(
        RecentContentSource(
          recents: recentsShown,
          kind: SemanticKind.gif,
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
      final gifPageSource = owned(
        JoinedCollectionSource([recentGifs, ?giphyTrending]),
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
        giphy: giphy,
        corpus: corpusPacks,
        describe: describe,
        scrolling: scrolling,
        pageParts: [
          recentStickers,
          recentGifs,
          ?giphyTrending,
          ...corpusSources,
        ],
        animatedEmoji: animatedEmoji,
        clock: clock,
        lottiePlayback: lottiePlayback,
        videoPlayback: videoPlayback,
        glyphProbe: probe.probe,
        glyphArtVersion: glyphArtVersion ?? probe.artVersion,
        glyphBakeObserver: probe.bakeObserver,
        glyphCache: glyphCache,
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
  /// pack of animated emoji. It owns none.
  final CollectionSource emojiPageSource;

  /// What the stickers page lists: the recent stickers, then the packs of
  /// the local [corpus]. It owns none.
  final CollectionSource stickerPageSource;

  /// What the GIF page lists: the recent GIFs, then Giphy's trending clips
  /// when there is a key. It owns none.
  final CollectionSource gifPageSource;

  /// Search of Giphy for the GIF page, or null without a key.
  final SearchSource? gifSearch;

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

  /// How much of the disk Giphy's stills may take: 16 MB. A still is the
  /// clip's 100 px wide frame, a few KB, so this keeps a few thousand: more
  /// than a long scroll of trending and searches, little next to the clips.
  static const int giphyStillDiskBytes = 16 << 20;

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

  final CollectionSource _animatedEmoji;
  final List<CollectionSource> _pageParts;
  final PlaybackClock _clock;
  final LottiePlayback? _lottiePlayback;
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
    _animatedEmoji.dispose();
    emojiSearch.dispose();
    emojiSource.dispose();
    recentsShown.dispose();
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
    _clock.dispose();
    memoryPressure.dispose();
    largeEmoji.dispose();
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

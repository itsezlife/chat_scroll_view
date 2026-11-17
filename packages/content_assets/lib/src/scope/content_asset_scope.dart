import 'package:content_assets/src/glyph/glyph_binding.dart';
import 'package:content_assets/src/identity/content_media.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart' show Listenable, ValueListenable;
import 'package:glyph_atlas/glyph_atlas.dart';
import 'package:mpx_core/mpx_core.dart';

/// Where the chat's surfaces attach content by [ContentKey]: media goes to
/// the media core's [AssetCacheScope], unicode glyphs to the glyph atlas.
///
/// The media core keys media by `MediaKey` and has no glyph route: a glyph has
/// nothing to fetch or decode, and its pixels belong to the atlas. This scope
/// is the one place the chat splits the two, so a panel cell, an inline embed
/// or a preview attaches any content the same way:
///
/// - A unicode key gets a [GlyphBinding] on [glyphSource]: a baked sprite, a
///   circle until its page exists, or the glyph drawn as text while the
///   source does not make it wait. Without a source glyphs are drawn as text
///   (a platform that bakes nothing, or a host whose atlas does not exist
///   yet).
/// - Any other key attaches to [media] under its media key
///   (`ContentKeyMedia.mediaKey`).
///
/// The strategy follows the source for the life of a glyph, not only when it
/// attaches: glyphs drawn as text move onto an atlas registered later, and
/// glyphs on an atlas that is dropped go back to text (never to a placeholder
/// that stays).
///
/// The host owns the source and the signals it passes, and [media] unless the
/// scope made it ([ContentAssetScope.withMedia]); [dispose] detaches the glyph
/// bindings and stops listening.
final class ContentAssetScope {
  /// A scope over [media] that draws glyphs from [glyphSource], or as text.
  ///
  /// [systemFonts] is the engine's signal that its fonts changed
  /// (`PaintingBinding.systemFonts`): glyphs drawn as text lay out again on
  /// it, since a browser fetches the font that draws an emoji only once it
  /// meets one. [textGlyphsReady] says whether the fonts that draw glyphs as
  /// text are there: until it is true they are placeholders, not
  /// missing-glyph boxes. [glyphPlaceholder] is what a glyph paints before it
  /// has a sprite or text (a circle by default; media has the media scope's
  /// placeholder).
  ContentAssetScope({
    required this.media,
    GlyphSpriteSource? glyphSource,
    Listenable? systemFonts,
    ValueListenable<bool>? textGlyphsReady,
    this.placeholder = const CirclePlaceholder(),
  }) : _glyphSource = glyphSource,
       _systemFonts = systemFonts,
       _textGlyphsReady = textGlyphsReady,
       _ownsMedia = false {
    _listen();
  }

  /// A scope over a media cache of its own, made from [producer],
  /// [budgets], [clock], [memoryPressure], [mediaPlaceholder], [textures] and
  /// [autoDownload] (see [AssetCacheScope]); [dispose] disposes it too. The
  /// glyph parameters are the main constructor's.
  ///
  /// [autoDownload] decides which missing content downloads by itself; the
  /// default downloads everything. A composition root that builds its media
  /// stack passes the stack's policy, and the stack's preview store goes to
  /// the stack's producer, which reads and derives previews.
  ContentAssetScope.withMedia({
    AssetProducer? producer,
    AssetCacheBudgets budgets = AssetCacheBudgets.defaults,
    PlaybackClock? clock,
    Listenable? memoryPressure,
    AssetPaintable? mediaPlaceholder,
    FrameTexturePool? textures,
    AutoDownloadPolicy autoDownload = AutoDownloadPolicy.always,
    GlyphSpriteSource? glyphSource,
    Listenable? systemFonts,
    ValueListenable<bool>? textGlyphsReady,
    this.placeholder = const CirclePlaceholder(),
  }) : media = AssetCacheScope(
         producer: producer,
         budgets: budgets,
         clock: clock,
         memoryPressure: memoryPressure,
         placeholder: mediaPlaceholder,
         textures: textures,
         autoDownload: autoDownload,
       ),
       _glyphSource = glyphSource,
       _systemFonts = systemFonts,
       _textGlyphsReady = textGlyphsReady,
       _ownsMedia = true {
    _listen();
  }

  void _listen() {
    _glyphSource?.addPageListener(_onGlyphPage);
    _systemFonts?.addListener(_onSystemFonts);
    _textGlyphsReady?.addListener(_onTextGlyphsReady);
  }

  /// The media core's scope every non-glyph key attaches to.
  final AssetCacheScope media;

  /// What a glyph binding paints before it has a sprite or text.
  final AssetPaintable placeholder;

  final bool _ownsMedia;
  final Listenable? _systemFonts;
  final ValueListenable<bool>? _textGlyphsReady;
  GlyphSpriteSource? _glyphSource;
  final Set<GlyphBinding> _glyphs = {};
  bool _disposed = false;

  /// The clock every animated binding advances by; the media scope's.
  PlaybackClock get clock => media.clock;

  /// What a media binding paints before its entry has any stage.
  AssetPaintable get mediaPlaceholder => media.placeholder;

  /// The platform textures playing media may take, or null.
  FrameTexturePool? get textures => media.textures;

  /// What decides whether missing media downloads by itself, weighed per
  /// surface by the tag it attaches with (`ContentAssetView.downloadContext`);
  /// the media scope's. A glyph never downloads.
  AutoDownloadPolicy get autoDownload => media.autoDownload;

  /// The atlas unicode keys bind to, or null (glyphs drawn as text).
  GlyphSpriteSource? get glyphSource => _glyphSource;

  /// Registers (or, with null, removes) the source glyph bindings read.
  ///
  /// Every glyph binding already attached moves in place: it gives back its
  /// hold on the old source, takes one on the new (or draws as text without
  /// one) and signals its listeners. The scope never disposes a source. After
  /// [dispose] the value is only remembered.
  set glyphSource(GlyphSpriteSource? value) {
    if (identical(_glyphSource, value)) return;
    if (_disposed) {
      _glyphSource = value;
      return;
    }
    _glyphSource?.removePageListener(_onGlyphPage);
    _glyphSource = value;
    value?.addPageListener(_onGlyphPage);
    for (final binding in List<GlyphBinding>.of(_glyphs)) {
      binding.rebind(value);
    }
  }

  /// Attaches [key] decoded as [spec], to be used as [profile] says.
  ///
  /// [downloadContext] is the class of the surface the content is shown in,
  /// which [autoDownload] weighs for media (`AssetCacheScope.attach`); a
  /// glyph has nothing to download and ignores it.
  ///
  /// Throws a [StateError] after [dispose]: a surface that outlives its scope
  /// is a lifecycle bug to see, not to absorb.
  AssetBinding attach(
    ContentKey key,
    AssetSpec spec,
    AssetProfile profile, {
    AutoDownloadContext? downloadContext,
  }) {
    if (_disposed) {
      throw StateError('ContentAssetScope.attach called after dispose.');
    }
    if (key case ContentKey$Unicode(:final sequence)) {
      final binding = GlyphBinding(
        key: key.mediaKey,
        glyph: sequence,
        spec: spec,
        profile: profile,
        placeholder: placeholder,
        source: _glyphSource,
        fontsReady: _textGlyphsReady,
        onDetach: _glyphs.remove,
      );
      _glyphs.add(binding);
      return binding;
    }
    return media.attach(
      key.mediaKey,
      spec,
      profile,
      downloadContext: downloadContext,
    );
  }

  /// Whether a binding of [key] at [spec] is attached: a glyph binding, or
  /// one of the media entry.
  bool isAttached(ContentKey key, AssetSpec spec) => switch (key) {
    ContentKey$Unicode() => _glyphs.any(
      (binding) => binding.key == key.mediaKey && binding.spec == spec,
    ),
    _ => media.isAttached(key.mediaKey, spec),
  };

  /// Holds every media binding but the foreground ones until the hold is
  /// released (`AssetCacheScope.holdBackground`). Glyphs are stills: a hold
  /// changes nothing for them.
  AssetBackgroundHold holdBackground() => media.holdBackground();

  /// Whether a background hold is on.
  bool get isBackgroundHeld => media.isBackgroundHeld;

  /// How many glyph bindings are attached.
  int get glyphBindingCount => _glyphs.length;

  /// Detaches every glyph binding and stops listening, and disposes [media]
  /// when the scope made it. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _glyphSource?.removePageListener(_onGlyphPage);
    _systemFonts?.removeListener(_onSystemFonts);
    _textGlyphsReady?.removeListener(_onTextGlyphsReady);
    for (final binding in List<GlyphBinding>.of(_glyphs)) {
      binding.detach();
    }
    _glyphs.clear();
    if (_ownsMedia) media.dispose();
  }

  // Every glyph binding repaints when any page changes: which cells are on a
  // page is the source's to know.
  void _onGlyphPage(int pageIndex) {
    for (final binding in List<GlyphBinding>.of(_glyphs)) {
      binding.pageChanged();
    }
  }

  void _onSystemFonts() {
    for (final binding in List<GlyphBinding>.of(_glyphs)) {
      binding.systemFontsChanged();
    }
  }

  void _onTextGlyphsReady() {
    for (final binding in List<GlyphBinding>.of(_glyphs)) {
      binding.fontsReadyChanged();
    }
  }
}

import 'dart:ui';

import 'package:catalog_assets/src/atlas/atlas_sprite.dart';
import 'package:catalog_assets/src/glyph/glyph_sprite_source.dart';

/// A [GlyphSpriteSource] over a fixed glyph list whose pages a test bakes and
/// releases by hand, with hold counts it can read.
///
/// Glyph `i` of the list sits on page `i ~/ glyphsPerPage`. A page has a
/// sprite for its glyphs only while baked. The glyphs of [onDemand] are
/// planned but do not make a surface wait ([waitsForSprite]); [learn] adds a
/// glyph to the end of the plan, as a source that grows does.
final class FakeGlyphSpriteSource implements GlyphSpriteSource {
  /// Creates a source for [glyphs], [glyphsPerPage] to a page.
  FakeGlyphSpriteSource(
    List<String> glyphs, {
    this.glyphsPerPage = 2,
    Set<String> onDemand = const {},
  }) : assert(glyphsPerPage > 0, 'a page holds at least one glyph'),
       glyphs = List.of(glyphs),
       onDemand = Set.of(onDemand);

  /// The planned glyphs, in page order.
  final List<String> glyphs;

  /// The planned glyphs a surface does not wait for.
  final Set<String> onDemand;

  /// Adds [glyph] to the end of the plan, baked on demand.
  void learn(String glyph) {
    if (glyphs.contains(glyph)) return;
    glyphs.add(glyph);
    onDemand.add(glyph);
  }

  /// Glyphs on each page.
  final int glyphsPerPage;

  final Map<int, Image> _baked = {};
  final Map<int, int> _holds = {};
  final List<void Function(int)> _listeners = [];
  bool _disposed = false;

  /// The page [glyph] is on, or null when it is not planned.
  int? pageOf(String glyph) {
    final at = glyphs.indexOf(glyph);
    return at < 0 ? null : at ~/ glyphsPerPage;
  }

  /// Holds currently covering [pageIndex].
  int holdCount(int pageIndex) => _holds[pageIndex] ?? 0;

  /// Whether [pageIndex] is baked and loaded.
  bool isBaked(int pageIndex) => _baked.containsKey(pageIndex);

  /// Listeners currently registered.
  int get listenerCount => _listeners.length;

  /// Makes [pageIndex] drawable and tells the listeners.
  void bakePage(int pageIndex) {
    if (_disposed) return;
    _baked[pageIndex] ??= _blankImage();
    _notify(pageIndex);
  }

  /// Drops [pageIndex]'s image as memory pressure would and tells the
  /// listeners. Hold counts stay.
  void releasePage(int pageIndex) {
    _baked.remove(pageIndex)?.dispose();
    _notify(pageIndex);
  }

  /// Ends the source: no sprites afterwards, no listener calls.
  void dispose() {
    _disposed = true;
    for (final image in _baked.values) {
      image.dispose();
    }
    _baked.clear();
    _listeners.clear();
  }

  @override
  AtlasSprite? spriteOf(String glyph) {
    if (_disposed) return null;
    final at = glyphs.indexOf(glyph);
    if (at < 0) return null;
    final page = _baked[at ~/ glyphsPerPage];
    if (page == null) return null;
    return AtlasSprite(
      pageIndex: at ~/ glyphsPerPage,
      page: page,
      source: const Rect.fromLTWH(0, 0, 1, 1),
    );
  }

  @override
  SpritePageHold? holdPageOf(String glyph) {
    final page = pageOf(glyph);
    if (_disposed || page == null) return null;
    _holds[page] = holdCount(page) + 1;
    return _FakeHold(() => _holds[page] = holdCount(page) - 1);
  }

  @override
  bool waitsForSprite(String glyph) =>
      !_disposed && glyphs.contains(glyph) && !onDemand.contains(glyph);

  @override
  void addPageListener(void Function(int pageIndex) listener) =>
      _listeners.add(listener);

  @override
  void removePageListener(void Function(int pageIndex) listener) =>
      _listeners.remove(listener);

  void _notify(int pageIndex) {
    for (final listener in List.of(_listeners)) {
      listener(pageIndex);
    }
  }

  static Image _blankImage() {
    final recorder = PictureRecorder();
    Canvas(recorder).drawColor(const Color(0xFF000000), BlendMode.src);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(2, 2);
    picture.dispose();
    return image;
  }
}

final class _FakeHold implements SpritePageHold {
  _FakeHold(this._onRelease);

  void Function()? _onRelease;

  @override
  bool get isReleased => _onRelease == null;

  @override
  void release() {
    final onRelease = _onRelease;
    _onRelease = null;
    onRelease?.call();
  }
}

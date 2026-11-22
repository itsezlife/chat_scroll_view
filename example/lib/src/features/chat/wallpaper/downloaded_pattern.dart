import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:http_bytes_cache/http_bytes_cache.dart';
import 'package:mpx_svg/mpx_svg.dart';
import 'package:vector_graphics/vector_graphics.dart';

/// Wallpaper artwork that arrives at run time: a pattern downloaded as
/// gzipped SVG, compiled to the vector form the wallpaper draws.
///
/// The wallpaper package takes artwork as a `BytesLoader` of that form and
/// stays free of the SVG compiler; this host loader fills it. It goes
/// through the same compiler, caps and sanitizer as every other SVG
/// (`SvgCompiler`): a pattern is inflated to `SvgLimits.maxInflatedBytes` at
/// most, and one the limits refuse fails, so the wallpaper keeps its bare
/// fill.
///
/// The compiled form is kept in [compiled] under the pattern's slug, so a
/// later start draws the pattern without downloading or parsing it again
/// (a 100 KB pattern is tens of milliseconds of parse on a phone).
final class DownloadedPattern extends BytesLoader {
  /// Artwork of [slug], fetched by [download] (the gzipped SVG, through the
  /// host's bytes cache), compiled by [compiler] and kept in [compiled].
  const DownloadedPattern({
    required this.slug,
    required this.download,
    required this.compiled,
    this.compiler = const SvgCompiler(),
  });

  /// The pattern's slug: its identity, and its compiled form's key.
  final String slug;

  /// The pattern's bytes: gzipped SVG, or plain SVG.
  final Future<Uint8List> Function() download;

  /// Where the compiled form is kept between starts.
  final IBytesCache compiled;

  /// Sanitizes and compiles the downloaded pattern.
  final SvgCompiler compiler;

  BytesCacheKey get _key => BytesCacheKey('wallpaper-pattern-$slug');

  @override
  Future<ByteData> loadBytes(BuildContext? context) async {
    if (await compiled.read(_key) case final kept?) return _view(kept);
    final form = await compiler
        .compile(SvgSource.bytes(await download()))
        .result;
    if (form == null) throw StateError('Pattern "$slug" compile was cancelled');
    await compiled.write(_key, form);
    return _view(form);
  }

  static ByteData _view(Uint8List bytes) => ByteData.sublistView(bytes);

  /// One key per slug, so the drawing library loads a pattern once however
  /// many loaders name it.
  @override
  Object cacheKey(BuildContext? context) => (DownloadedPattern, slug);
}

import 'dart:async';
import 'dart:ui' as ui;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Loads the bytes of a bundled asset; tests replace it.
typedef IconArtLoader = Future<ByteData> Function(String key);

/// The reference client's icon art bundled with this package, as chrome icon
/// painters: single-colour alpha masks drawn tinted with the icon's colour.
///
/// Decoded images are shared by every scope for the life of the process: a
/// few kilobytes each, decoded once however often the surface that shows
/// them opens.
abstract final class IconArt {
  static final _cache = <String, Future<ui.Image>>{};
  static final _decoded = <String, ui.Image>{};
  static final _painters = Expando<ChromeIconPainter>('IconArt painter');

  /// The decoded art at bundle [key].
  static Future<ui.Image> imageFor(String key) =>
      _cache.putIfAbsent(key, () => _fromBundle(key));

  /// The art at [key] if it has been decoded, for a surface that should
  /// paint it from its first frame.
  static ui.Image? decodedFor(String key) => _decoded[key];

  /// Starts decoding the art at [keys], so a surface that opens later draws
  /// it at once. A failure is left for the surface's own load to report.
  static void warm(Iterable<String> keys) {
    for (final key in keys) {
      unawaited(imageFor(key).then<void>((_) {}, onError: (Object _) {}));
    }
  }

  /// Forgets every decoded image, so the next [imageFor] reads the bundle
  /// again.
  ///
  /// For tests that share a process: a widget test that opened a scope under
  /// fake async leaves a decode that never completes in the cache, which a
  /// later test awaiting [imageFor] would wait on for good. Not exported:
  /// tests reach it through `EmojiTabIcons.clearCache`.
  static void clearCache() {
    _cache.clear();
    _decoded.clear();
  }

  static Future<ui.Image> _fromBundle(String key) async {
    try {
      final image = await decode(rootBundle.load(key));
      _decoded[key] = image;
      return image;
    } on Object {
      // A failure is not remembered: the next scope tries again.
      unawaited(_cache.remove(key));
      rethrow;
    }
  }

  /// Decodes [bytes] into an image the caller owns.
  static Future<ui.Image> decode(Future<ByteData> bytes) async {
    final data = await bytes;
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  /// A painter that draws [image] tinted with the icon colour; the same
  /// painter for the same image, so a registry rebuilt from the same art is
  /// equal and its icons do not repaint.
  static ChromeIconPainter painterFor(ui.Image image) =>
      _painters[image] ??= ChromeIconPainter.paint((canvas, size, color) {
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          Offset.zero & size,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..colorFilter = ColorFilter.mode(color, BlendMode.srcIn),
        );
      });
}

/// Registers bundled [IconArt] as chrome icons for the subtree, and loads
/// it.
///
/// Art already decoded paints from the first frame; the rest shows the
/// registry's fallback glyph until it arrives. A host restyles an icon by
/// registering a painter for its id in a [ChromeIconScope] above this one:
/// an id the enclosing registry already paints keeps that painter.
///
/// With a [loader] (a test's) the art is decoded per scope and released with
/// it.
class IconArtScope extends StatefulWidget {
  /// Provides the art at [assets] (bundle keys by icon id) to [child].
  const IconArtScope({
    required this.assets,
    required this.child,
    this.loader,
    super.key,
  });

  /// The bundle key of each icon's art.
  final Map<ChromeIconId, String> assets;

  /// The subtree that shows the icons.
  final Widget child;

  /// Where the art's bytes come from; the asset bundle when null.
  final IconArtLoader? loader;

  @override
  State<IconArtScope> createState() => _IconArtScopeState();
}

class _IconArtScopeState extends State<IconArtScope> {
  final _images = <ChromeIconId, ui.Image>{};
  final _owned = <ui.Image>[];
  var _painters = const <ChromeIconId, ChromeIconPainter>{};
  var _disposed = false;

  @override
  void initState() {
    super.initState();
    for (final MapEntry(key: id, value: key) in widget.assets.entries) {
      if (widget.loader == null) {
        if (IconArt.decodedFor(key) case final image?) {
          _images[id] = image;
          continue;
        }
      }
      unawaited(_load(id, key));
    }
    _painters = _paintersOf(_images);
  }

  static Map<ChromeIconId, ChromeIconPainter> _paintersOf(
    Map<ChromeIconId, ui.Image> images,
  ) => {
    for (final entry in images.entries)
      entry.key: IconArt.painterFor(entry.value),
  };

  Future<void> _load(ChromeIconId id, String key) async {
    final loader = widget.loader;
    try {
      final image = switch (loader) {
        final loader? => await IconArt.decode(loader(key)),
        null => await IconArt.imageFor(key),
      };
      if (_disposed) {
        if (loader != null) image.dispose();
        return;
      }
      if (loader != null) _owned.add(image);
      _images[id] = image;
      setState(() => _painters = _paintersOf(_images));
    } on Object catch (error, stack) {
      // Missing art leaves the fallback glyph; it is reported, not thrown
      // into the frame.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'panel_pages',
          context: ErrorDescription('while loading the icon art $key'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // Images of the shared cache outlive the scope; only decoded-by-loader
    // images are this scope's to release.
    for (final image in _owned) {
      image.dispose();
    }
    _owned.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // An icon the enclosing registry already paints is the host's: its
    // registration wins over the art.
    final enclosing = ChromeIconScope.of(context);
    return ChromeIconScope(
      icons: {
        for (final entry in _painters.entries)
          if (!enclosing.contains(entry.key)) entry.key: entry.value,
      },
      child: widget.child,
    );
  }
}

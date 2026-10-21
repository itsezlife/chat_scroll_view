import 'dart:async';
import 'dart:ui' as ui;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Loads the bytes of a bundled asset; tests replace it.
typedef EmojiTabAssetLoader = Future<ByteData> Function(String key);

/// The pictures of the category strip, as chrome icon painters.
///
/// The art is the reference client's: single-colour alpha masks bundled with
/// this package and drawn tinted with the icon's colour.
abstract final class EmojiTabIcons {
  /// The package the art is bundled in.
  static const String package = 'panel_pages';

  /// The asset key of each tab's art.
  static const Map<ChromeIconId, String> assets = {
    ChromeIconId('emoji.recents'): 'msg_emoji_recent',
    ChromeIconId('emoji.smileys'): 'msg_emoji_smiles',
    ChromeIconId('emoji.animals'): 'msg_emoji_cat',
    ChromeIconId('emoji.food'): 'msg_emoji_food',
    ChromeIconId('emoji.activities'): 'msg_emoji_activities',
    ChromeIconId('emoji.travel'): 'msg_emoji_travel',
    ChromeIconId('emoji.objects'): 'msg_emoji_objects',
    ChromeIconId('emoji.symbols'): 'msg_emoji_other',
  };

  /// The bundle key of [id]'s art, or null for an id that is not a tab's.
  static String? assetKeyOf(ChromeIconId id) {
    final name = assets[id];
    return switch (name) {
      final name? => 'packages/$package/assets/emoji_tabs/$name.webp',
      null => null,
    };
  }

  static final _cache = <String, Future<ui.Image>>{};

  /// The decoded art at bundle [key], shared by every scope for the life of the
  /// process: eight images of a few kilobytes, decoded once however often the
  /// panel opens, so the open does not pay for them again.
  static Future<ui.Image> imageFor(String key) =>
      _cache.putIfAbsent(key, () => _fromBundle(key));

  /// Forgets every decoded image, so the next [imageFor] reads the bundle
  /// again.
  ///
  /// For tests that share a process: a widget test that opened a scope under
  /// fake async leaves a decode that never completes in the cache, which a
  /// later test awaiting [imageFor] would wait on for good.
  @visibleForTesting
  static void clearCache() => _cache.clear();

  static Future<ui.Image> _fromBundle(String key) async {
    try {
      return await _decode(rootBundle.load(key));
    } on Object {
      // A failure is not remembered: the next scope tries again.
      unawaited(_cache.remove(key));
      rethrow;
    }
  }

  /// Decodes [bytes] into an image the caller owns.
  static Future<ui.Image> decode(Future<ByteData> bytes) => _decode(bytes);

  static Future<ui.Image> _decode(Future<ByteData> bytes) async {
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

  /// A painter that draws [image] tinted with the icon colour.
  ///
  /// A new painter per image: painters are equal by their callback, so a scope
  /// that gets one of these after the art loaded is a different registry and
  /// icons repaint.
  static ChromeIconPainter painterFor(ui.Image image) =>
      ChromeIconPainter.paint((canvas, size, color) {
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

/// Registers the strip's pictures as chrome icons for the subtree, and loads
/// them.
///
/// Until the art is decoded the tabs show the registry's fallback glyph, and
/// they repaint as each picture arrives. A host that restyles a tab registers
/// a painter for its id in a [ChromeIconScope] **below** this one.
///
/// The art is decoded once per process and shared; a `loader` of a test is
/// decoded per scope and released with it.
class EmojiTabIconScope extends StatefulWidget {
  /// Provides the strip's icons to [child].
  const EmojiTabIconScope({required this.child, this.loader, super.key});

  /// The subtree that shows the icons.
  final Widget child;

  /// Where the art's bytes come from; the asset bundle when null.
  final EmojiTabAssetLoader? loader;

  @override
  State<EmojiTabIconScope> createState() => _EmojiTabIconScopeState();
}

class _EmojiTabIconScopeState extends State<EmojiTabIconScope> {
  final _images = <ChromeIconId, ui.Image>{};
  final _owned = <ui.Image>[];
  var _painters = const <ChromeIconId, ChromeIconPainter>{};
  var _disposed = false;

  @override
  void initState() {
    super.initState();
    for (final id in EmojiTabIcons.assets.keys) {
      unawaited(_load(id));
    }
  }

  Future<void> _load(ChromeIconId id) async {
    final key = EmojiTabIcons.assetKeyOf(id)!;
    final loader = widget.loader;
    try {
      final image = switch (loader) {
        final loader? => await EmojiTabIcons.decode(loader(key)),
        null => await EmojiTabIcons.imageFor(key),
      };
      if (_disposed) {
        if (loader != null) image.dispose();
        return;
      }
      if (loader != null) _owned.add(image);
      _images[id] = image;
      setState(() {
        _painters = {
          for (final entry in _images.entries)
            entry.key: EmojiTabIcons.painterFor(entry.value),
        };
      });
    } on Object catch (error, stack) {
      // A missing picture leaves the fallback glyph; it is reported, not
      // thrown into the frame.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'panel_pages',
          context: ErrorDescription('while loading the emoji tab art $key'),
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
  Widget build(BuildContext context) =>
      ChromeIconScope(icons: _painters, child: widget.child);
}

import 'dart:ui' as ui;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_pages/src/assets/icon_art.dart';

/// Loads the bytes of a bundled asset; tests replace it.
typedef EmojiTabAssetLoader = IconArtLoader;

/// The pictures of the category strip, and of the favourites tab of the
/// stickers page's strip, as chrome icon painters.
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
    // The stickers page's favourites tab (`stickerIcons[1]` of `EmojiView`).
    ChromeIconId('stickers.favourites'): 'emoji_tabs_faves',
  };

  /// The bundle key of [id]'s art, or null for an id that is not a tab's.
  static String? assetKeyOf(ChromeIconId id) {
    final name = assets[id];
    return switch (name) {
      final name? => 'packages/$package/assets/emoji_tabs/$name.webp',
      null => null,
    };
  }

  /// The decoded art at bundle [key], shared by every scope for the life of the
  /// process: eight images of a few kilobytes, decoded once however often the
  /// panel opens, so the open does not pay for them again.
  static Future<ui.Image> imageFor(String key) => IconArt.imageFor(key);

  /// Forgets every decoded image, so the next [imageFor] reads the bundle
  /// again.
  ///
  /// For tests that share a process: a widget test that opened a scope under
  /// fake async leaves a decode that never completes in the cache, which a
  /// later test awaiting [imageFor] would wait on for good.
  @visibleForTesting
  static void clearCache() => IconArt.clearCache();

  /// Decodes [bytes] into an image the caller owns.
  static Future<ui.Image> decode(Future<ByteData> bytes) =>
      IconArt.decode(bytes);

  /// A painter that draws [image] tinted with the icon colour.
  static ChromeIconPainter painterFor(ui.Image image) =>
      IconArt.painterFor(image);
}

/// Registers the strip's pictures as chrome icons for the subtree, and loads
/// them.
///
/// Art decoded earlier (by another scope) paints from the first frame; until
/// the rest is decoded those tabs show the registry's fallback glyph, and
/// they repaint as each picture arrives. A host restyles a tab by registering
/// a painter for its id in a [ChromeIconScope] above this one (the strip
/// mounts a scope of its own, so above is the only place a host can reach):
/// an id the enclosing registry already paints keeps that painter.
///
/// The art is decoded once per process and shared; a `loader` of a test is
/// decoded per scope and released with it.
class EmojiTabIconScope extends StatelessWidget {
  /// Provides the strip's icons to [child].
  const EmojiTabIconScope({required this.child, this.loader, super.key});

  /// The subtree that shows the icons.
  final Widget child;

  /// Where the art's bytes come from; the asset bundle when null.
  final EmojiTabAssetLoader? loader;

  @override
  Widget build(BuildContext context) => IconArtScope(
    assets: {
      for (final id in EmojiTabIcons.assets.keys)
        id: EmojiTabIcons.assetKeyOf(id)!,
    },
    loader: loader,
    child: child,
  );
}

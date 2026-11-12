import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_pages/src/assets/icon_art.dart';

/// The icons the pages' menus lead their items with: the content preview's
/// menu and the context menu a secondary click opens.
///
/// The art is single-colour menu masks bundled with this package at their
/// 3x size ([sizeOf]). A host restyles one by registering a painter for its id
/// in a [ChromeIconScope] above the menu.
abstract final class CatalogMenuIcons {
  /// Send (`msg_send`).
  static const ChromeIconId send = ChromeIconId('menu.send');

  /// Send without sound (`input_notify_off`).
  static const ChromeIconId sendWithoutSound = ChromeIconId(
    'menu.send-without-sound',
  );

  /// Add to favourites (`msg_fave`).
  static const ChromeIconId favourite = ChromeIconId('menu.favourite');

  /// Delete from favourites (`msg_unfave`).
  static const ChromeIconId unfavourite = ChromeIconId('menu.unfavourite');

  /// View the pack (`msg_media`).
  static const ChromeIconId viewPack = ChromeIconId('menu.view-pack');

  /// Delete or remove (`msg_delete`).
  static const ChromeIconId delete = ChromeIconId('menu.delete');

  /// Save to GIFs (`msg_gif_add`).
  static const ChromeIconId saveGif = ChromeIconId('menu.save-gif');

  /// Copy (`msg_copy`).
  static const ChromeIconId copy = ChromeIconId('menu.copy');

  /// The size [id] is drawn at, never scaled: 24, but 28 for the
  /// notifications-off icon (84 px at 3x).
  static double sizeOf(ChromeIconId id) => id == sendWithoutSound ? 28 : 24;

  /// The bundle key of each icon's art.
  static const Map<ChromeIconId, String> art = {
    send: '$_dir/msg_send.webp',
    sendWithoutSound: '$_dir/input_notify_off.webp',
    favourite: '$_dir/msg_fave.webp',
    unfavourite: '$_dir/msg_unfave.webp',
    viewPack: '$_dir/msg_media.webp',
    delete: '$_dir/msg_delete.webp',
    saveGif: '$_dir/msg_gif_add.webp',
    copy: '$_dir/msg_copy.webp',
  };

  static const String _dir = 'packages/panel_pages/assets/menu_icons';

  /// Starts decoding the art, so a menu that opens later draws its icons
  /// from its first frame.
  static void warm() => IconArt.warm(art.values);
}

/// Registers the menu icons' art for a menu's subtree.
class CatalogMenuIconScope extends StatelessWidget {
  /// Provides [CatalogMenuIcons] to [child].
  const CatalogMenuIconScope({required this.child, super.key});

  /// The menu.
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      IconArtScope(assets: CatalogMenuIcons.art, child: child);
}

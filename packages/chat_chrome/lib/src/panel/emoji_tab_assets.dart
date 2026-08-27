// ignore_for_file: public_member_api_docs

import 'package:emoji_data/emoji_data.dart';

/// Bundled category / type-tab drawable paths for [chat_chrome].
///
/// Package-relative; use with [Image.asset] `package: 'chat_chrome'`.
abstract final class EmojiTabAssets {
  static const String _root = 'assets/emoji_tabs';

  /// Package name for [AssetImage].
  static const String package = 'chat_chrome';

  // —— Category strip ——

  static const String recent = '$_root/msg_emoji_recent.webp';
  static const String smiles = '$_root/msg_emoji_smiles.webp';
  static const String cat = '$_root/msg_emoji_cat.webp';
  static const String food = '$_root/msg_emoji_food.webp';
  static const String activities = '$_root/msg_emoji_activities.webp';
  static const String travel = '$_root/msg_emoji_travel.webp';
  static const String objects = '$_root/msg_emoji_objects.webp';
  static const String other = '$_root/msg_emoji_other.webp';
  static const String flags = '$_root/msg_emoji_flags.webp';

  // —— Bottom type / action icons ——

  static const String search = '$_root/smiles_tab_search.webp';
  static const String clear = '$_root/smiles_tab_clear.webp';
  static const String settings = '$_root/smiles_tab_settings.webp';
  static const String typeSmiles = '$_root/smiles_tab_smiles.webp';
  static const String typeGif = '$_root/smiles_tab_gif.webp';
  static const String typeStickers = '$_root/smiles_tab_stickers.webp';

  /// Asset path for a known unicode category id (fallback: smiles).
  static String categoryAssetForId(String id) => switch (id) {
        'recents' => recent,
        'smileys' => smiles,
        'animals' => cat,
        'food' => food,
        'activities' => activities,
        'travel' => travel,
        'objects' => objects,
        'symbols' => other,
        'flags' => flags,
        _ => smiles,
      };

  /// Strip icon for a known unicode category id.
  static EmojiStripIcon stripIconForId(String id) => EmojiStripIcon.asset(
        categoryAssetForId(id),
        package: package,
      );

  /// Recents strip icon.
  static EmojiStripIcon get recentsStripIcon =>
      const EmojiStripIcon.asset(recent, package: package);
}

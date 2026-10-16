/// The emoji data API `chat_chrome` is still written against: catalogue,
/// recents, skin-tone preferences and the platform filter seam.
///
/// Interim code for the `emoji_data` rewrite: the logic packages replace it
/// and it is deleted together with `chat_chrome`. Nothing new depends on it.
library;

export 'package:chat_chrome/src/legacy_emoji/catalog/emoji_category_titles.dart';
export 'package:chat_chrome/src/legacy_emoji/catalog/emoji_catalog_search.dart';
export 'package:chat_chrome/src/legacy_emoji/catalog/emoji_platform_filter.dart';
export 'package:chat_chrome/src/legacy_emoji/catalog/locale_emoji_catalog.dart';
export 'package:chat_chrome/src/legacy_emoji/default_emoji_data_source.dart';
export 'package:chat_chrome/src/legacy_emoji/emoji_catalog_provider.dart';
export 'package:chat_chrome/src/legacy_emoji/emoji_category_spec.dart';
export 'package:chat_chrome/src/legacy_emoji/emoji_data_listener.dart';
export 'package:chat_chrome/src/legacy_emoji/emoji_data_source.dart';
export 'package:chat_chrome/src/legacy_emoji/emoji_item.dart';
export 'package:chat_chrome/src/legacy_emoji/emoji_pick_source.dart';
export 'package:chat_chrome/src/legacy_emoji/emoji_recents_store.dart';
export 'package:chat_chrome/src/legacy_emoji/emoji_skin_tone.dart';
export 'package:chat_chrome/src/legacy_emoji/emoji_strip_icon.dart';
export 'package:chat_chrome/src/legacy_emoji/glyph_probe_emoji_platform_filter.dart';
export 'package:chat_chrome/src/legacy_emoji/locale_emoji_catalog_provider.dart';
export 'package:chat_chrome/src/legacy_emoji/skin_tone_prefs.dart';

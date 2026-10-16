import 'package:chat_chrome/src/legacy_emoji/catalog/emoji_category_titles.dart';
import 'package:chat_chrome/src/legacy_emoji/catalog/emoji_platform_filter.dart';
import 'package:chat_chrome/src/legacy_emoji/catalog/locale_emoji_catalog.dart';
import 'package:chat_chrome/src/legacy_emoji/emoji_catalog_provider.dart';
import 'package:chat_chrome/src/legacy_emoji/emoji_category_spec.dart';
import 'package:chat_chrome/src/legacy_emoji/emoji_item.dart';
import 'package:chat_chrome/src/legacy_emoji/emoji_skin_tone.dart';
import 'package:chat_chrome/src/legacy_emoji/emoji_strip_icon.dart';
import 'package:flutter/material.dart';

/// Loads bundled locale keyword tables into [EmojiCategorySpec].
///
/// Pass host-localized [categoryTitles] and [stripIconFor] for production.
/// Omitting them uses English title fallbacks and no strip icons.
final class LocaleEmojiCatalogProvider implements EmojiCatalogProvider {
  /// Creates a locale catalog provider.
  LocaleEmojiCatalogProvider({
    this.locale = const Locale('en'),
    this.filterUnsupported = true,
    Map<String, String>? categoryTitles,
    this.stripIconFor,
    EmojiPlatformFilter? platformFilter,
  }) : categoryTitles = categoryTitles ?? EmojiCategoryTitles.forLocale(locale),
       _platformFilter = platformFilter ?? PassthroughEmojiPlatformFilter();

  /// Keyword-table locale (`languageCode` selects the bundled catalog).
  final Locale locale;

  /// When true, runs the platform glyph filter.
  final bool filterUnsupported;

  /// Section titles keyed by category id — host should pass l10n.
  final Map<String, String> categoryTitles;

  /// Optional strip icon per category id (custom packs, branded assets).
  final EmojiStripIcon? Function(String categoryId)? stripIconFor;

  final EmojiPlatformFilter _platformFilter;

  /// English fallback titles for demos/tests.
  static Map<String, String> get defaultCategoryTitles =>
      EmojiCategoryTitles.english;

  @override
  Future<List<EmojiCategorySpec>> loadCategories() async {
    final raw = emojiCatalogForLocale(locale);
    final specs = <EmojiCategorySpec>[];

    for (final cat in raw) {
      var items = cat.entries
          .map(
            (e) => UnicodeEmojiItem(
              glyph: e.glyph,
              keywords: e.keywordList,
              supportsSkinTone:
                  e.supportsSkinTone || EmojiSkinTone.supports(e.glyph),
            ),
          )
          .toList(growable: true);

      if (filterUnsupported) {
        items = await _platformFilter.filter(items);
      }

      if (items.isEmpty) continue;

      specs.add(
        EmojiCategorySpec(
          id: cat.id,
          title: categoryTitles[cat.id] ?? cat.id,
          stripIcon: stripIconFor?.call(cat.id),
          items: List<UnicodeEmojiItem>.unmodifiable(items),
        ),
      );
    }

    return specs;
  }
}

import 'package:emoji_data/src/catalog/emoji_catalog_category.dart';
import 'package:emoji_data/src/catalog/locale/emoji_catalog_de.dart';
import 'package:emoji_data/src/catalog/locale/emoji_catalog_en.dart';
import 'package:emoji_data/src/catalog/locale/emoji_catalog_es.dart';
import 'package:emoji_data/src/catalog/locale/emoji_catalog_fr.dart';
import 'package:emoji_data/src/catalog/locale/emoji_catalog_hi.dart';
import 'package:emoji_data/src/catalog/locale/emoji_catalog_it.dart';
import 'package:emoji_data/src/catalog/locale/emoji_catalog_ja.dart';
import 'package:emoji_data/src/catalog/locale/emoji_catalog_nl.dart';
import 'package:emoji_data/src/catalog/locale/emoji_catalog_pt.dart';
import 'package:emoji_data/src/catalog/locale/emoji_catalog_ru.dart';
import 'package:emoji_data/src/catalog/locale/emoji_catalog_zh.dart';
import 'package:flutter/material.dart';

/// Bundled locale codes with keyword catalogs.
const Set<String> supportedEmojiCatalogLocales = <String>{
  'de',
  'en',
  'es',
  'fr',
  'hi',
  'it',
  'ja',
  'nl',
  'pt',
  'ru',
  'zh',
};

/// Resolves a locale to bundled Unicode catalog categories.
List<EmojiCatalogCategory> emojiCatalogForLocale(Locale locale) {
  return switch (locale.languageCode) {
    'de' => emojiCatalogGerman,
    'es' => emojiCatalogSpanish,
    'fr' => emojiCatalogFrench,
    'hi' => emojiCatalogHindi,
    'it' => emojiCatalogItalian,
    'ja' => emojiCatalogJapanese,
    'nl' => emojiCatalogDutch,
    'pt' => emojiCatalogPortuguese,
    'ru' => emojiCatalogRussian,
    'zh' => emojiCatalogChinese,
    _ => emojiCatalogEnglish,
  };
}

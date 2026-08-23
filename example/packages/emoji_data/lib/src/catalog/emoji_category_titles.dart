import 'package:flutter/material.dart';

/// Optional locale fallbacks for section titles keyed by stable category id.
///
/// Prefer host l10n (arb / app strings) passed into
/// [LocaleEmojiCatalogProvider.categoryTitles]. These maps exist for demos and
/// tests that do not wire app localization.
abstract final class EmojiCategoryTitles {
  /// English fallbacks.
  static const Map<String, String> english = <String, String>{
    'smileys': 'Smileys',
    'animals': 'Animals',
    'food': 'Food',
    'activities': 'Activities',
    'travel': 'Travel',
    'objects': 'Objects',
    'symbols': 'Symbols',
    'flags': 'Flags',
  };

  /// German fallbacks.
  static const Map<String, String> german = <String, String>{
    'smileys': 'Smileys',
    'animals': 'Tiere',
    'food': 'Essen',
    'activities': 'Aktivitäten',
    'travel': 'Reisen',
    'objects': 'Gegenstände',
    'symbols': 'Symbole',
    'flags': 'Flaggen',
  };

  /// Spanish fallbacks.
  static const Map<String, String> spanish = <String, String>{
    'smileys': 'Emoticonos',
    'animals': 'Animales',
    'food': 'Comida',
    'activities': 'Actividades',
    'travel': 'Viajes',
    'objects': 'Objetos',
    'symbols': 'Símbolos',
    'flags': 'Banderas',
  };

  /// French fallbacks.
  static const Map<String, String> french = <String, String>{
    'smileys': 'Smileys',
    'animals': 'Animaux',
    'food': 'Nourriture',
    'activities': 'Activités',
    'travel': 'Voyages',
    'objects': 'Objets',
    'symbols': 'Symboles',
    'flags': 'Drapeaux',
  };

  /// Hindi fallbacks.
  static const Map<String, String> hindi = <String, String>{
    'smileys': 'मुस्कान',
    'animals': 'जानवर',
    'food': 'भोजन',
    'activities': 'गतिविधियाँ',
    'travel': 'यात्रा',
    'objects': 'वस्तुएँ',
    'symbols': 'प्रतीक',
    'flags': 'झंडे',
  };

  /// Italian fallbacks.
  static const Map<String, String> italian = <String, String>{
    'smileys': 'Faccine',
    'animals': 'Animali',
    'food': 'Cibo',
    'activities': 'Attività',
    'travel': 'Viaggi',
    'objects': 'Oggetti',
    'symbols': 'Simboli',
    'flags': 'Bandiere',
  };

  /// Japanese fallbacks.
  static const Map<String, String> japanese = <String, String>{
    'smileys': '顔文字',
    'animals': '動物',
    'food': '食べ物',
    'activities': 'アクティビティ',
    'travel': '旅行',
    'objects': '物',
    'symbols': '記号',
    'flags': '旗',
  };

  /// Dutch fallbacks.
  static const Map<String, String> dutch = <String, String>{
    'smileys': 'Smileys',
    'animals': 'Dieren',
    'food': 'Eten',
    'activities': 'Activiteiten',
    'travel': 'Reizen',
    'objects': 'Voorwerpen',
    'symbols': 'Symbolen',
    'flags': 'Vlaggen',
  };

  /// Portuguese fallbacks.
  static const Map<String, String> portuguese = <String, String>{
    'smileys': 'Smileys',
    'animals': 'Animais',
    'food': 'Comida',
    'activities': 'Atividades',
    'travel': 'Viagens',
    'objects': 'Objetos',
    'symbols': 'Símbolos',
    'flags': 'Bandeiras',
  };

  /// Russian fallbacks.
  static const Map<String, String> russian = <String, String>{
    'smileys': 'Смайлы',
    'animals': 'Животные',
    'food': 'Еда',
    'activities': 'Спорт',
    'travel': 'Путешествия',
    'objects': 'Предметы',
    'symbols': 'Символы',
    'flags': 'Флаги',
  };

  /// Chinese fallbacks.
  static const Map<String, String> chinese = <String, String>{
    'smileys': '表情',
    'animals': '动物',
    'food': '食物',
    'activities': '活动',
    'travel': '旅行',
    'objects': '物品',
    'symbols': '符号',
    'flags': '旗帜',
  };

  /// Resolves optional fallback titles for [locale.languageCode].
  static Map<String, String> forLocale(Locale locale) =>
      switch (locale.languageCode) {
        'de' => german,
        'es' => spanish,
        'fr' => french,
        'hi' => hindi,
        'it' => italian,
        'ja' => japanese,
        'nl' => dutch,
        'pt' => portuguese,
        'ru' => russian,
        'zh' => chinese,
        _ => english,
      };
}

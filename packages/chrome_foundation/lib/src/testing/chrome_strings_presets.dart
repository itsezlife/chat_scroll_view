import 'package:chrome_foundation/src/strings/chrome_strings.dart';
import 'package:chrome_foundation/src/strings/composer_strings.dart';
import 'package:chrome_foundation/src/strings/formatting_strings.dart';
import 'package:chrome_foundation/src/strings/panel_strings.dart';
import 'package:chrome_foundation/src/strings/semantics_strings.dart';

/// English and Russian [ChromeStrings] for tests and demos.
///
/// These are not production defaults: no chrome package imports them, and a
/// host supplies its own strings.
abstract final class ChromeStringsPresets {
  /// English copy.
  static final ChromeStrings english = ChromeStrings(
    panel: PanelStrings(
      tabLabel: (id) => switch (id) {
        'emoji' => 'Emoji',
        'stickers' => 'Stickers',
        'gif' => 'GIF',
        _ => id,
      },
      categoryTitle: (id) => switch (id) {
        'people' => 'Smileys & People',
        'nature' => 'Animals & Nature',
        'food' => 'Food & Drink',
        'travel' => 'Travel & Places',
        'activity' => 'Activity',
        'objects' => 'Objects',
        'symbols' => 'Symbols',
        _ => id,
      },
      recentlyUsedTitle: 'Recently used',
      searchResultsTitle: 'Search result',
      searchHint: 'Search',
      searchEmpty: 'No emoji found',
      clearRecentsTitle: 'Clear recent emoji',
      clearRecentsMessage: 'Do you want to clear all your recent emoji?',
      clearAction: 'Clear',
      cancelAction: 'Cancel',
      copyAction: 'Copy',
      removeRecentAction: 'Remove from recent',
      clearRecentAction: 'Clear recent',
      colorAllTitle: 'Choose default skin tone',
    ),
    composer: ComposerStrings(
      messageHint: 'Message',
      sendAction: 'Send',
      confirmEditAction: 'Save changes',
      recordVoiceAction: 'Record voice message',
      attachAction: 'Attach',
      showPanelAction: 'Show emoji panel',
      showKeyboardAction: 'Show keyboard',
      dismissHeaderAction: 'Cancel',
      pastePlainAction: 'Paste as plain text',
      replyTo: (name) => 'Reply to $name',
      editingMessage: 'Editing message',
    ),
    formatting: FormattingStrings(
      quoteAction: 'Quote',
      spoilerAction: 'Spoiler',
      boldAction: 'Bold',
      italicAction: 'Italic',
      monoAction: 'Mono',
      strikethroughAction: 'Strikethrough',
      underlineAction: 'Underline',
      createLinkAction: 'Create Link',
      editLinkAction: 'Edit Link',
      removeLinkAction: 'Remove Link',
      codeBlockAction: 'Code block',
      bulletListAction: 'Bullet list',
      numberedListAction: 'Numbered list',
      clearFormattingAction: 'Regular',
      moreAction: 'More',
      backAction: 'Back',
      bulletListItem: 'Bullet list item',
      numberedListItem: (number) => 'Numbered list item $number',
    ),
    semantics: SemanticsStrings(
      panelOpened: 'Panel opened',
      panelClosed: 'Panel closed',
      pageSelected: (label) => '$label selected',
      searchFieldLabel: 'Search',
      searchResultCount: (count) => switch (count) {
        0 => 'No results',
        1 => '1 result',
        _ => '$count results',
      },
      backspaceAction: 'Delete',
      variantsAction: 'Show variants',
      categoryStripLabel: 'Categories',
    ),
  );

  /// Russian copy.
  static final ChromeStrings russian = ChromeStrings(
    panel: PanelStrings(
      tabLabel: (id) => switch (id) {
        'emoji' => 'Эмодзи',
        'stickers' => 'Стикеры',
        'gif' => 'GIF',
        _ => id,
      },
      categoryTitle: (id) => switch (id) {
        'people' => 'Смайлики и люди',
        'nature' => 'Животные и природа',
        'food' => 'Еда и напитки',
        'travel' => 'Путешествия и места',
        'activity' => 'Активности',
        'objects' => 'Предметы',
        'symbols' => 'Символы',
        _ => id,
      },
      recentlyUsedTitle: 'Недавние',
      searchResultsTitle: 'Результат поиска',
      searchHint: 'Поиск',
      searchEmpty: 'Эмодзи не найдены',
      clearRecentsTitle: 'Очистить недавние эмодзи',
      clearRecentsMessage: 'Вы хотите очистить все недавние эмодзи?',
      clearAction: 'Очистить',
      cancelAction: 'Отмена',
      copyAction: 'Копировать',
      removeRecentAction: 'Удалить из недавних',
      clearRecentAction: 'Очистить недавние',
      colorAllTitle: 'Выберите тон кожи по умолчанию',
    ),
    composer: ComposerStrings(
      messageHint: 'Сообщение',
      sendAction: 'Отправить',
      confirmEditAction: 'Сохранить изменения',
      recordVoiceAction: 'Записать голосовое сообщение',
      attachAction: 'Прикрепить',
      showPanelAction: 'Показать панель эмодзи',
      showKeyboardAction: 'Показать клавиатуру',
      dismissHeaderAction: 'Отмена',
      pastePlainAction: 'Вставить без форматирования',
      replyTo: (name) => 'Ответ для $name',
      editingMessage: 'Редактирование сообщения',
    ),
    formatting: FormattingStrings(
      quoteAction: 'Цитата',
      spoilerAction: 'Спойлер',
      boldAction: 'Жирный',
      italicAction: 'Курсив',
      monoAction: 'Моноширинный',
      strikethroughAction: 'Зачёркнутый',
      underlineAction: 'Подчёркнутый',
      createLinkAction: 'Создать ссылку',
      editLinkAction: 'Изменить ссылку',
      removeLinkAction: 'Удалить ссылку',
      codeBlockAction: 'Блок кода',
      bulletListAction: 'Маркированный список',
      numberedListAction: 'Нумерованный список',
      clearFormattingAction: 'Обычный',
      moreAction: 'Ещё',
      backAction: 'Назад',
      bulletListItem: 'Пункт маркированного списка',
      numberedListItem: (number) => 'Пункт нумерованного списка $number',
    ),
    semantics: SemanticsStrings(
      panelOpened: 'Панель открыта',
      panelClosed: 'Панель закрыта',
      pageSelected: (label) => 'Выбрано: $label',
      searchFieldLabel: 'Поиск',
      searchResultCount: (count) => switch (_russianPlural(count)) {
        _RussianPlural.one => '$count результат',
        _RussianPlural.few => '$count результата',
        _RussianPlural.many => '$count результатов',
      },
      backspaceAction: 'Удалить',
      variantsAction: 'Показать варианты',
      categoryStripLabel: 'Категории',
    ),
  );
}

enum _RussianPlural { one, few, many }

// CLDR cardinal rules for integers: one for 1, 21, 31 (not 11); few for
// 2-4, 22-24 (not 12-14); many otherwise, zero included.
_RussianPlural _russianPlural(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return _RussianPlural.one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return _RussianPlural.few;
  }
  return _RussianPlural.many;
}

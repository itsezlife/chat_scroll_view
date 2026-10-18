import 'package:chrome_foundation/chrome_foundation.dart';

/// The demo's language for every string the chrome packages draw: Russian.
///
/// The packages ship no translation, so the host supplies the whole set. A
/// real app fills this from its localisation; the demo keeps one literal.
final ChromeStrings demoChromeStrings = ChromeStrings(
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
    clearFormattingAction: 'Очистить форматирование',
    moreAction: 'Ещё',
    backAction: 'Назад',
    bulletListItem: 'Пункт маркированного списка',
    numberedListItem: (number) => 'Пункт нумерованного списка $number',
  ),
  editMenu: EditMenuStrings(
    undoAction: 'Отменить',
    redoAction: 'Повторить',
    cutAction: 'Вырезать',
    copyAction: 'Копировать',
    pasteAction: 'Вставить',
    deleteAction: 'Удалить',
    selectAllAction: 'Выделить всё',
    formattingMenu: 'Форматирование',
    boldAction: 'Жирный',
    italicAction: 'Курсив',
    underlineAction: 'Подчёркнутый',
    strikethroughAction: 'Зачёркнутый',
    quoteAction: 'Цитата',
    monospaceAction: 'Моноширинный',
    spoilerAction: 'Спойлер',
    createLinkAction: 'Создать ссылку',
    editLinkAction: 'Изменить ссылку',
    clearFormattingAction: 'Очистить форматирование',
    pastePlainAction: 'Вставить без форматирования',
    codeBlockAction: 'Блок кода',
    removeLinkAction: 'Удалить ссылку',
    bulletListAction: 'Маркированный список',
    numberedListAction: 'Нумерованный список',
  ),
  semantics: SemanticsStrings(
    panelOpened: 'Панель открыта',
    panelClosed: 'Панель закрыта',
    pageSelected: (label) => 'Выбрано: $label',
    searchFieldLabel: 'Поиск',
    searchResultCount: (count) => switch (_pluralOf(count)) {
      _Plural.one => '$count результат',
      _Plural.few => '$count результата',
      _Plural.many => '$count результатов',
    },
    backspaceAction: 'Удалить',
    variantsAction: 'Показать варианты',
    categoryStripLabel: 'Категории',
  ),
);

enum _Plural { one, few, many }

// CLDR cardinal rules of Russian for integers: one for 1, 21, 31 (not 11),
// few for 2-4, 22-24 (not 12-14), many otherwise, zero included.
_Plural _pluralOf(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return _Plural.one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return _Plural.few;
  }
  return _Plural.many;
}

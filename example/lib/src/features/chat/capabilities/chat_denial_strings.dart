import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_composer/chat_composer.dart' show ComposerSlowModeState;
import 'package:chrome_foundation/chrome_foundation.dart' show ComposerStrings;
import 'package:meta/meta.dart';

/// The demo's texts for a denied action: what a package draws in place
/// (`CapabilityFeedback.denialText`) and what the bulletin of an attempt
/// says, one text per `(CapabilityAction, DenialReason)`.
///
/// The packages never carry a denial text: the reason says why, and the
/// host words it. The reason's form picks the sentence and the action its
/// subject; the `other` tags the packages ask with (the write-access bars,
/// a pending slow-mode send) have sentences of their own.
///
/// [english] holds the English texts; [russian] is the demo's language, as
/// `demoChromeStrings` is.
@immutable
final class ChatDenialStrings {
  /// A set of every text.
  const ChatDenialStrings({
    required this.subject,
    required this.everyone,
    required this.restricted,
    required this.restrictedUntil,
    required this.unlockable,
    required this.unavailable,
    required this.readOnly,
    required this.join,
    required this.requestToJoin,
    required this.slowModeWait,
    required this.slowModePending,
    required this.unlockAction,
  });

  /// The English texts.
  static const ChatDenialStrings english = ChatDenialStrings(
    subject: _englishSubject,
    everyone: _englishEveryone,
    restricted: _englishRestricted,
    restrictedUntil: _englishRestrictedUntil,
    unlockable: _englishUnlockable,
    unavailable: _englishUnavailable,
    readOnly: 'Only admins can post in this channel.',
    join: 'Join the chat to write here.',
    requestToJoin: 'Ask to join the chat to write here.',
    slowModeWait: _englishSlowModeWait,
    slowModePending: 'Slow mode: wait until your last message is sent.',
    unlockAction: _englishUnlockAction,
  );

  /// The demo's Russian.
  static const ChatDenialStrings russian = ChatDenialStrings(
    subject: _russianSubject,
    everyone: _russianEveryone,
    restricted: _russianRestricted,
    restrictedUntil: _russianRestrictedUntil,
    unlockable: _russianUnlockable,
    unavailable: _russianUnavailable,
    readOnly: 'Писать в этом канале могут только администраторы.',
    join: 'Вступите в чат, чтобы писать.',
    requestToJoin: 'Подайте заявку на вступление, чтобы писать.',
    slowModeWait: _russianSlowModeWait,
    slowModePending:
        'Медленный режим: дождитесь отправки предыдущего сообщения.',
    unlockAction: _russianUnlockAction,
  );

  /// The set the demo shows: [russian], the language of its chrome strings.
  static const ChatDenialStrings demo = russian;

  /// What [CapabilityAction] names, as the object of a sentence: "sending
  /// stickers", "copying".
  final String Function(CapabilityAction action) subject;

  /// [DenialReason.everyone]: the chat denies it to every member.
  final String Function(String subject) everyone;

  /// [DenialReason.restricted] for good.
  final String Function(String subject) restricted;

  /// [DenialReason.restricted] until a date, given as the text of [until].
  final String Function(String subject, String until) restrictedUntil;

  /// [DenialReason.unlockable]: the user can lift it with what `kind` names.
  final String Function(String subject, String kind) unlockable;

  /// Any other reason: the action is not available.
  final String Function(String subject) unavailable;

  /// The read-only bar (`DenialReason.other('readOnly')`).
  final String readOnly;

  /// The join bar (`DenialReason.other('join')`).
  final String join;

  /// The request-to-join bar (`DenialReason.other('requestToJoin')`).
  final String requestToJoin;

  /// An early send during slow mode's countdown, with the wait left as
  /// `m:ss`.
  final String Function(String countdown) slowModeWait;

  /// An early send while the last message is still sending.
  final String slowModePending;

  /// The label of the action that lifts an `unlockable` restriction.
  final String Function(String kind) unlockAction;

  /// The text for [action] denied for [reason], read at [now] (a slow mode
  /// wait counts down from it).
  String text(
    CapabilityAction action,
    DenialReason reason, {
    required DateTime now,
  }) => switch (reason) {
    DenialReason$Restricted(:final until?)
        when action == CapabilityAction.sendNow =>
      slowModeWait(ComposerStrings.minutesSeconds(until.difference(now))),
    DenialReason$Other(tag: ComposerSlowModeState.pendingTag) =>
      slowModePending,
    DenialReason$Other(tag: 'readOnly') => readOnly,
    DenialReason$Other(tag: 'join') => join,
    DenialReason$Other(tag: 'requestToJoin') => requestToJoin,
    DenialReason$Other() => unavailable(subject(action)),
    DenialReason$Everyone() => everyone(subject(action)),
    DenialReason$Restricted(:final until?) => restrictedUntil(
      subject(action),
      _date(until),
    ),
    DenialReason$Restricted() => restricted(subject(action)),
    DenialReason$Unlockable(:final kind) => unlockable(subject(action), kind),
  };

  // Day, month and time, as a chat's ban dates read: 28.11 14:05.
  static String _date(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(at.day)}.${two(at.month)} ${two(at.hour)}:${two(at.minute)}';
  }
}

// --- English ---------------------------------------------------------------

String _englishSubject(CapabilityAction action) => switch (action) {
  CapabilityAction.sendText => 'sending messages',
  CapabilityAction.sendPhoto => 'sending photos',
  CapabilityAction.sendVideo => 'sending videos',
  CapabilityAction.sendAnimation => 'sending GIFs',
  CapabilityAction.sendFile => 'sending files',
  CapabilityAction.sendAudio => 'sending music',
  CapabilityAction.sendVoice => 'sending voice messages',
  CapabilityAction.sendRoundVideo => 'sending video messages',
  CapabilityAction.sendSticker => 'sending stickers',
  CapabilityAction.sendLinkPreview => 'sending link previews',
  CapabilityAction.sendPoll => 'sending polls',
  CapabilityAction.sendInline => 'sending inline results',
  CapabilityAction.sendNow => 'sending now',
  CapabilityAction.copy => 'copying',
  CapabilityAction.forward => 'forwarding',
  CapabilityAction.save => 'saving',
};

String _capitalised(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

String _englishEveryone(String subject) =>
    'The admins of this chat have turned off $subject.';

String _englishRestricted(String subject) =>
    'The admins of this chat have restricted you from $subject.';

String _englishRestrictedUntil(String subject, String until) =>
    'The admins of this chat have restricted you from $subject until $until.';

String _englishUnlockable(String subject, String kind) => switch (kind) {
  'boost' => '${_capitalised(subject)} opens once you boost this chat.',
  _ => '${_capitalised(subject)} is locked; you can unlock it.',
};

String _englishUnavailable(String subject) =>
    '${_capitalised(subject)} is not available here.';

String _englishSlowModeWait(String countdown) =>
    'Slow mode is on. You can send again in $countdown.';

String _englishUnlockAction(String kind) => switch (kind) {
  'boost' => 'Boost to lift',
  _ => 'Unlock',
};

// --- Russian ---------------------------------------------------------------

String _russianSubject(CapabilityAction action) => switch (action) {
  CapabilityAction.sendText => 'отправку сообщений',
  CapabilityAction.sendPhoto => 'отправку фото',
  CapabilityAction.sendVideo => 'отправку видео',
  CapabilityAction.sendAnimation => 'отправку GIF',
  CapabilityAction.sendFile => 'отправку файлов',
  CapabilityAction.sendAudio => 'отправку музыки',
  CapabilityAction.sendVoice => 'отправку голосовых сообщений',
  CapabilityAction.sendRoundVideo => 'отправку видеосообщений',
  CapabilityAction.sendSticker => 'отправку стикеров',
  CapabilityAction.sendLinkPreview => 'отправку превью ссылок',
  CapabilityAction.sendPoll => 'отправку опросов',
  CapabilityAction.sendInline => 'отправку инлайн-результатов',
  CapabilityAction.sendNow => 'отправку сейчас',
  CapabilityAction.copy => 'копирование',
  CapabilityAction.forward => 'пересылку',
  CapabilityAction.save => 'сохранение',
};

String _russianEveryone(String subject) =>
    'Администраторы запретили $subject в этом чате.';

String _russianRestricted(String subject) =>
    'Администраторы ограничили вам $subject.';

String _russianRestrictedUntil(String subject, String until) =>
    'Администраторы ограничили вам $subject до $until.';

String _russianUnlockable(String subject, String kind) => switch (kind) {
  'boost' => 'Бустните чат, чтобы снять запрет на $subject.',
  _ => 'Снимите ограничение на $subject.',
};

String _russianUnavailable(String subject) =>
    'В этом чате не разрешили $subject.';

String _russianSlowModeWait(String countdown) =>
    'Включён медленный режим. Отправить снова можно через $countdown.';

String _russianUnlockAction(String kind) => switch (kind) {
  'boost' => 'Бустнуть, чтобы снять',
  _ => 'Снять ограничение',
};

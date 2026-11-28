import 'package:chat_scroll_view_example/src/common/utils/russian_plural.dart';
import 'package:content_model/content_model.dart' show MediaItemKind;
import 'package:flutter/foundation.dart';
import 'package:mpx_library/mpx_library.dart' show SaveFailure;

/// The words of a save's feedback: the progress dialog, the "saved"
/// bulletins per destination, kind and count, and a failure per reason.
///
/// [english] holds the English texts; [russian] is the demo's language, as
/// `ChatBulletinStrings` is.
@immutable
final class ChatSaveStrings {
  /// A set of every text.
  const ChatSaveStrings({
    required this.progressMessage,
    required this.cancel,
    required this.downloadsLink,
    required String Function(MediaItemKind? kind, int count) savedToGallery,
    required String Function(MediaItemKind? kind, int count) savedToDownloads,
    required this.failed,
  }) : _savedToGallery = savedToGallery,
       _savedToDownloads = savedToDownloads;

  /// The English texts.
  static const ChatSaveStrings english = ChatSaveStrings(
    progressMessage: 'Loading…',
    cancel: 'Cancel',
    downloadsLink: 'Downloads',
    savedToGallery: _englishGallery,
    savedToDownloads: _englishDownloads,
    failed: _englishFailed,
  );

  /// The demo's Russian.
  static const ChatSaveStrings russian = ChatSaveStrings(
    progressMessage: 'Загрузка…',
    cancel: 'Отмена',
    downloadsLink: 'Загрузки',
    savedToGallery: _russianGallery,
    savedToDownloads: _russianDownloads,
    failed: _russianFailed,
  );

  /// The set the demo shows: [russian], the language of its chrome strings.
  static const ChatSaveStrings demo = russian;

  /// The progress dialog's text.
  final String progressMessage;

  /// The progress dialog's cancel button.
  final String cancel;

  /// The word of [savedToDownloads] that opens the Downloads; every
  /// Downloads text holds it.
  final String downloadsLink;

  /// Why a save failed.
  final String Function(SaveFailure reason) failed;

  final String Function(MediaItemKind? kind, int count) _savedToGallery;
  final String Function(MediaItemKind? kind, int count) _savedToDownloads;

  /// [count] items of [kind] saved to the gallery; a null [kind] for
  /// items of several kinds.
  String savedToGallery(MediaItemKind? kind, int count) =>
      _savedToGallery(kind, count);

  /// [count] items of [kind] saved to the Downloads; a null [kind] for
  /// items of several kinds. Holds [downloadsLink].
  String savedToDownloads(MediaItemKind? kind, int count) =>
      _savedToDownloads(kind, count);

  // --- English ---

  static String _englishGallery(MediaItemKind? kind, int count) =>
      switch ((kind, count)) {
        (MediaItemKind.photo, 1) => 'Photo saved to gallery',
        (MediaItemKind.photo, _) => '$count photos saved to gallery',
        (MediaItemKind.video, 1) => 'Video saved to gallery',
        (MediaItemKind.video, _) => '$count videos saved to gallery',
        (MediaItemKind.animation, 1) => 'GIF saved to gallery',
        (MediaItemKind.animation, _) => '$count GIFs saved to gallery',
        (_, 1) => 'An item saved to gallery',
        _ => '$count items saved to gallery',
      };

  // Several items to the Downloads are files, whatever their kinds.
  static String _englishDownloads(MediaItemKind? kind, int count) =>
      switch ((kind, count)) {
        (MediaItemKind.photo, 1) => 'Photo saved to Downloads.',
        (MediaItemKind.video, 1) => 'Video saved to Downloads.',
        (MediaItemKind.animation, 1) => 'GIF saved to Downloads.',
        (_, 1) => 'File saved to Downloads.',
        _ => '$count files saved to Downloads.',
      };

  static String _englishFailed(SaveFailure reason) => switch (reason) {
    SaveFailure.accessDenied => 'No access to save. Allow it in Settings.',
    SaveFailure.noSpace => 'Not enough space to save.',
    SaveFailure.unsupportedFormat => "This file can't be saved there.",
    SaveFailure.unavailable => "Couldn't save. Try again later.",
  };

  // --- Russian ---

  // The count leads after a colon, so the verb needs no agreement with it.
  static String _russianGallery(MediaItemKind? kind, int count) =>
      switch ((kind, count)) {
        (MediaItemKind.photo, 1) => 'Фото сохранено в галерею',
        (MediaItemKind.video, 1) => 'Видео сохранено в галерею',
        (MediaItemKind.animation, 1) => 'GIF сохранён в галерею',
        (MediaItemKind.photo, _) => 'Сохранено в галерею: $count фото',
        (MediaItemKind.video, _) => 'Сохранено в галерею: $count видео',
        (MediaItemKind.animation, _) => 'Сохранено в галерею: $count GIF',
        _ =>
          'Сохранено в галерею: $count '
              '${RussianPlural.wordOf(count, 'объект', 'объекта', 'объектов')}',
      };

  static String _russianDownloads(MediaItemKind? kind, int count) =>
      switch ((kind, count)) {
        (MediaItemKind.photo, 1) => 'Фото сохранено в Загрузки.',
        (MediaItemKind.video, 1) => 'Видео сохранено в Загрузки.',
        (MediaItemKind.animation, 1) => 'GIF сохранён в Загрузки.',
        (_, 1) => 'Файл сохранён в Загрузки.',
        _ =>
          'Сохранено в Загрузки: $count '
              '${RussianPlural.wordOf(count, 'файл', 'файла', 'файлов')}.',
      };

  static String _russianFailed(SaveFailure reason) => switch (reason) {
    SaveFailure.accessDenied =>
      'Нет доступа для сохранения. Разрешите его в настройках.',
    SaveFailure.noSpace => 'Недостаточно места для сохранения.',
    SaveFailure.unsupportedFormat => 'Этот файл нельзя сохранить сюда.',
    SaveFailure.unavailable => 'Не удалось сохранить. Попробуйте позже.',
  };
}

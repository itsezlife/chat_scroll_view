import 'dart:async';

import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/attach_sheet.dart';
import 'package:bulletins/bulletins.dart';
import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/app/environment_specific/cache_directory.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_bulletins.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mpx_capture/mpx_capture.dart';
import 'package:mpx_library/mpx_library.dart';

/// Turns a send plan into the demo chat's messages: one message per planned
/// send, a send group as one message listing its items, the caption on the
/// send the plan put it on, and the web's leading caption as a text message.
///
/// The demo's messages carry text only, so a media item is a line naming it
/// (and its prepared size when it was prepared).
abstract final class ChatAttachMessages {
  /// The texts of [plan], in order.
  static List<String> of(
    SendPlan$Ready plan, {
    Map<AttachItemId, PreparedMedia> prepared = const {},
  }) {
    String line(AttachItem item) {
      final kind = switch (item.kind) {
        AttachKind.photo => '🖼',
        AttachKind.video => '🎬',
        AttachKind.animation => 'GIF',
        AttachKind.audio => '🎵',
        AttachKind.file => '📎',
      };
      final name = item.facts.name ?? item.id;
      final out = prepared[item.id];
      final size = switch (out?.dimensions) {
        final d? => ' ${d.width}×${d.height}',
        null => '',
      };
      return '$kind $name$size';
    }

    return [
      for (final send in plan.sends)
        switch (send) {
          PlannedSend$Single(:final item, :final caption) => [
            line(item),
            if (caption != null) caption.plain,
          ].join('\n'),
          PlannedSend$Group(
            :final items,
            :final captionIndex,
            :final caption,
          ) =>
            [
              for (var i = 0; i < items.length; i++) ...[
                line(items[i]),
                if (i == captionIndex && caption != null) caption.plain,
              ],
            ].join('\n'),
          PlannedSend$Text(:final caption) => caption.plain,
        },
    ];
  }
}

/// The demo's **attach sheet host**: opens the sheet (Android, iOS) or the
/// confirm box (desktop, web) from the attach button, a drop or the file
/// dialog, moves the composer's text into the caption and back, parks the
/// keyboard, prepares the media at send and posts the messages.
final class ChatAttach extends AttachSheetHost {
  /// The attach host of one chat screen.
  ChatAttach({
    required this.services,
    required this.composer,
    required this.bulletins,
    required this.send,
  });

  /// The app's services (the device library, the key-value store).
  final AppServices services;

  /// The chat's composer, whose text moves into the caption.
  final ComposerController composer;

  /// Where refusals are told.
  final BulletinController bulletins;

  /// Posts one message.
  final Future<void> Function(String text) send;

  /// The sheet or box family of this platform.
  final AttachSheetPolicy policy = AttachSheetPolicy.current();

  /// The model's family of this platform.
  final AttachPolicy attachPolicy = AttachPolicy.forPlatform(
    switch (defaultTargetPlatform) {
      TargetPlatform.android => AttachHostPlatform.android,
      TargetPlatform.iOS => AttachHostPlatform.iOS,
      TargetPlatform.macOS => AttachHostPlatform.macOS,
      TargetPlatform.windows => AttachHostPlatform.windows,
      TargetPlatform.linux => AttachHostPlatform.linux,
      TargetPlatform.fuchsia => AttachHostPlatform.fuchsia,
    },
    isWeb: kIsWeb,
  );

  /// The demo chat's rights: captions of 1024, files up to 2000 MB, no
  /// timers (a group chat), scheduling allowed.
  static const AttachLimits limits = AttachLimits(
    fileSizeLimit: 2000 * 1024 * 1024,
    timerAllowed: false,
  );

  late final Future<FileIntake> _$intake = PlatformIntake.fileIntake();
  late final Future<String> _$work = _workDirectory();
  final IntakeItems _$items = IntakeItems();
  ConfirmBoxController? _$box;
  bool _keyboardWasUp = false;
  BuildContext? _$context;

  /// Whether a confirm box is up (one at a time: later routes add to it).
  final ValueNotifier<bool> boxOpen = ValueNotifier(false);

  /// The platform's drop source, on a family that picks through the box.
  late final DropSource? dropSource = policy.confirmBox == null
      ? null
      : PlatformIntake.dropSource();

  static Future<String> _workDirectory() async =>
      await $appCacheDirectory('attach') ?? '';

  SendOptionStore get _store =>
      SendOptionStore(services.keyValueStore, policy: attachPolicy);

  /// The attach button.
  Future<void> open(BuildContext context) async {
    _$context = context;
    if (policy.confirmBox != null) {
      final files = await (await _$intake).pickFiles();
      if (files.isEmpty || !context.mounted) return;
      return openBox(context, files);
    }
    await _openSheet(context);
  }

  Future<void> _openSheet(BuildContext context) async {
    final intake = await _$intake;
    final directory = await _$work;
    if (!context.mounted) return;
    final caption = composer.richText;
    composer.clear();
    final library = services.mediaLibrary;
    final outcome = await AttachSheet.show(
      context,
      policy: policy,
      selection: AttachSelection(policy: attachPolicy, limits: limits),
      host: this,
      opening: AttachSheetOpening(keyboardWasUp: composer.hasFocus),
      initialCaption: caption,
      optionStore: _store,
      pages: AttachPageRegistry([
        if (library != null)
          GalleryPage.create(
            library: library,
            label: 'Галерея',
            icon: const Icon(Icons.photo_library_outlined),
            camera: GalleryCamera(
              sessions: const PlatformCameraSessions(),
              outputDirectory: directory,
              systemCamera: intake,
            ),
          ),
        FilesPage.create(
          intake: intake,
          library: library,
          items: _$items,
          label: 'Файл',
          icon: const Icon(Icons.insert_drive_file_outlined),
        ),
      ]),
    );
    await _finish(outcome, library: library);
  }

  /// Opens the confirm box with [files], or adds them to the open one.
  Future<void> openBox(
    BuildContext context,
    List<IntakeFile> files, {
    bool? asFiles,
  }) async {
    if (_$box case final box? when box.isOpen) {
      box.addFiles(files);
      return;
    }
    final intake = await _$intake;
    final directory = await _$work;
    if (!context.mounted) return;
    final caption = composer.richText;
    composer.clear();
    final box = _$box = ConfirmBoxController(
      policy: policy,
      selection: AttachSelection(policy: attachPolicy, limits: limits),
      intake: intake,
      host: this,
      initialCaption: caption,
      store: _store,
      asFiles: asFiles,
      items: _$items,
      preparation: _preparation(directory, null),
    )..addFiles(files);
    boxOpen.value = true;
    final outcome = await ConfirmBox.show(context, controller: box);
    boxOpen.value = false;
    _$box = null;
    await _finish(outcome);
    box.dispose();
  }

  AttachPreparation? _preparation(String directory, MediaLibrary? library) {
    if (directory.isEmpty) return null;
    return AttachPreparation.withPreparer(
      MediaPreparer(
        codec: const PlatformPreparationCodec(),
        transcoder: const PlatformTranscoder(),
        outputDirectory: directory,
      ),
      PreparationPolicy.forPlatform(defaultTargetPlatform),
      library: library,
      items: _$items,
      concurrency: 2,
    );
  }

  Future<void> _finish(AttachOutcome outcome, {MediaLibrary? library}) async {
    switch (outcome) {
      case AttachOutcome$Cancelled(:final caption):
        // The caption goes back to the composer.
        composer.restore(caption);
      case AttachOutcome$Send(:final request, :final prepared):
        final plan = planSend(request, attachPolicy, limits);
        if (plan case SendPlan$Rejected(:final rejection)) {
          bulletins.show(
            ChatBulletins.error('Не отправлено: ${rejection.name}'),
          );
          return;
        }
        var outputs = prepared;
        if (outputs.isEmpty) {
          // The sheet hands the request over unprepared: prepare here,
          // two at a time.
          final preparation = _preparation(await _$work, library);
          if (preparation != null) {
            outputs = await preparation.prepareAll(request);
          }
        }
        for (final text in ChatAttachMessages.of(
          plan as SendPlan$Ready,
          prepared: outputs,
        )) {
          await send(text);
        }
      case AttachOutcome$Custom():
        return;
    }
  }

  // --- AttachSheetHost ---

  @override
  void opened(AttachSheetOpening opening) {
    _keyboardWasUp = opening.keyboardWasUp;
    composer.focusNode.unfocus();
  }

  @override
  void restoreKeyboard() {
    if (_keyboardWasUp) composer.focusNode.requestFocus();
  }

  @override
  void interaction(AttachInteraction interaction) {
    final text = switch (interaction) {
      AttachInteraction$CaptionTooLong(:final over) =>
        'Подпись длиннее на $over',
      AttachInteraction$Refused(reason: AttachRefusal.capReached) =>
        'Можно выбрать не больше 100',
      AttachInteraction$Refused(reason: AttachRefusal.kindNotAllowed) =>
        'Такие файлы здесь отправлять нельзя',
      AttachInteraction$Refused(reason: AttachRefusal.fileTooLarge) =>
        'Файл больше 2000 МБ',
      AttachInteraction$Refused(reason: AttachRefusal.emptyFile) =>
        'Пустой файл',
    };
    bulletins.show(ChatBulletins.notice(text));
  }

  @override
  Future<SendSchedule?> pickSchedule(BuildContext context) async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (day == null || !context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null) return null;
    return SendSchedule.at(
      DateTime(day.year, day.month, day.day, time.hour, time.minute),
    );
  }

  @override
  void openExternalPicker() {
    final context = _$context;
    if (context == null) return;
    unawaited(
      _$intake.then((intake) async {
        final files = await intake.pickFiles(
          filter: IntakeFilter.imagesAndVideos,
        );
        if (files.isEmpty || !context.mounted) return;
        await openBox(context, files);
      }),
    );
  }

  /// Releases what the host made.
  void dispose() => boxOpen.dispose();
}

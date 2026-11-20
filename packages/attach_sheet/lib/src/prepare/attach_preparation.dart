import 'dart:async';
import 'dart:math' as math;

import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/src/files/intake_items.dart';
import 'package:flutter/foundation.dart';
import 'package:mpx_capture/mpx_capture.dart';
import 'package:mpx_library/mpx_library.dart';

/// Prepares one source file for an intent; [AttachPreparation.withPreparer]
/// runs `mpx_capture`'s `MediaPreparer`.
typedef PrepareFile =
    Future<PreparedMedia> Function(
      PreparationInput input,
      PreparationIntent intent,
    );

/// **Media preparation** for a send: every item of a request prepared by
/// its kind and the send options (photo downscale and JPEG, video preset,
/// files as they are), a few at a time, before the host makes the
/// messages.
///
/// Library assets are read through their originals (a file lease released
/// after); files and captures by their paths; a browser blob through
/// [IntakeItems]. An item whose source cannot be read is left out of the
/// result (the host sends what was prepared and tells the user).
final class AttachPreparation {
  /// A preparation running [prepare].
  AttachPreparation({
    required this.prepare,
    this.library,
    this.items,
    this.concurrency = 10,
  });

  /// A preparation over [preparer] under [policy].
  factory AttachPreparation.withPreparer(
    MediaPreparer preparer,
    PreparationPolicy policy, {
    MediaLibrary? library,
    IntakeItems? items,
    int concurrency = 10,
  }) => AttachPreparation(
    prepare: (input, intent) => preparer.prepare(input, intent, policy).result,
    library: library,
    items: items,
    concurrency: concurrency,
  );

  /// Prepares one file.
  final PrepareFile prepare;

  /// The device library, for library assets.
  final MediaLibrary? library;

  /// The intake files behind file and blob items.
  final IntakeItems? items;

  /// How many items are prepared at once.
  final int concurrency;

  /// The intent of [item] under [options].
  static PreparationIntent intentOf(AttachItem item, SendOptions options) {
    if (options.asFiles) return const PreparationIntent.file();
    return switch (item.kind) {
      AttachKind.photo => PreparationIntent.photo(
        highQuality: options.highQuality,
      ),
      AttachKind.video ||
      AttachKind.animation => const PreparationIntent.video(),
      AttachKind.audio || AttachKind.file => const PreparationIntent.file(),
    };
  }

  /// Prepares every item of [request], reporting the share done to
  /// [onProgress]; completes with the outputs by item.
  Future<Map<AttachItemId, PreparedMedia>> prepareAll(
    SendRequest request, {
    ValueChanged<double>? onProgress,
  }) async {
    final items = request.items;
    final done = <AttachItemId, PreparedMedia>{};
    var finished = 0;
    var next = 0;
    Future<void> worker() async {
      while (next < items.length) {
        final item = items[next++];
        try {
          final prepared = await _prepareOne(item, request.options);
          if (prepared != null) done[item.id] = prepared;
        } on Object catch (error, stack) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'attach_sheet',
              context: ErrorDescription('preparing ${item.id} to send'),
            ),
          );
        }
        finished++;
        onProgress?.call(finished / items.length);
      }
    }

    await Future.wait([
      for (var i = 0; i < math.min(concurrency, items.length); i++) worker(),
    ]);
    return done;
  }

  Future<PreparedMedia?> _prepareOne(
    AttachItem item,
    SendOptions options,
  ) async {
    final intent = intentOf(item, options);
    switch (item.source) {
      case AttachSource$Library(:final assetId):
        final library = this.library;
        if (library == null) return null;
        final lease = await library.original(LibraryAssetId(assetId));
        try {
          return await prepare(
            PreparationInput(lease.path, mimeType: lease.mimeType),
            intent,
          );
        } finally {
          await lease.release();
        }
      case AttachSource$File(:final path) ||
          AttachSource$Captured(localKey: final path):
        return prepare(
          PreparationInput(
            path,
            mimeType: item.facts.mimeType,
            byteSize: item.facts.byteSize,
          ),
          intent,
        );
      case AttachSource$Blob():
        final file = items?.fileOf(item.id);
        if (file case IntakeFile(source: IntakeSource$Blob(:final handle))) {
          return prepare(
            PreparationInput(
              '$handle',
              mimeType: file.mimeType,
              byteSize: file.size,
            ),
            intent,
          );
        }
        return null;
      case AttachSource$Pasted(:final localKey):
        return prepare(PreparationInput(localKey), intent);
    }
  }
}

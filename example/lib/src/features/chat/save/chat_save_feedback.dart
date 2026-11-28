import 'dart:async';

import 'package:bulletins/bulletins.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/chat_save_strings.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/chat_save_wiring.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_bulletins.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:mpx_library/mpx_library.dart';

/// Shows the progress of a save over the chat and answers a way to close
/// it; the host's dialog by default (`SaveProgressDialog.show`).
typedef ChatSaveProgressPresenter =
    VoidCallback Function(ChatSaveProgress progress);

/// Where the user cancelled a save from its progress.
enum ChatSaveCancelSource {
  /// The dialog's cancel button.
  dialog,

  /// The system back, which closes the dialog by cancelling.
  back,
}

/// A save job's progress as its dialog shows it: how far the job is, and
/// the cancel the dialog offers.
final class ChatSaveProgress {
  ChatSaveProgress._(this._job, this._onCancel);

  final SaveJob _job;
  final void Function(ChatSaveCancelSource from) _onCancel;
  bool _$cancelled = false;

  /// How far the job is, from 0 to 1.
  ValueListenable<double> get fraction => _job.progress;

  /// Cancels the job and closes its dialog. Only the first call counts: a
  /// burst of taps on the button, or a tap and a back, cancels once.
  void cancel({ChatSaveCancelSource from = ChatSaveCancelSource.dialog}) {
    if (_$cancelled) return;
    _$cancelled = true;
    _onCancel(from);
  }
}

/// The feedback of the chat's save jobs, headless: a progress dialog only
/// when a job runs past [progressDelay], and the bulletin its results earn.
///
/// - **Progress**: a job still running [progressDelay] after it started
///   shows [present]'s dialog, which offers a cancel; the dialog closes when
///   the job ends or is cancelled. A save to a place the user picks
///   (`SaveDestination.ask`) shows none: the system's save dialog is up
///   for most of that job, and a progress under it says nothing.
/// - **Saved**: every item saved gives a "saved to …" bulletin per
///   destination, kind and count; a Downloads one links its word to
///   [openDownloads]. A save to a picked place gives none: the user saw
///   where it went.
/// - **Failed**: any item failed gives a bulletin with the first failure's
///   reason.
/// - **Cancelled**: any item cancelled gives no bulletin.
///
/// One per chat screen, disposed before its [BulletinController].
final class ChatSaveFeedback {
  /// Feedback of the chat [chatId]'s saves, shown through [bulletins] and
  /// [present].
  ChatSaveFeedback({
    required this.chatId,
    required BulletinController bulletins,
    required ChatSaveProgressPresenter present,
    this.strings = ChatSaveStrings.demo,
    VoidCallback? openDownloads,
    DateTime Function()? now,
  }) : _bulletins = bulletins,
       _present = present,
       _openDownloads = openDownloads,
       _now = now ?? DateTime.now;

  /// How long a job runs before its progress dialog shows: the recommended
  /// host default. A quicker save shows its bulletin alone, with no dialog
  /// flashing up and away.
  static const Duration progressDelay = Duration(milliseconds: 250);

  /// The leading of a bulletin of a save to the gallery.
  static const ChromeIconId galleryIcon = ChromeIconId('bulletin.savedGallery');

  /// The leading of a bulletin of a save to the Downloads.
  static const ChromeIconId downloadsIcon = ChromeIconId(
    'bulletin.savedDownloads',
  );

  /// The painters of [galleryIcon] and [downloadsIcon], which the host
  /// registers beside the chat's other bulletin icons.
  static const Map<ChromeIconId, ChromeIconPainter> icons = {
    galleryIcon: ChromeIconPainter.font(Icons.photo_library_outlined),
    downloadsIcon: ChromeIconPainter.font(Icons.download_rounded),
  };

  /// The chat the events name.
  final String chatId;

  /// The words of the dialog and the bulletins.
  final ChatSaveStrings strings;

  final BulletinController _bulletins;
  final ChatSaveProgressPresenter _present;
  final VoidCallback? _openDownloads;
  final DateTime Function() _now;

  final Set<Timer> _$timers = {};
  bool _$disposed = false;

  /// Follows [job], a save of items of [kinds] to [destination], to its
  /// end.
  void follow(
    SaveJob job, {
    required Iterable<MediaItemKind> kinds,
    required SaveDestination destination,
  }) {
    if (_$disposed) return;
    final started = _now();
    final kindList = kinds.toList(growable: false);
    final correlation = ChatCorrelation(chatId: chatId, jobId: job.id);
    int sinceStart() => _now().difference(started).inMilliseconds;
    var ended = false;
    VoidCallback? dismiss;
    void close() {
      dismiss?.call();
      dismiss = null;
    }

    // Cancelled when the job ends first, so a quick job leaves no timer.
    final delay = switch (destination) {
      SaveDestination$Ask() => null,
      _ => Timer(progressDelay, () {
        if (ended || _$disposed) return;
        final progress = ChatSaveProgress._(job, (from) {
          ChatDiagnostics.current.emit(
            ChatEventLevel.debug,
            ChatEventCategory.save,
            ChatSaveOp.feedbackCancelled,
            correlation: correlation,
            fields: () => {
              'from': from.name,
              'ms': sinceStart(),
              'percent': (job.progress.value * 100).round(),
            },
          );
          job.cancel();
          close();
        });
        dismiss = _present(progress);
        _shown(correlation, 'progressDialog', sinceStart());
      }),
    };
    if (delay != null) _$timers.add(delay);

    unawaited(
      job.results.then((results) {
        ended = true;
        if (delay != null) {
          delay.cancel();
          _$timers.remove(delay);
        }
        close();
        if (_$disposed) return;
        switch (_bulletinOf(results, kindList, destination)) {
          case (final bulletin, final form, final reason):
            _bulletins.show(bulletin);
            _shown(correlation, form, sinceStart(), reason: reason);
          case null:
            break;
        }
      }),
    );
  }

  void _shown(
    ChatCorrelation correlation,
    String form,
    int ms, {
    SaveFailure? reason,
  }) => ChatDiagnostics.current.emit(
    ChatEventLevel.debug,
    ChatEventCategory.save,
    ChatSaveOp.feedbackShown,
    correlation: correlation,
    fields: () => {'form': form, 'ms': ms, 'reason': ?reason?.name},
  );

  // The bulletin of [results] with its form and failure, or null for none:
  // a cancel shows nothing, a failure wins over the items saved beside it.
  (Bulletin, String, SaveFailure?)? _bulletinOf(
    List<SaveResult> results,
    List<MediaItemKind> kinds,
    SaveDestination destination,
  ) {
    SaveFailure? failure;
    for (final result in results) {
      switch (result) {
        case SaveResult$Cancelled():
          return null;
        case SaveResult$Failed(:final reason):
          failure ??= reason;
        case SaveResult$Saved():
          break;
      }
    }
    if (failure case final reason?) {
      return (
        ChatBulletins.error(strings.failed(reason)),
        'failedBulletin',
        reason,
      );
    }
    final kind = switch (kinds.toSet().toList()) {
      [final kind] => kind,
      _ => null,
    };
    final count = results.length;
    final bulletin = switch (destination) {
      SaveDestination$Gallery() => Bulletin(
        message: strings.savedToGallery(kind, count),
        leading: const BulletinLeading.icon(galleryIcon),
        duration: BulletinDuration.short,
      ),
      SaveDestination$Downloads() => _downloadsBulletin(
        strings.savedToDownloads(kind, count),
      ),
      SaveDestination$Ask() => null,
    };
    return switch (bulletin) {
      final bulletin? => (bulletin, 'savedBulletin', null),
      null => null,
    };
  }

  Bulletin _downloadsBulletin(String message) {
    final start = message.indexOf(strings.downloadsLink);
    return Bulletin(
      message: message,
      leading: const BulletinLeading.icon(downloadsIcon),
      duration: BulletinDuration.short,
      links: switch ((_openDownloads, start)) {
        (final open?, >= 0) => [
          BulletinLink(
            start: start,
            end: start + strings.downloadsLink.length,
            onTap: open,
          ),
        ],
        _ => const [],
      },
    );
  }

  /// Stops showing feedback: no dialog opens and no bulletin shows after
  /// this. A dialog already up still closes when its job ends; the jobs
  /// themselves run on. Idempotent.
  void dispose() {
    if (_$disposed) return;
    _$disposed = true;
    for (final timer in _$timers) {
      timer.cancel();
    }
    _$timers.clear();
  }
}

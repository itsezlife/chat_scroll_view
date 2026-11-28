import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:mpx_core/mpx_core.dart' show TrackedTransfers;
import 'package:mpx_library/mpx_library.dart';

/// The example's diagnostics ops for saving media (category `save`).
///
/// The menus, the viewer action and the feedback add theirs here; the
/// saver's own events are mpx's (`mpx_library`'s `SaveOp`), bridged into the
/// journal with the rest of the media side.
enum ChatSaveOp implements DiagnosticOp {
  /// The composition root made its saver (info; warning when the define
  /// could not be read): `transfers` whether `saveContent` can download
  /// through tracked transfers, `subfolder` whether the host names a
  /// sub-folder, `define` the Apple save define (`on`, `off`, `notNeeded`
  /// elsewhere, `unknown` when the read failed).
  saverWired,

  /// The maintainer saved the demo item from the save debug panel (info):
  /// `destination`, with the save job as `jobId`; at warning, with the
  /// error and no job, when the demo item could not be read.
  debugSave,

  /// A menu or the selection bar offers a save entry (debug): the items'
  /// `kind` (`mixed` for several kinds), the `platform`, the entry's
  /// `destination` and the `batch` (`single`, `album`, `selection`).
  entriesOffered,

  /// A save entry the items would have is not offered (info): `why`
  /// (`protection`, `linkPreviewPart`) and whether it went `live`, from an
  /// entry offered before (the selection bar).
  entriesHidden,

  /// A save entry started its job (info): the `source` (`menu`, `album`,
  /// `selection`, `viewer`), the number of `items` and the `destination`,
  /// with the job as `jobId`; a single item also names its item and media
  /// key.
  saveStarted,

  /// A tap on a save entry was dropped by the input guard (debug): `ms`
  /// since the tap that started the job.
  saveDropped,

  /// A save that protection denies reached the host anyway (info): `path`
  /// (`staleMenu`, `viewer`); the chat's denial feedback reports
  /// `capabilities` / `denied` beside it.
  saveDenied,

  /// A save job's feedback showed (debug): the `form` (`progressDialog`,
  /// `savedBulletin`, `failedBulletin`) and the `ms` since the job started;
  /// a failure also names its `reason`. The job is the `jobId`.
  feedbackShown,

  /// The user cancelled a save job from its progress dialog (debug): `from`
  /// (`dialog`, `back`), the `ms` since the job started and the job's
  /// `percent` done. The job is the `jobId`.
  feedbackCancelled,
}

/// Makes the app's one [MediaSaver] over the composition's [transfers]
/// (null where no transfer engine is composed).
typedef MediaSaverStarter = MediaSaver Function({TrackedTransfers? transfers});

/// The example's choices around its [MediaSaver]: the platform saver, the
/// sub-folder its saves go into, and the report of what was wired.
abstract final class ChatSaveWiring {
  /// The sub-folder of Downloads (and, on Android, of the gallery's
  /// collections) the example's saves go into: the host's name, not the
  /// package's (spec S13).
  static const String subfolder = 'Chat Scroll View';

  /// The example's Downloads destination, in its [subfolder].
  static const SaveDestination downloads = SaveDestination.downloads(
    subfolder: subfolder,
  );

  /// The platform's saver, downloading what is not local through
  /// [transfers] first.
  static MediaSaver platform({TrackedTransfers? transfers}) =>
      PlatformMediaSaver(transfers: transfers);

  /// Reports [ChatSaveOp.saverWired] for [saver]; [transfers] says whether
  /// the composition handed it tracked transfers.
  ///
  /// On Apple the save code compiles only under the host's `MPX_LIBRARY_SAVE`
  /// condition, which Dart cannot see: the gallery's access tells. It is
  /// read, never asked for, so the report shows no prompt. Elsewhere there
  /// is no define, and nothing is read.
  static Future<void> report(
    MediaSaver saver, {
    required bool transfers,
  }) async {
    final apple = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => !kIsWeb,
      _ => false,
    };
    var define = 'notNeeded';
    Object? failure;
    StackTrace? failureStack;
    if (apple) {
      try {
        final access = await saver.access(const SaveDestination.gallery());
        define = access == SaveAccess.unavailable ? 'off' : 'on';
      } on Object catch (error, stackTrace) {
        define = 'unknown';
        failure = error;
        failureStack = stackTrace;
      }
    }
    ChatDiagnostics.current.emit(
      failure == null ? ChatEventLevel.info : ChatEventLevel.warning,
      ChatEventCategory.save,
      ChatSaveOp.saverWired,
      error: failure,
      stackTrace: failureStack,
      fields: () => {
        'transfers': transfers,
        'subfolder': subfolder.isNotEmpty,
        'define': define,
      },
    );
  }
}

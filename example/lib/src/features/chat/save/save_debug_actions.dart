import 'dart:async';

import 'package:chat_scroll_view_example/src/features/chat/save/chat_save_wiring.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:mpx_library/mpx_library.dart';

/// The save debug panel's actions, headless: save the demo item to each
/// destination the example's menus use, through the app's one saver, and
/// keep each destination's last outcome for the panel.
///
/// For the device checks: one tap per destination, and the saver's own
/// events (`save` in the journal) tell the rest. A burst of taps on one
/// destination saves once: a destination ignores taps for [guardWindow]
/// after one ran, so a double tap never writes the item twice.
final class SaveDebugActions {
  /// Actions saving [demoItem]'s item (read once, on the first save)
  /// through [saver].
  SaveDebugActions({
    required MediaSaver saver,
    required Future<SaveItem> Function() demoItem,
  }) : _saver = saver,
       _demoItem = demoItem;

  /// How long a tapped destination ignores further taps.
  static const Duration guardWindow = Duration(milliseconds: 600);

  /// The destinations the panel offers, in its order: the gallery without
  /// an album (an album needs read and write access on Apple), the
  /// example's Downloads sub-folder, and the save dialog.
  static const List<SaveDestination> destinations = [
    SaveDestination.gallery(),
    ChatSaveWiring.downloads,
    SaveDestination.ask(),
  ];

  final MediaSaver _saver;
  final Future<SaveItem> Function() _demoItem;
  Future<SaveItem>? _$item;
  final Map<String, Timer> _$guards = {};
  bool _$disposed = false;

  /// Each destination's last outcome by its name: `saving`, `saved`,
  /// `cancelled` or `failed: <reason>`; absent until it saved once.
  ValueListenable<Map<String, String>> get outcomes => _$outcomes;
  final ValueNotifier<Map<String, String>> _$outcomes = ValueNotifier(const {});

  /// Saves the demo item to [destination]; answers its job, or null when
  /// the tap was dropped (inside [guardWindow], or after [dispose]).
  Future<SaveJob?> saveDemoTo(SaveDestination destination) async {
    if (!_admit(destination.name)) return null;
    _outcome(destination, 'saving');
    final SaveItem item;
    try {
      item = await (_$item ??= _demoItem());
    } on Object catch (error, stackTrace) {
      // Read again on the next tap, not failed for the rest of the run.
      _$item = null;
      if (!_$disposed) _outcome(destination, 'failed: demoItem');
      ChatDiagnostics.current.emit(
        ChatEventLevel.warning,
        ChatEventCategory.save,
        ChatSaveOp.debugSave,
        error: error,
        stackTrace: stackTrace,
        fields: () => {'destination': destination.name},
      );
      return null;
    }
    if (_$disposed) return null;
    final job = _saver.save([item], destination);
    ChatDiagnostics.current.emit(
      ChatEventLevel.info,
      ChatEventCategory.save,
      ChatSaveOp.debugSave,
      correlation: ChatCorrelation(jobId: job.id),
      fields: () => {'destination': destination.name},
    );
    unawaited(
      job.results.then((results) {
        if (_$disposed) return;
        _outcome(destination, switch (results.single) {
          SaveResult$Saved() => 'saved',
          SaveResult$Cancelled() => 'cancelled',
          SaveResult$Failed(:final reason) => 'failed: ${reason.name}',
        });
      }),
    );
    return job;
  }

  void _outcome(SaveDestination destination, String outcome) =>
      _$outcomes.value = {..._$outcomes.value, destination.name: outcome};

  // A destination runs when no tap ran it within [guardWindow]; a timer
  // rather than a clock, so the window runs on a test's fake time.
  bool _admit(String destination) {
    if (_$disposed || _$guards.containsKey(destination)) return false;
    _$guards[destination] = Timer(
      guardWindow,
      () => _$guards.remove(destination),
    );
    return true;
  }

  /// Cancels the guards. Idempotent; a job already running finishes.
  void dispose() {
    if (_$disposed) return;
    _$disposed = true;
    for (final guard in _$guards.values) {
      guard.cancel();
    }
    _$guards.clear();
    _$outcomes.dispose();
  }
}

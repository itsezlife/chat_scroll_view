import 'dart:async';

import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_transfers.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_upload_transport.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/environment_specific/process_kill.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

/// The example's diagnostics op for the outbox debug panel.
enum OutboxDebugOp implements DiagnosticOp {
  /// The maintainer took a debug action (warning, so the journal writes it
  /// at once and it survives a kill): `action` is `killIn3s`,
  /// `cutNetwork`, `restoreNetwork` or `systemInterruption`, with the open
  /// chat.
  debugAction,
}

/// What the debug panel reads from, and does to, the transfer engine.
///
/// A seam rather than the engine itself: the panel's tests run over a fake
/// outbox, which opens no engine, and the engine cannot be told apart from
/// its snapshot in a test without running real jobs.
abstract interface class TransferDebugHooks {
  /// The hooks over [transfers]: [cut] is the switch the engine's
  /// connectivity and requests read (see [DemoTransfers.followNetwork]),
  /// and [transport] the in-process transport, failed while cut.
  factory TransferDebugHooks.engine(
    Transfers transfers, {
    required DemoNetworkCut cut,
    DemoUploadTransport? transport,
  }) = _EngineDebugHooks;

  /// The engine's state now; null when there is none.
  TransfersDebugSnapshot? snapshot();

  /// Cuts the engine's network ([cut] true) or gives it back.
  void cutNetwork({required bool cut});

  /// Acts as if the system ended the OS envelope now; answers how many
  /// jobs paused.
  int simulateSystemInterruption();
}

final class _EngineDebugHooks implements TransferDebugHooks {
  _EngineDebugHooks(this._transfers, {required this.cut, this.transport});

  final Transfers _transfers;
  final DemoNetworkCut cut;
  final DemoUploadTransport? transport;

  @override
  TransfersDebugSnapshot snapshot() => _transfers.debugSnapshot();

  @override
  void cutNetwork({required bool cut}) {
    transport?.offline = cut;
    this.cut.value = cut;
  }

  @override
  int simulateSystemInterruption() =>
      _transfers.debugSimulateSystemInterruption();
}

/// The debug panel's actions, headless: kill the process in 3 s, cut the
/// engine's network and give it back, and act out a system interruption.
///
/// Each action reports `debugAction` before it acts, at warning level, so
/// the journal writes it at once and a kill does not lose it. A burst of
/// taps on one action acts once: an action is ignored for [guardWindow]
/// after it ran. Made once for the app, so a kill asked for outlives the
/// panel that asked.
final class OutboxDebugActions {
  /// Actions over [engine] (none without one: the engine actions do
  /// nothing), exiting the process through [exit].
  OutboxDebugActions({
    required TransferDebugHooks? engine,
    VoidCallback exit = $killProcess,
    this.killDelay = const Duration(seconds: 3),
  }) : _engine = engine,
       _exit = exit;

  /// How long a tapped action ignores further taps.
  static const Duration guardWindow = Duration(milliseconds: 600);

  final TransferDebugHooks? _engine;
  final VoidCallback _exit;

  /// How long after [killIn] the process ends.
  final Duration killDelay;

  /// The transfer engine's state now; null without an engine.
  TransfersDebugSnapshot? engineSnapshot() => _engine?.snapshot();

  /// Whether the panel has an engine to act on.
  bool get hasEngine => _engine != null;

  /// Whether a kill is due.
  ValueListenable<bool> get killPending => _$killPending;
  final ValueNotifier<bool> _$killPending = ValueNotifier(false);

  /// Whether the engine's network is cut.
  ValueListenable<bool> get networkCut => _$networkCut;
  final ValueNotifier<bool> _$networkCut = ValueNotifier(false);

  Timer? _$kill;
  final Map<_Guarded, Timer> _$guards = {};
  bool _$disposed = false;

  /// Ends the process [killDelay] from now, as the system would kill it.
  void killIn(String chatId) {
    if (_$kill != null || !_admit(_Guarded.kill)) return;
    _report(chatId, 'killIn3s');
    _$kill = Timer(killDelay, _exit);
    _$killPending.value = true;
  }

  /// Calls off a pending kill.
  void cancelKill() {
    if (!_admit(_Guarded.kill)) return;
    _$kill?.cancel();
    _$kill = null;
    _$killPending.value = false;
  }

  /// Cuts the engine's network: its requests fail and it reads offline.
  void cutNetwork(String chatId) => _setCut(chatId, cut: true);

  /// Gives the engine its network back.
  void restoreNetwork(String chatId) => _setCut(chatId, cut: false);

  void _setCut(String chatId, {required bool cut}) {
    final engine = _engine;
    if (engine == null || _$networkCut.value == cut) return;
    if (!_admit(_Guarded.network)) return;
    _report(chatId, cut ? 'cutNetwork' : 'restoreNetwork');
    engine.cutNetwork(cut: cut);
    _$networkCut.value = cut;
  }

  /// Acts as if the system ended the OS envelope now; answers how many
  /// jobs paused (0 when the tap was dropped or there is no engine).
  int simulateSystemInterruption(String chatId) {
    final engine = _engine;
    if (engine == null || !_admit(_Guarded.interruption)) return 0;
    _report(chatId, 'systemInterruption');
    return engine.simulateSystemInterruption();
  }

  // An action runs when no tap ran it within [guardWindow]; a timer rather
  // than a clock, so the window runs on a test's fake time.
  bool _admit(_Guarded action) {
    if (_$disposed || _$guards.containsKey(action)) return false;
    _$guards[action] = Timer(guardWindow, () => _$guards.remove(action));
    return true;
  }

  static void _report(String chatId, String action) =>
      ChatDiagnostics.current.emit(
        ChatEventLevel.warning,
        ChatEventCategory.outbox,
        OutboxDebugOp.debugAction,
        correlation: ChatCorrelation(chatId: chatId),
        fields: () => {'action': action},
      );

  /// Cancels a pending kill and the guards. Idempotent.
  void dispose() {
    if (_$disposed) return;
    _$disposed = true;
    _$kill?.cancel();
    _$kill = null;
    for (final guard in _$guards.values) {
      guard.cancel();
    }
    _$guards.clear();
    _$killPending.dispose();
    _$networkCut.dispose();
  }
}

enum _Guarded { kill, network, interruption }

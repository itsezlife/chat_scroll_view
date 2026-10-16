import 'package:chat_scroll_view_example/src/features/chat/input/chat_input_set.dart';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:l/l.dart';
import 'package:listen/listen.dart' as listen;

/// Whether the panel's signals are logged: `--dart-define=PANEL_TRACE=true`.
const bool kPanelTrace = bool.fromEnvironment('PANEL_TRACE');

/// Logs every change of the signals that make up the chat's bottom space, in
/// the order they happen, so a frame-level problem (a jump, a dip, a late
/// keyboard) can be read from a log instead of guessed at from the screen.
///
/// Each line is `panel <ms> <signal> <value>`, with `<ms>` from the moment the
/// trace was attached. Read it with `adb logcat -s flutter | grep "panel "`.
/// The trace follows the input set's own notifiers and owns none of them;
/// [dispose] stops it.
final class PanelTrace {
  /// Starts tracing [input].
  PanelTrace(this.input) {
    _watch('state', input.presentation.state, (v) => '$v');
    _watch('slot', input.keyboardStrategy.state, (v) => '$v');
    _watch(
      'occupancy',
      input.presentation.occupancy,
      (o) => o.bottom.toStringAsFixed(1),
    );
    _watch('composerSafe', input.keyboardStrategy.composerSafeInset, _fixed);
    _watch('composerExtent', input.composer.extent, _fixed);
    _watch(
      'ime',
      input.ime.samples,
      (s) => '${s.height} animating=${s.animating} safe=${s.safeAreaBottom}',
    );
    final padding = input.insets.bottomPadding;
    void onPadding() => _log('bottomPadding ${_fixed(padding.value)}');
    padding.addListener(onPadding);
    _undo.add(() => padding.removeListener(onPadding));
    _watch('softKeyboard', input.composer.softKeyboard, (v) => '$v');
    void onFocus() => _log('composerFocus ${input.composer.hasFocus}');
    input.composer.focusNode.addListener(onFocus);
    _undo.add(() => input.composer.focusNode.removeListener(onFocus));
    _log('attached');
  }

  /// The traced set.
  final ChatInputSet input;

  final _stopwatch = Stopwatch()..start();
  final _undo = <VoidCallback>[];

  void _log(String message) =>
      l.i('panel ${_stopwatch.elapsedMilliseconds} $message');

  void _watch<T>(
    String name,
    listen.ValueListenable<T> listenable,
    String Function(T value) show,
  ) {
    void onChange() => _log('$name ${show(listenable.value)}');

    listenable.addListener(onChange);
    _undo.add(() => listenable.removeListener(onChange));
  }

  static String _fixed(double value) => value.toStringAsFixed(1);

  /// Stops tracing.
  void dispose() {
    for (final undo in _undo) {
      undo();
    }
    _undo.clear();
  }
}

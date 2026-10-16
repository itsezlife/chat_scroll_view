import 'dart:async';

import 'package:listen/listen.dart';

/// The shared search helper of pages: turns a stream of typed text into
/// debounced searches whose stale results never surface.
///
/// A page forwards each change of the shell's query to [update]. The helper
/// waits for typing to pause, runs [search] once, and hands the result to
/// [onResult] only if no newer text arrived meanwhile, which is the whole of
/// its **generation** rule: every [update] that changes the trimmed text
/// invalidates whatever was scheduled or in flight before it.
///
/// ## Behaviour
///
/// - Text is trimmed. Trimmed-empty text cancels everything, drops any reply
///   still in flight and calls [onCleared] at once.
/// - The same trimmed text as the last [update] changes nothing, so a rebuild
///   that repeats the query does not restart the debounce.
/// - [busy] turns true [busyDelay] after the text changed, so a fast reply
///   never flashes progress, and false when the reply lands, is dropped or
///   the text is cleared.
/// - A [search] that throws is reported to the zone's uncaught-error handler
///   and ends the busy state; no result is published.
/// - After [dispose] timers are cancelled and nothing is published.
final class DebouncedSearch<R> {
  /// A helper running [search] and publishing through [onResult] and
  /// [onCleared].
  DebouncedSearch({
    required Future<R> Function(String query) search,
    required void Function(String query, R result) onResult,
    void Function()? onCleared,
    this.debounce = defaultDebounce,
    this.busyDelay = defaultBusyDelay,
  }) : _search = search,
       _onResult = onResult,
       _onCleared = onCleared;

  /// How long typing must pause before a search runs.
  static const Duration defaultDebounce = Duration(milliseconds: 300);

  /// How long after the text changed before [busy] turns true.
  static const Duration defaultBusyDelay = Duration(milliseconds: 65);

  /// How long typing must pause before a search runs.
  final Duration debounce;

  /// How long after the text changed before [busy] turns true.
  final Duration busyDelay;

  final Future<R> Function(String query) _search;
  final void Function(String query, R result) _onResult;
  final void Function()? _onCleared;

  final _busy = ValueNotifier<bool>(false);
  Timer? _debounceTimer;
  Timer? _busyTimer;
  var _generation = 0;
  var _lastQuery = '';
  var _disposed = false;

  /// Whether a search for the latest text is pending or in flight and has
  /// been for longer than [busyDelay].
  ValueListenable<bool> get busy => _busy;

  /// Feeds the latest text of the query.
  void update(String text) {
    if (_disposed) return;
    final query = text.trim();
    if (query == _lastQuery) return;
    _lastQuery = query;
    final generation = ++_generation;
    _debounceTimer?.cancel();
    _busyTimer?.cancel();

    if (query.isEmpty) {
      _busy.value = false;
      _onCleared?.call();
      return;
    }

    _busyTimer = Timer(busyDelay, () => _busy.value = true);
    _debounceTimer = Timer(debounce, () => _run(query, generation));
  }

  Future<void> _run(String query, int generation) async {
    try {
      final result = await _search(query);
      if (_disposed || generation != _generation) return;
      _busyTimer?.cancel();
      _busy.value = false;
      _onResult(query, result);
    } on Object catch (error, stackTrace) {
      if (_disposed || generation != _generation) return;
      _busyTimer?.cancel();
      _busy.value = false;
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }

  /// Cancels pending work and stops publishing. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _debounceTimer?.cancel();
    _busyTimer?.cancel();
    _busy.dispose();
  }
}

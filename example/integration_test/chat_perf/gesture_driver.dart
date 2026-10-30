/// What a selection, menu or rich-text script may do: held-pointer gestures,
/// the designated targets of the `rich` corpus profile and the public
/// selection facade, nothing else.
library;

import 'dart:ui';

import 'package:chat_scroll_view/chat_scroll_view.dart';

import 'corpus_rich.dart';
import 'metrics.dart';

/// One pointer that stays down: a long-press and the drag that continues it.
abstract interface class PointerStream {
  /// Keeps the pointer still for [duration] of live wall time, a frame at a
  /// time. Returns how long after the pointer went down [watch] first held,
  /// or null if it never did (or none was given).
  Future<Duration?> hold(Duration duration, {bool Function()? watch});

  /// Moves the pointer by [delta] over [frames] frames, one move per frame.
  Future<void> moveBy(Offset delta, {required int frames});

  /// Lifts the pointer.
  Future<void> up();
}

/// The public selection facade, read as numbers.
final class SelectionState {
  const SelectionState({
    required this.selectedIds,
    required this.isTextSelectionActive,
    required this.textSelectionSubject,
    required this.extentChars,
  });

  final Set<int> selectedIds;
  final bool isTextSelectionActive;
  final int? textSelectionSubject;

  /// Characters between the text selection's two ends inside one block, or 0
  /// with no text selection.
  final int extentChars;
}

/// The driver a script gets from its context.
abstract interface class GestureDriver {
  /// The viewport's global rect.
  Rect get viewportRect;

  /// The bubble of [target] in global coordinates.
  Rect rowRect(BenchTarget target);

  /// The markdown body of [target] in global coordinates.
  Rect bodyRect(BenchTarget target);

  /// The markdown body of [target] while it is mounted, else null.
  Rect? bodyRectIfMounted(BenchTarget target);

  /// Jumps so the message [id] sits mid-viewport and settles.
  Future<void> seat(int id);

  /// Jumps to [target] and settles; throws when the history is too short to
  /// hold the rich profile.
  Future<void> seatTarget(BenchTarget target);

  /// Puts a pointer down at [global].
  Future<PointerStream> down(Offset global);

  /// A tap: down, [hold] of live time, up.
  Future<void> tap(
    Offset global, {
    Duration hold = const Duration(milliseconds: 50),
  });

  /// A short, fast drag of [dy] over [over], the 6.7k px/s fling when
  /// `dy / over` is that.
  Future<void> fling(double dy, Duration over);

  /// Idles [count] live frames.
  Future<void> frames(int count);

  /// Idles live frames until none is scheduled, at most [cap]; returns how
  /// many ran.
  Future<int> framesUntilIdle({int cap = 240});

  /// Frames drawn since the host mounted.
  int get frameCount;

  /// Current facade state.
  SelectionState get state;

  /// Clears message selection, as the app bar's close does.
  void clearSelection();

  /// Interactions the facade reported since the host mounted.
  List<ChatSelectionInteraction> get interactions;

  /// Time from the last pointer-up to the idle message tap request, null when
  /// none arrived.
  Duration? get menuRequestLatency;

  /// Whether a message menu session is presented.
  bool get menuOpen;

  /// Dismisses the menu by tapping outside it and waits for it to close.
  Future<void> dismissMenu();

  /// Metrics of a window already measured.
  Map<String, Metric> metricsOf(String window);

  /// Adds [metrics] to a window already measured.
  void report(String window, Map<String, Metric> metrics);
}

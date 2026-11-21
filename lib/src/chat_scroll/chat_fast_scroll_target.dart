import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:viewport_scroll/viewport_scroll.dart';

/// The chat as a `FastScrollTarget`: its [controller]'s
/// [ChatScrollController.scrollProgress] read, and
/// [ChatScrollController.jumpToProgress] to move.
///
/// The progress is the anchor viewport's estimate over the known span
/// (linear in message ids, ADR 002), the same one its own scrollbar paints;
/// there is no pixel extent to fake. A drag freezes the visible share at its
/// start, as the viewport's own scrollbar grab does, so the mapping under
/// the finger holds still while rows of other heights come into view. A
/// stop re-seats the band where it stands, which ends a fling.
///
/// Adapters on one controller are equal and share the frozen share.
@immutable
final class ChatFastScrollTarget extends FastScrollTarget {
  /// The target of [controller].
  const ChatFastScrollTarget(this.controller);

  /// The controller moved.
  final ChatScrollController controller;

  // The visible share frozen by a drag on each controller.
  static final _dragShare = Expando<double>('ChatFastScrollTarget');

  @override
  double? get progress => controller.scrollProgress.value?.progress;

  @override
  double get visibleShare => controller.scrollProgress.value?.visibleShare ?? 1;

  @override
  void jumpTo(double progress) {
    controller.jumpToProgress(
      progress,
      visibleShare: _dragShare[controller] ?? visibleShare,
    );
  }

  @override
  void stop() {
    if (progress case final p?) jumpTo(p);
  }

  @override
  void dragStarted() => _dragShare[controller] = visibleShare;

  @override
  void dragEnded() => _dragShare[controller] = null;

  @override
  void addListener(VoidCallback listener) =>
      controller.scrollProgress.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      controller.scrollProgress.removeListener(listener);

  @override
  bool operator ==(Object other) =>
      other is ChatFastScrollTarget && identical(other.controller, controller);

  @override
  int get hashCode => identityHashCode(controller);
}

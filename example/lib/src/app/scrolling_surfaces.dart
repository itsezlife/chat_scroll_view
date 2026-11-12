import 'dart:async';

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:panel_shell/panel_shell.dart';

/// Whether any of the app's scrolling surfaces moves now: the chat list or
/// the panel's catalogue, under a drag or a fling.
///
/// The texture pool's `scrolling` signal (ADR 043, "Pool"): it creates no
/// texture while this is true. The emoji glyph bake holds on it too (ADR 022,
/// *Amendment: glyph bake holds*): no strip or page is baked while any
/// surface moves.
final class ScrollingSurfaces extends ChangeNotifier
    implements ValueListenable<bool> {
  final Set<Object> _moving = {};

  @override
  bool get value => _moving.isNotEmpty;

  /// Says whether [surface] moves; the value is true while any one does.
  void report(Object surface, {required bool scrolling}) {
    final was = value;
    if (scrolling) {
      _moving.add(surface);
    } else {
      _moving.remove(surface);
    }
    if (value != was) notifyListeners();
  }

  /// Follows the chat list of [controller]: it moves from a drag start, a
  /// fling start or an animated scroll's start until all of them ended. The
  /// callback stops following, and the list then rests.
  ///
  /// The rest is published a microtask late: the viewport ends a drag and
  /// starts its fling in one call, and the list does not stop between them.
  VoidCallback followChat(ChatScrollController controller) {
    var dragging = false;
    var flinging = false;
    var animating = false;
    var following = true;

    void settle() {
      if (!following || dragging || flinging || animating) return;
      report(controller, scrolling: false);
    }

    void onEvent(ChatScrollEvent event) {
      switch (event) {
        case ChatUserDragStart():
          dragging = true;
        case ChatUserDragEnd():
          dragging = false;
        case ChatFlingStart():
          flinging = true;
        case ChatFlingEnd():
          flinging = false;
        case ChatAnimateStart():
          animating = true;
        case ChatAnimateEnd():
          animating = false;
        default:
          return;
      }
      if (dragging || flinging || animating) {
        report(controller, scrolling: true);
      } else {
        scheduleMicrotask(settle);
      }
    }

    controller.addScrollListener(onEvent);
    return () {
      following = false;
      controller.removeScrollListener(onEvent);
      report(controller, scrolling: false);
    };
  }

  /// Follows the panel of [shell]: it moves while its selected page reports a
  /// drag, a fling or a jump, and rests at the page's idle report (one quiet
  /// frame after the catalogue stopped) and when another page is selected,
  /// whose idle report the shell would drop. The callback stops following,
  /// and the panel then rests.
  VoidCallback followPanel(PanelShellController shell) {
    final activity = shell.scrollActivity.listen(
      (activity) => report(shell, scrolling: activity is! PageScrollIdle),
    );
    void onSelected() => report(shell, scrolling: false);
    shell.selectedPageId.addListener(onSelected);
    return () {
      unawaited(activity.cancel());
      shell.selectedPageId.removeListener(onSelected);
      report(shell, scrolling: false);
    };
  }
}

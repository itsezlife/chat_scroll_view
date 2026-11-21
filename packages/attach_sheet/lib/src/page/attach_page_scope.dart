import 'package:attach_sheet/src/page/attach_page.dart';
import 'package:attach_sheet/src/panel/attach_send_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The **attach page** hooks: what a page may ask of the sheet that hosts
/// it. A page gets its own in its builder, and `AttachPageScope.of(context)`
/// finds it below.
///
/// Settings (pan, top offset, header items, dismiss guard, main button,
/// panel hidden) are the page's own and apply while its tab is shown.
abstract interface class AttachPageScope {
  /// The scope of the page above [context].
  static AttachPageScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AttachPageScopeProvider>();
    assert(scope != null, 'No attach page above this context.');
    return scope!.scope;
  }

  /// The page this scope belongs to.
  AttachPageId get page;

  /// Whether the page is the one shown; a camera preview pauses while it is
  /// false. Its changes are the page's `onShow` and `onHide`.
  ValueListenable<bool> get isActive;

  /// How present the page is on a page switch, 0 to 1: 1 at rest; the page
  /// coming in goes from 0 with the switch, the one going out down to 0 by
  /// 0.7 of it. A page fades what stands apart from its content (a live
  /// camera preview) by it.
  ValueListenable<double> get presence;

  /// The scroll controller the page's scrollable takes, shared with the
  /// sheet's drag.
  ScrollController get scrollController;

  /// The panel's state (caption, options, send), for a page that draws the
  /// panel elsewhere (the picker-mode viewer's bottom slot) or an overflow
  /// button in its header.
  AttachSendController get panel;

  /// Asks the sheet to rise to its top.
  void requestExpansion();

  /// Whether drags move the sheet while this page is shown; off for a
  /// gesture of the page's own.
  set panEnabled(bool value);

  /// The sheet's resting top while this page is shown; null for the
  /// policy's.
  set topOffset(double? value);

  /// The page's items in the sheet's pinned header (an album switcher, a
  /// menu); null for none.
  set headerItems(Widget? value);

  /// Asked before the sheet closes while this page is shown; false keeps it
  /// open. Null for none.
  set dismissGuard(Future<bool> Function()? value);

  /// What a tap on the shown tab does to the page; null scrolls
  /// [scrollController] to the top. The sheet also rises to its top.
  set onScrollToTop(VoidCallback? value);

  /// The button shown in place of the tab bar while this page is shown
  /// (host pages); null for the tabs.
  set mainButton(AttachMainButton? value);

  /// Whether the bottom panel hides while this page is shown (host pages).
  set panelHidden(bool value);

  /// Closes the sheet with this page's [payload]: `AttachOutcome.custom`.
  void finish(Object? payload);
}

/// Provides an [AttachPageScope] to a page's subtree.
@internal
final class AttachPageScopeProvider extends InheritedWidget {
  /// Provides [scope] to [child].
  const AttachPageScopeProvider({
    required this.scope,
    required super.child,
    super.key,
  });

  /// The page's scope.
  final AttachPageScope scope;

  @override
  bool updateShouldNotify(AttachPageScopeProvider oldWidget) =>
      !identical(scope, oldWidget.scope);
}

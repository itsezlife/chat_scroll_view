import 'dart:async';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_shell/src/controller/panel_shell_controller.dart';
import 'package:swipe_pager/swipe_pager.dart';

/// The pager: one swipeable page per registered page, kept in step with the
/// shell controller's selection.
///
/// It is a `SwipePager` (package `swipe_pager`): a drag swipes only past the
/// touch slop and direction rule, so a slightly diagonal
/// drag over a page's catalogue scrolls the catalogue, and a strip that
/// scrolls sideways in a page keeps its drags; a mouse does not drag it.
///
/// A swipe that goes on to another page calls `selectPage`, the same intent
/// a tab tap or a host uses; a selection made any other way moves the pager
/// with a jump (no scroll animation, because the tabs' capsule has its own
/// settle), or, given a [selectSlide], slides the chosen page in next to the
/// current one.
///
/// Pages are built lazily and, once built, kept alive for the life of the
/// pager, so at most the registered pages are kept: a type tab switched away
/// from keeps its page, with its cells, their frames and their positions. A page that is
/// not on screen is offstage and under `TickerMode(enabled: false)`: its
/// animations hold and a catalogue in it holds its bindings. What a page
/// must restore after the shell itself is rebuilt still lives in the
/// controller's registry.
///
/// Swiping direction follows the reading direction, so in a right-to-left
/// layout the first page sits at the right and swipes mirror.
class PanelPager extends StatefulWidget {
  /// A pager over the pages of [controller].
  ///
  /// It writes the continuous page to [position] and whether it is between
  /// pages to [dragging], for the tabs to follow.
  const PanelPager({
    required this.controller,
    required this.position,
    required this.dragging,
    this.selectSlide = Duration.zero,
    super.key,
  });

  /// How long a selection made elsewhere (a tab) slides the pages, or zero
  /// to jump.
  final Duration selectSlide;

  /// The controller whose selection the pager follows and changes.
  final PanelShellController controller;

  /// Receives the continuous page, in page units.
  final ValueNotifier<double> position;

  /// Receives whether the pager is between two pages.
  final ValueNotifier<bool> dragging;

  @override
  State<PanelPager> createState() => _PanelPagerState();
}

class _PanelPagerState extends State<PanelPager> {
  late final SwipePagerController _pages;

  int _indexOf(String pageId) =>
      widget.controller.pages.indexWhere((page) => page.id == pageId);

  @override
  void initState() {
    super.initState();
    final initial = _indexOf(widget.controller.selectedPageId.value);
    _pages = SwipePagerController(initialPage: initial < 0 ? 0 : initial)
      ..addPositionListener(_onPosition);
    widget.position.value = _pages.position;
    widget.controller.selectedPageId.addListener(_onSelected);
  }

  @override
  void didUpdateWidget(PanelPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.selectedPageId.removeListener(_onSelected);
      widget.controller.selectedPageId.addListener(_onSelected);
      _onSelected();
    }
  }

  @override
  void dispose() {
    widget.controller.selectedPageId.removeListener(_onSelected);
    // The pager under this state is unmounted, and has let the controller
    // go, before this state is disposed.
    _pages
      ..removePositionListener(_onPosition)
      ..dispose();
    super.dispose();
  }

  void _onPosition(double page) {
    widget.position.value = page;
    final between = (page - page.roundToDouble()).abs() > 0.001;
    if (widget.dragging.value != between) widget.dragging.value = between;
  }

  void _onSelected() {
    final index = _indexOf(widget.controller.selectedPageId.value);
    if (index < 0 || index == _pages.page) return;
    final slide = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : ChromeMotionScope.of(context).speed.scale(widget.selectSlide);
    if (slide == Duration.zero) {
      _pages.jumpTo(index);
      return;
    }
    unawaited(
      _pages.animateTo(index, duration: slide, curve: Curves.easeOutCirc),
    );
  }

  void _onPageChanged(int index) {
    final id = widget.controller.pages[index].id;
    // A move we made ourselves also lands here; only a swipe differs.
    if (id != widget.controller.selectedPageId.value) {
      widget.controller.selectPage(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.controller.pages;
    return SwipePager(
      controller: _pages,
      pageCount: pages.length,
      onPageChanged: _onPageChanged,
      pageBuilder: (context, index) {
        final page = pages[index];
        return KeyedSubtree(
          key: ValueKey<String>(page.id),
          child: page.builder(context, widget.controller.hostFor(page.id)),
        );
      },
    );
  }
}

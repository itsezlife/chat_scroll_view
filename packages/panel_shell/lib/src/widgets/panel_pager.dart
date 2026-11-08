import 'dart:async';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_shell/src/controller/panel_shell_controller.dart';

/// The pager: one swipeable page per registered page, kept in step with the
/// shell controller's selection.
///
/// A swipe that settles on another page calls `selectPage`, the same intent a
/// tab tap or a host uses; a selection made any other way moves the pager
/// with a jump (no scroll animation, because the tabs' capsule has its own
/// settle), or, given a [selectSlide], slides there from the neighbouring
/// page over it, as the reference desktop client slides its sections.
///
/// Pages are built lazily and, once built, kept alive for the life of the
/// pager, so at most the registered pages are kept: a type tab switched away
/// from keeps its page, with its cells, their frames and their positions, as
/// the reference mobile client keeps every page of its pager. A page that is
/// not on screen (a page or more from the pager's position) is under
/// `TickerMode(enabled: false)`: its animations hold and a catalogue in it
/// holds its bindings. What a page must restore after the shell itself is
/// rebuilt still lives in the controller's registry.
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
  late PageController _pages;

  int _indexOf(String pageId) =>
      widget.controller.pages.indexWhere((page) => page.id == pageId);

  @override
  void initState() {
    super.initState();
    final initial = _indexOf(widget.controller.selectedPageId.value);
    _pages = PageController(initialPage: initial)..addListener(_onTick);
    widget.position.value = initial.toDouble();
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
    _pages
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  void _onTick() {
    final page = _pages.page;
    if (page == null) return;
    if (page != widget.position.value) widget.position.value = page;
    final between = (page - page.roundToDouble()).abs() > 0.001;
    if (widget.dragging.value != between) widget.dragging.value = between;
  }

  void _onSelected() {
    final index = _indexOf(widget.controller.selectedPageId.value);
    if (index < 0 || !_pages.hasClients) return;
    final current = _pages.page?.round() ?? index;
    if (current == index) return;
    final slide = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : ChromeMotionScope.of(context).speed.scale(widget.selectSlide);
    if (slide == Duration.zero) {
      _pages.jumpToPage(index);
      widget.position.value = index.toDouble();
      widget.dragging.value = false;
      return;
    }
    // From the page next to it, so a far page does not pass over the ones
    // between.
    _sliding = true;
    _pages.jumpToPage(index > current ? index - 1 : index + 1);
    unawaited(
      _pages
          .animateToPage(index, duration: slide, curve: Curves.easeOutCirc)
          .whenComplete(() => _sliding = false),
    );
  }

  // A slide this pager runs passes over pages that are not the selection.
  var _sliding = false;

  void _onPageChanged(int index) {
    if (_sliding) return;
    final id = widget.controller.pages[index].id;
    // A jump we made ourselves also lands here; only a swipe differs.
    if (id != widget.controller.selectedPageId.value) {
      widget.controller.selectPage(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.controller.pages;
    return PageView.builder(
      controller: _pages,
      itemCount: pages.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) {
        final page = pages[index];
        return _KeptPage(
          key: ValueKey<String>(page.id),
          index: index,
          position: widget.position,
          child: page.builder(context, widget.controller.hostFor(page.id)),
        );
      },
    );
  }
}

/// One page of the pager: kept alive once built, and under
/// `TickerMode(enabled: false)` while it is not on screen.
class _KeptPage extends StatefulWidget {
  const _KeptPage({
    required this.index,
    required this.position,
    required this.child,
    super.key,
  });

  final int index;
  final ValueNotifier<double> position;
  final Widget child;

  @override
  State<_KeptPage> createState() => _KeptPageState();
}

class _KeptPageState extends State<_KeptPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Rebuilt on every step of a swipe, but only the bool reaches the
    // subtree, and a TickerMode of the same value notifies nobody.
    return ValueListenableBuilder<double>(
      valueListenable: widget.position,
      child: widget.child,
      builder: (context, position, child) => TickerMode(
        enabled: (widget.index - position).abs() < 1,
        child: child!,
      ),
    );
  }
}

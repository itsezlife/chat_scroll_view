import 'package:flutter/widgets.dart';
import 'package:panel_shell/src/controller/panel_shell_controller.dart';

/// The pager: one swipeable page per registered page, kept in step with the
/// shell controller's selection.
///
/// A swipe that settles on another page calls `selectPage`, the same intent a
/// tab tap or a host uses; a selection made any other way moves the pager
/// with a jump (no scroll animation, because the tabs' capsule has its own
/// settle). Pages are built lazily and dropped when off screen: what a page
/// must keep lives in the controller's registry, not in the pager.
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
    super.key,
  });

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
    if ((_pages.page?.round() ?? index) == index) return;
    _pages.jumpToPage(index);
    widget.position.value = index.toDouble();
    widget.dragging.value = false;
  }

  void _onPageChanged(int index) {
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
        return KeyedSubtree(
          key: ValueKey<String>(page.id),
          child: page.builder(context, widget.controller.hostFor(page.id)),
        );
      },
    );
  }
}

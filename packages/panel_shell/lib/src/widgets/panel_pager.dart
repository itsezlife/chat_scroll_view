import 'dart:async';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_shell/src/controller/panel_shell_controller.dart';
import 'package:panel_shell/src/page/page_availability.dart';
import 'package:panel_shell/src/page/panel_page.dart';
import 'package:panel_shell/src/widgets/listen_value_builder.dart';
import 'package:panel_shell/src/widgets/panel_page_availability_view.dart';
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
/// not on screen is offstage, under `TickerMode(enabled: false)` and under
/// an invisible `Visibility`: its animations hold, and a catalogue in it
/// holds its bindings and gives back the textures their frames are on,
/// keeping the frames. What a page
/// must restore after the shell itself is rebuilt still lives in the
/// controller's registry.
///
/// Swiping direction follows the reading direction, so in a right-to-left
/// layout the first page sits at the right and swipes mirror.
///
/// The pager holds the controller's shown pages: a hidden page has no place
/// in it, and a page that is hidden or comes back moves the others along,
/// each keeping its state. A page's content follows its availability: its
/// own while available, its text while replaced, nothing while dimmed. A
/// swipe onto a dimmed page is refused by the controller and slides back.
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
  late SwipePagerController _pages;
  // The pages the pager was last built with.
  var _count = 0;

  // Keyed by page id across the pager's slots, so a page keeps its state
  // when a page before it is hidden or comes back and it changes index.
  final _keys = <String, GlobalKey>{};

  List<PanelPage> get _shown => widget.controller.shownPages.value;

  int _indexOf(String pageId) => _shown.indexWhere((page) => page.id == pageId);

  @override
  void initState() {
    super.initState();
    final initial = _indexOf(widget.controller.selectedPageId.value);
    _pages = SwipePagerController(initialPage: initial < 0 ? 0 : initial)
      ..addPositionListener(_onPosition);
    widget.position.value = _pages.position;
    widget.controller.selectedPageId.addListener(_onSelected);
    widget.controller.shownPages.addListener(_onShown);
  }

  @override
  void didUpdateWidget(PanelPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.selectedPageId.removeListener(_onSelected);
      oldWidget.controller.shownPages.removeListener(_onShown);
      widget.controller.selectedPageId.addListener(_onSelected);
      widget.controller.shownPages.addListener(_onShown);
      _onSelected();
    }
  }

  @override
  void dispose() {
    widget.controller.selectedPageId.removeListener(_onSelected);
    widget.controller.shownPages.removeListener(_onShown);
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

  // The selected page stays on screen at its new index. An index the pager
  // has now is a jump; one past its count (a page before it came back) is
  // not reachable until the pager has rebuilt with the new count, and a jump
  // after that would show the page now at the old index for a frame, so the
  // pager starts over on a new controller at the right page. Pages kept
  // alive off screen are dropped then and built again when shown; the
  // selected page keeps its state through its key.
  void _onShown() {
    final index = _indexOf(widget.controller.selectedPageId.value);
    if (index >= 0 && index != _pages.page) {
      if (index < _count) {
        _pages.jumpTo(index);
      } else {
        final previous = _pages..removePositionListener(_onPosition);
        _pages = SwipePagerController(initialPage: index)
          ..addPositionListener(_onPosition);
        _onPosition(_pages.position);
        // The pager lets the old controller go on its next build.
        WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
      }
    }
    setState(() {});
  }

  void _onPageChanged(int index) {
    final shown = _shown;
    if (index >= shown.length) return;
    final id = shown[index].id;
    // A move we made ourselves also lands here; only a swipe differs.
    if (id == widget.controller.selectedPageId.value) return;
    widget.controller.selectPage(id);
    // A page the controller refused (dimmed): back to the one selected.
    final selected = _indexOf(widget.controller.selectedPageId.value);
    if (selected >= 0 && selected != _pages.page) {
      unawaited(_pages.animateTo(selected));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = _shown;
    _count = pages.length;
    return SwipePager(
      controller: _pages,
      pageCount: pages.length,
      onPageChanged: _onPageChanged,
      pageBuilder: (context, index) {
        final page = pages[index];
        return KeyedSubtree(
          key: _keys.putIfAbsent(page.id, () => GlobalKey(debugLabel: page.id)),
          child: ListenValueBuilder<PageAvailability>(
            listenable: widget.controller.availabilityOf(page.id),
            builder: (context, availability) => switch (availability) {
              PageAvailability$Available() => page.builder(
                context,
                widget.controller.hostFor(page.id),
              ),
              PageAvailability$Replaced(:final text) => PanelReplacedPage(
                text: text,
              ),
              PageAvailability$Dimmed() ||
              PageAvailability$Hidden() => const SizedBox.expand(),
            },
          ),
        );
      },
    );
  }
}

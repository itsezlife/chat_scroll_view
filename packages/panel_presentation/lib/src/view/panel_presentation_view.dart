import 'package:flutter/widgets.dart';
import 'package:panel_presentation/src/controller/panel_presentation_controller.dart';
import 'package:panel_presentation/src/kind/panel_presentation.dart';
import 'package:panel_presentation/src/kind/panel_visibility.dart';
import 'package:panel_presentation/src/strategy/panel_presentation_strategy.dart';
import 'package:panel_presentation/src/view/listen_value_builder.dart';

/// The mounted presentation: projects the visibility state of a
/// [PanelPresentationController] through the strategy of the active kind.
///
/// It asks the strategy registered for the active kind to build the panel and
/// keys the result by kind, so a switch of kind unmounts one strategy's
/// subtree and mounts the next. That is safe because the page, the query,
/// the focus intent and the pages' scroll offsets live in the shell
/// controller, and the new subtree reads them back. No `GlobalKey` moves a
/// widget between the two.
///
/// ## Hidden
///
/// Hidden, the view keeps the subtree of the last kind it showed: the
/// strategy builds it with [PanelVisibility.hidden], and the view puts it
/// offstage (no paint, no hit test, no semantics) and out of focus, under an
/// invisible [Visibility] that keeps its state: content that asks
/// [Visibility.of] learns that nothing of it is on screen.
/// The tree has one shape shown or hidden, so a hide and a show remount
/// nothing: the shell, its pages and their cells keep their state, and the
/// cells their frames, and its views are kept while it is removed from the
/// window. Before the first show it
/// builds nothing.
///
/// The view fills the box its host gives it; where that box sits, and how
/// the host reserves space for [PanelPresentationController.occupancy], is
/// the host's layout. While mounted it is attached to the controller, which
/// then waits for the strategy to settle `showing` and `hiding`.
class PanelPresentationView extends StatefulWidget {
  /// A view of [controller].
  const PanelPresentationView({required this.controller, super.key});

  /// The controller this view projects.
  final PanelPresentationController controller;

  @override
  State<PanelPresentationView> createState() => _PanelPresentationViewState();
}

class _PanelPresentationViewState extends State<PanelPresentationView> {
  late PanelPresentationAttachment _attachment;
  // The kind last shown: what a hidden view keeps mounted.
  PanelPresentation? _kept;

  @override
  void initState() {
    super.initState();
    _attachment = widget.controller.attach();
  }

  @override
  void didUpdateWidget(PanelPresentationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _attachment.detach();
      _attachment = widget.controller.attach();
      _kept = null;
    }
  }

  @override
  void dispose() {
    _attachment.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenValueBuilder<PanelVisibility>(
    listenable: widget.controller.state,
    builder: (context, visibility) {
      final kind = visibility.kind ?? _kept;
      if (kind == null) return const SizedBox.shrink();
      final strategy = widget.controller.strategyFor(kind);
      assert(
        strategy != null,
        'No PanelPresentationStrategy is registered for $kind.',
      );
      if (strategy == null) return const SizedBox.shrink();
      _kept = kind;
      // Offstage and out of focus while hidden, and [Visibility.of] says
      // so to the content: what plays in it gives back what it plays on for
      // the surfaces on screen, which a panel held on screen while it moves
      // does not. The tickers are the strategy's (off unless shown).
      return Visibility(
        visible: visibility.isVisible,
        maintainState: true,
        maintainAnimation: true,
        child: KeyedSubtree(
          key: ValueKey<String>(kind.name),
          child: strategy.build(
            context,
            PanelStrategyContext(
              controller: widget.controller,
              visibility: visibility,
              onMotionSettled: _attachment.motionSettled,
            ),
          ),
        ),
      );
    },
  );
}

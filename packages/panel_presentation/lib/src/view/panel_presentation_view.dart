import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_presentation/src/controller/panel_presentation_controller.dart';
import 'package:panel_presentation/src/kind/panel_visibility.dart';
import 'package:panel_presentation/src/strategy/panel_presentation_strategy.dart';

/// The mounted presentation: projects the visibility state of a
/// [PanelPresentationController] through the strategy of the active kind.
///
/// Hidden, it builds nothing. Otherwise it asks the strategy registered for
/// the active kind to build the panel and keys the result by kind, so a
/// switch of kind unmounts one strategy's subtree and mounts the next. That
/// is safe because nothing is kept in the subtree: the page, the query, the
/// focus intent and the pages' scroll offsets live in the shell controller,
/// and the new subtree reads them back. No `GlobalKey` moves a widget
/// between the two.
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
    }
  }

  @override
  void dispose() {
    _attachment.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueObservableBuilder<PanelVisibility>(
    observable: widget.controller.state,
    builder: (context, visibility) {
      final kind = visibility.kind;
      if (kind == null) return const SizedBox.shrink();
      final strategy = widget.controller.strategyFor(kind);
      assert(
        strategy != null,
        'No PanelPresentationStrategy is registered for $kind.',
      );
      if (strategy == null) return const SizedBox.shrink();
      return KeyedSubtree(
        key: ValueKey<String>(kind.name),
        child: strategy.build(
          context,
          PanelStrategyContext(
            controller: widget.controller,
            visibility: visibility,
            onMotionSettled: _attachment.motionSettled,
          ),
        ),
      );
    },
  );
}

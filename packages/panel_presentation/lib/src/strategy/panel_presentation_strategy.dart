import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_presentation/src/controller/panel_presentation_controller.dart';
import 'package:panel_presentation/src/kind/panel_occupancy.dart';
import 'package:panel_presentation/src/kind/panel_presentation.dart';
import 'package:panel_presentation/src/kind/panel_visibility.dart';

/// What draws one [PanelPresentation] kind and how much space it takes.
///
/// The policy decides which kind is active; a strategy projects that
/// decision: it builds the panel for the kind it is registered for (placing
/// the `PanelShell` of the controller in a bottom slot, a popup or a docked
/// section) and publishes the [occupancy] the host aggregates. It keeps no
/// panel state of its own: page, query and scroll offsets live in the shell
/// controller, which is what lets a switch of kind restore them.
///
/// A strategy may animate. While the visibility is moving it reports the end
/// of its motion with [PanelStrategyContext.motionSettled]; the controller
/// then moves `showing` to `shown` and `hiding` to `hidden`.
abstract interface class PanelPresentationStrategy {
  /// The kind this strategy draws. Unique among a controller's strategies.
  PanelPresentation get kind;

  /// The space this kind takes now, animated as the strategy sees fit.
  ///
  /// Read even while the panel is hidden: the keyboard strategy keeps
  /// publishing the soft keyboard's own height then, so the host never adds
  /// the keyboard a second time.
  ValueObservable<PanelOccupancy> get occupancy;

  /// Builds the panel for [view.visibility], which is never hidden.
  ///
  /// Called again on every change of the visibility state, with the same
  /// kind; the returned widget keeps its own state across those calls.
  Widget build(BuildContext context, PanelStrategyContext view);
}

/// What a strategy is given to build against.
@immutable
final class PanelStrategyContext {
  /// A context for [controller] in the visibility [visibility].
  const PanelStrategyContext({
    required this.controller,
    required this.visibility,
    required this.onMotionSettled,
  });

  /// The controller being projected. Its `shell` is what to mount.
  final PanelPresentationController controller;

  /// The visibility being projected; never `hidden`.
  final PanelVisibility visibility;

  /// The reporting channel behind [motionSettled].
  final void Function(PanelVisibility settledFor) onMotionSettled;

  /// Reports that the motion toward [visibility] has finished.
  ///
  /// Ignored when the visibility has changed since, so a late report from an
  /// interrupted animation cannot settle a newer state.
  void motionSettled() => onMotionSettled(visibility);
}

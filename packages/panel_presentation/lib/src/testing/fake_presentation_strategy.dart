import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_presentation/panel_presentation.dart';
import 'package:panel_shell/panel_shell.dart';

/// A [PanelPresentationStrategy] for tests: it mounts the controller's
/// `PanelShell` in a box labelled with its kind and publishes whatever
/// occupancy a test sets.
///
/// The shell needs the scopes `PanelShellTestScope` (from
/// `package:panel_shell/testing.dart`) provides.
final class FakePresentationStrategy implements PanelPresentationStrategy {
  /// A strategy drawing [kind], publishing [initialOccupancy] at first.
  ///
  /// With [autoSettle] it reports the end of its motion on the frame after
  /// each moving build, as an instant animation would; otherwise a test
  /// settles it by calling `lastContext.motionSettled()`.
  FakePresentationStrategy(
    this.kind, {
    PanelOccupancy initialOccupancy = PanelOccupancy.zero,
    this.autoSettle = false,
  }) : _occupancy = ObservableValue<PanelOccupancy>(initialOccupancy);

  @override
  final PanelPresentation kind;

  /// Whether to settle every moving build on the next frame.
  final bool autoSettle;

  final ObservableValue<PanelOccupancy> _occupancy;

  /// The context of the latest build, or null before the first.
  PanelStrategyContext? lastContext;

  /// How many times [build] ran.
  int buildCount = 0;

  @override
  ValueObservable<PanelOccupancy> get occupancy => _occupancy;

  /// The occupancy being published; assign to publish another.
  PanelOccupancy get published => _occupancy.value;

  set published(PanelOccupancy occupancy) => _occupancy.value = occupancy;

  /// Releases the occupancy observable.
  void dispose() => _occupancy.dispose();

  @override
  Widget build(BuildContext context, PanelStrategyContext view) {
    lastContext = view;
    buildCount++;
    if (autoSettle && view.visibility.isMoving) {
      WidgetsBinding.instance.addPostFrameCallback((_) => view.motionSettled());
    }
    return KeyedSubtree(
      key: ValueKey<String>('fake-${kind.name}'),
      child: PanelShell(controller: view.controller.shell),
    );
  }
}

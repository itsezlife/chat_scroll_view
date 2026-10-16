import 'package:content_model/content_model.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Rebuilds [builder] with the current value of [observable] each time it
/// signals.
///
/// The one bridge from the model's `ValueObservable` to the widget tree. The
/// model package is pure Dart, so its observables are not `Listenable`s by
/// design; adapting them is a framework-edge job, done here once for every
/// package that draws from them.
///
/// A change can be published from layout (a view reporting its extent). The
/// rebuild then waits for the end of that frame instead of being scheduled
/// from inside it. [observable] stays its owner's: the builder only listens,
/// and stops when it is removed or given another one.
class ValueObservableBuilder<T> extends StatefulWidget {
  /// Builds from [observable] through [builder].
  const ValueObservableBuilder({
    required this.observable,
    required this.builder,
    super.key,
  });

  /// The observed value.
  final ValueObservable<T> observable;

  /// Builds the subtree for the current value.
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<ValueObservableBuilder<T>> createState() =>
      _ValueObservableBuilderState<T>();
}

class _ValueObservableBuilderState<T> extends State<ValueObservableBuilder<T>> {
  @override
  void initState() {
    super.initState();
    widget.observable.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(ValueObservableBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.observable, widget.observable)) {
      oldWidget.observable.removeListener(_onChanged);
      widget.observable.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.observable.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.observable.value);
}

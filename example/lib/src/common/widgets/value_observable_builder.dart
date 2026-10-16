import 'package:content_model/content_model.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Rebuilds [builder] with the current value of [observable] whenever it
/// changes.
///
/// The `content_model` observables are not Flutter `Listenable`s (the model
/// package is pure Dart), so the host adapts them at the widget boundary.
class ValueObservableBuilder<T> extends StatefulWidget {
  /// Builds from [observable].
  const ValueObservableBuilder({
    required this.observable,
    required this.builder,
    super.key,
  });

  /// What to follow. Its owner disposes it.
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
    // A change can be reported from layout (a view publishing its extent):
    // the rebuild waits for the end of that frame instead of being scheduled
    // from inside it.
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

/// An [Observable] seen as a Flutter [Listenable], to merge with the
/// controllers that are one (`Listenable.merge`, `ListenableBuilder`).
final class ObservableListenable implements Listenable {
  /// Adapts [observable].
  const ObservableListenable(this._observable);

  final Observable _observable;

  @override
  void addListener(VoidCallback listener) => _observable.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _observable.removeListener(listener);
}

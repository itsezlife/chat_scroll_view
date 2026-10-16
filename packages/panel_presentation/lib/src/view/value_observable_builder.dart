import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';

/// Rebuilds [builder] with the current value of [observable] each time it
/// signals: the bridge from the model's [Observable] to the widget tree.
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

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.observable.value);
}

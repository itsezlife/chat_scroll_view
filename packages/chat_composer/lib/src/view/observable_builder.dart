import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';

/// Rebuilds [builder] whenever [observable] signals, handing it the current
/// value.
///
/// The framework-edge adapter from a `ValueObservable` to a widget; the
/// observable itself knows no Flutter type.
class ObservableBuilder<T> extends StatefulWidget {
  /// Builds from [observable].
  const ObservableBuilder({
    required this.observable,
    required this.builder,
    super.key,
  });

  /// The source of values.
  final ValueObservable<T> observable;

  /// Builds the subtree for the current value.
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<ObservableBuilder<T>> createState() => _ObservableBuilderState<T>();
}

class _ObservableBuilderState<T> extends State<ObservableBuilder<T>> {
  @override
  void initState() {
    super.initState();
    widget.observable.addListener(_changed);
  }

  @override
  void didUpdateWidget(ObservableBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.observable, widget.observable)) {
      oldWidget.observable.removeListener(_changed);
      widget.observable.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.observable.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.observable.value);
}

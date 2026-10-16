import 'package:flutter/widgets.dart';
import 'package:listen/listen.dart' as listen;

/// Rebuilds [builder] with the current value of [listenable] each time it
/// signals: the bridge from `package:listen`'s `ValueListenable` to the widget
/// tree (Flutter's own `ValueListenableBuilder` takes the framework's type of
/// that name, which is a different type).
class ListenValueBuilder<T> extends StatefulWidget {
  /// Builds from [listenable] through [builder].
  const ListenValueBuilder({
    required this.listenable,
    required this.builder,
    super.key,
  });

  /// The observed value.
  final listen.ValueListenable<T> listenable;

  /// Builds the subtree for the current value.
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<ListenValueBuilder<T>> createState() => _ListenValueBuilderState<T>();
}

class _ListenValueBuilderState<T> extends State<ListenValueBuilder<T>> {
  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(ListenValueBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.listenable, widget.listenable)) {
      oldWidget.listenable.removeListener(_onChanged);
      widget.listenable.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.listenable.value);
}

import 'package:flutter/widgets.dart';
import 'package:listen/listen.dart' as listen;

/// Rebuilds [builder] whenever [listenable] signals, handing it the current
/// value.
///
/// The framework-edge adapter from `package:listen`'s `ValueListenable` to a
/// widget (Flutter's own `ValueListenableBuilder` takes the framework's type
/// of that name, which is a different type).
class ListenValueBuilder<T> extends StatefulWidget {
  /// Builds from [listenable].
  const ListenValueBuilder({
    required this.listenable,
    required this.builder,
    super.key,
  });

  /// The source of values.
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
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(ListenValueBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.listenable, widget.listenable)) {
      oldWidget.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.listenable.value);
}

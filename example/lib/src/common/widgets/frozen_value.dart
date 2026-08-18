import 'package:flutter/widgets.dart';

/// Builds a widget from a possibly frozen [value].
typedef FrozenValueWidgetBuilder<T> =
    Widget Function(BuildContext context, T value);

/// Presents the last [value] seen while [frozen] was `false`.
///
/// When [frozen] becomes `true`, later [value] updates are ignored until it
/// is unfrozen. Use this to keep outgoing chrome (a selection count, action
/// buttons) visually stable while a reverse animation plays after the live
/// source has already reset — e.g. selection `1 → 0`.
///
/// ```dart
/// FrozenValue<int>(
///   frozen: !selection.isSelectionMode,
///   value: selection.count,
///   builder: (context, count) => Text('$count'),
/// )
/// ```
class FrozenValue<T> extends StatefulWidget {
  /// Holds [value] while [frozen] and rebuilds via [builder].
  const FrozenValue({
    required this.frozen,
    required this.value,
    required this.builder,
    super.key,
  });

  /// When `true`, [builder] keeps receiving the last unfrozen [value].
  final bool frozen;

  /// Live value. Applied only while [frozen] is `false`.
  final T value;

  /// Builds the child from the held or live [value].
  final FrozenValueWidgetBuilder<T> builder;

  @override
  State<FrozenValue<T>> createState() => _FrozenValueState<T>();
}

class _FrozenValueState<T> extends State<FrozenValue<T>> {
  late T _held;

  @override
  void initState() {
    super.initState();
    _held = widget.value;
  }

  @override
  void didUpdateWidget(FrozenValue<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.frozen) _held = widget.value;
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _held);
}

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:listen/listen.dart' as listen;

/// Rebuilds [builder] with the current value of [listenable] whenever it
/// changes.
///
/// `package:listen`'s `ValueListenable` is not Flutter's type of that name
/// (the model packages are pure Dart), so the host adapts it at the widget
/// boundary. A change reported from layout waits for the end of the frame.
class ListenValueBuilder<T> extends StatefulWidget {
  /// Builds from [listenable].
  const ListenValueBuilder({
    required this.listenable,
    required this.builder,
    super.key,
  });

  /// What to follow. Its owner disposes it.
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
      widget.builder(context, widget.listenable.value);
}

/// A `package:listen` [listen.Listenable] seen as a Flutter [Listenable], to
/// merge with the controllers that are one (`Listenable.merge`,
/// `ListenableBuilder`).
final class ListenableBridge implements Listenable {
  /// Adapts [listenable].
  const ListenableBridge(this._listenable);

  final listen.Listenable _listenable;

  @override
  void addListener(VoidCallback listener) => _listenable.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _listenable.removeListener(listener);
}

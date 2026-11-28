import 'package:flutter/widgets.dart';

/// Whether the row below is still appearing: its time pill holds back the
/// status motion the platform suppresses meanwhile.
class DemoRowEntering extends InheritedWidget {
  /// Marks the row of [child] as [entering] or not.
  const DemoRowEntering({
    required this.entering,
    required super.child,
    super.key,
  });

  /// Whether the row is appearing.
  final bool entering;

  /// Whether the row of [context] is appearing; false outside any row.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DemoRowEntering>()?.entering ??
      false;

  @override
  bool updateShouldNotify(DemoRowEntering oldWidget) =>
      entering != oldWidget.entering;
}

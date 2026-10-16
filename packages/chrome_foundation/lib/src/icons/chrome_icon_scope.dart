import 'package:chrome_foundation/src/icons/chrome_icon_id.dart';
import 'package:chrome_foundation/src/icons/chrome_icon_painter.dart';
import 'package:chrome_foundation/src/icons/chrome_icon_registry.dart';
import 'package:flutter/widgets.dart';

/// The **chrome icon scope**: supplies the icon registry to the subtree.
///
/// Optional: with no scope, widgets see [ChromeIconRegistry.stock]. A scope
/// adds [icons] to the registry of the enclosing scope, so an inner scope
/// registers more ids or replaces a few without repeating the rest.
class ChromeIconScope extends StatelessWidget {
  /// A scope adding [icons] to the enclosing registry.
  const ChromeIconScope({required this.icons, required this.child, super.key});

  /// The painters to register, by id.
  final Map<ChromeIconId, ChromeIconPainter> icons;

  /// The subtree that sees the extended registry.
  final Widget child;

  /// The registry at [context]; depends on the nearest scope.
  static ChromeIconRegistry of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_ChromeIconInherited>()
          ?.registry ??
      ChromeIconRegistry.stock;

  @override
  Widget build(BuildContext context) => _ChromeIconInherited(
    registry: of(context).withPainters(icons),
    child: child,
  );
}

class _ChromeIconInherited extends InheritedWidget {
  const _ChromeIconInherited({required this.registry, required super.child});

  final ChromeIconRegistry registry;

  @override
  bool updateShouldNotify(_ChromeIconInherited oldWidget) =>
      registry != oldWidget.registry;
}

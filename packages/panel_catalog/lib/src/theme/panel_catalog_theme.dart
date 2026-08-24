import 'package:flutter/widgets.dart';
import 'package:panel_catalog/src/theme/panel_catalog_theme_data.dart';

export 'panel_catalog_theme_data.dart';

/// Inherited scope for [PanelCatalogThemeData] above a catalog subtree.
///
/// Mount above [PanelCatalogViewport] (or the whole panel shell) so paint
/// tokens resolve through [of]. Package-owned inherited theme — independent
/// of Material [ThemeData].
///
/// ```dart
/// PanelCatalogTheme(
///   data: PanelCatalogThemeData.dark,
///   child: PanelCatalogViewport(/* … */),
/// )
/// ```
///
/// ## Brightness transitions
///
/// To animate palette changes, rebuild this widget with
/// `data: PanelCatalogThemeData.lerp(start, end, t)` each frame instead of
/// swapping [PanelCatalogThemeData.light] / [dark] abruptly.
class PanelCatalogTheme extends InheritedWidget {
  /// Provides [data] to descendants.
  const PanelCatalogTheme({
    required this.data,
    required super.child,
    super.key,
  });

  /// Active catalog paint tokens for this subtree.
  final PanelCatalogThemeData data;

  /// Nearest [PanelCatalogThemeData] for [context].
  ///
  /// Registers a dependency — subtree rebuilds when [data] changes. Falls
  /// back to [PanelCatalogThemeData.light] when no ancestor is mounted.
  static PanelCatalogThemeData of(BuildContext context) {
    final scoped =
        context.dependOnInheritedWidgetOfExactType<PanelCatalogTheme>();
    return scoped?.data ?? PanelCatalogThemeData.light;
  }

  /// Optional lookup without registering a dependency.
  static PanelCatalogThemeData? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PanelCatalogTheme>()?.data;

  @override
  bool updateShouldNotify(PanelCatalogTheme oldWidget) =>
      oldWidget.data != data;
}

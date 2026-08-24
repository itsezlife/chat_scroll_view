import 'package:flutter/widgets.dart';
import 'package:panel_catalog/src/theme/panel_catalog_theme_data.dart';

export 'panel_catalog_theme_data.dart';

/// Inherited scope for [PanelCatalogThemeData] above a catalog subtree.
class PanelCatalogTheme extends InheritedWidget {
  /// Provides [data] to descendants.
  const PanelCatalogTheme({
    required this.data,
    required super.child,
    super.key,
  });

  /// Active catalog paint tokens for this subtree.
  final PanelCatalogThemeData data;

  /// Looks up the nearest [PanelCatalogThemeData], or `null`.
  static PanelCatalogThemeData? maybeOf(
    BuildContext context, {
    bool listen = false,
  }) {
    final inherited = listen
        ? context.dependOnInheritedWidgetOfExactType<PanelCatalogTheme>()
        : context.getInheritedWidgetOfExactType<PanelCatalogTheme>();
    return inherited?.data;
  }

  /// Looks up the nearest [PanelCatalogThemeData].
  static PanelCatalogThemeData of(
    BuildContext context, {
    bool listen = false,
  }) => maybeOf(context, listen: listen) ?? _notFound();

  static Never _notFound() => throw ArgumentError(
    'PanelCatalogTheme not found in context. '
    'Mount PanelCatalogTheme above this call site.',
  );

  @override
  bool updateShouldNotify(PanelCatalogTheme oldWidget) =>
      oldWidget.data != data;
}

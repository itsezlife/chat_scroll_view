import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_shell/panel_shell.dart';

/// Scopes the catalogue's paint tokens, mapped from the chrome theme above, for
/// the viewport below.
///
/// `panel_catalog` takes a small theme of its own and depends on no chrome
/// package; this is the one place that knows both. The mapping changes
/// colours only. Geometry, timing and text metrics stay the viewport's
/// ([PanelCatalogThemeData.forBrightness] is the base), so a page never forks
/// them.
///
/// Requires a [ChromeThemeScope] above. A [CatalogPage] mounts this itself;
/// mount it directly only for a viewport used outside a page.
class ChromeCatalogTheme extends StatelessWidget {
  /// Provides the mapped theme to [child].
  const ChromeCatalogTheme({required this.child, super.key});

  /// The subtree that reads the theme.
  final Widget child;

  /// The wash of a hovered or focused item on a card, in [palette]: the text
  /// colour at alpha `0x12`. The one recipe the cell hover, the variant
  /// picker and the context menu share.
  static Color hoverWashOf(ChromePalette palette) =>
      palette.onSurface.withAlpha(0x12);

  /// The catalogue theme the chrome theme [chrome] stands for.
  ///
  /// - Every stand-in (circle, thumbnail silhouette, sticker wash) and the
  ///   skeleton take the placeholder tokens' `skeleton` colour.
  /// - The wash highlight and the press highlight are the palette's text
  ///   colour at fixed low alpha, the same recipe the viewport's own light
  ///   and dark themes use.
  /// - Keyboard focus is drawn in the accent.
  /// - The section title is the panel tokens' `sectionTitle`.
  /// - Under [PanelArrangement.pointer] a mouse over a cell paints the text
  ///   colour at alpha `0x12`; under touch nothing hovers.
  static PanelCatalogThemeData dataFor(
    ChromeThemeData chrome, {
    PanelArrangement arrangement = PanelArrangement.touch,
  }) {
    final palette = chrome.palette;
    final base = PanelCatalogThemeData.forBrightness(palette.brightness);
    final skeleton = chrome.placeholder.skeleton;
    return base.copyWith(
      circleColor: skeleton,
      thumbColor: skeleton,
      washColor: skeleton,
      washHighlightColor: palette.onSurface.withAlpha(0x24),
      skeletonColor: skeleton,
      leafPressHighlightColor: palette.onSurface.withAlpha(0x0F),
      leafFocusHighlightColor: palette.accent.withAlpha(0x40),
      leafHoverHighlightColor: switch (arrangement) {
        PanelArrangement.pointer => hoverWashOf(palette),
        PanelArrangement.touch => null,
      },
      sectionHeaderStyle: base.sectionHeaderStyle.copyWith(
        color: chrome.panel.sectionTitle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PanelCatalogTheme(
    data: dataFor(
      ChromeThemeScope.of(context),
      arrangement: PanelArrangementScope.of(context),
    ),
    child: child,
  );
}

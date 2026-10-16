import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';

/// One row of colour cells per token group, derived from [palette].
///
/// Cells are solid rectangles on whole logical pixels with no text, so the
/// rendering does not depend on fonts or anti-aliasing and is byte-stable
/// across platforms. Translucent colours are drawn over the palette's panel
/// surface, which is what they sit on in the chrome.
class PaletteSwatch extends StatelessWidget {
  const PaletteSwatch(this.palette, {super.key});

  final ChromePalette palette;

  static const double cell = 20;

  @override
  Widget build(BuildContext context) {
    final data = ChromeThemeData.fromPalette(palette);
    final rows = <List<Color>>[
      [
        palette.surface,
        palette.surfaceDim,
        palette.surfaceRaised,
        palette.surfaceSelected,
        palette.surfaceTint,
        palette.onSurface,
        palette.onSurfaceMuted,
        palette.iconIdle,
        palette.iconActive,
        palette.accent,
        palette.onAccent,
        palette.separator,
        palette.destructive,
        palette.contentFade,
        palette.shadow,
      ],
      [
        data.composer.background,
        data.composer.text,
        data.composer.cursor,
        data.composer.shadow,
        data.composer.replyLine,
        data.composer.replyName,
        data.composer.replyText,
        data.composer.contentFade,
      ],
      [
        data.panel.background,
        data.panel.categoryIcon,
        data.panel.categoryIconSelected,
        data.panel.hairline,
        data.panel.tabSelector,
        data.panel.tabSelectorLine,
        data.panel.sectionTitle,
        data.panel.searchFill,
        data.panel.searchIcon,
        data.panel.searchText,
      ],
      [
        data.action.icon,
        data.action.send,
        data.action.onSend,
        data.action.backspace,
        data.action.floatingFill,
        data.action.floatingSelectedFill,
        data.action.floatingLabel,
        data.action.floatingLabelMuted,
      ],
      [
        data.placeholder.emptyState,
        data.placeholder.fieldHint,
        data.placeholder.skeleton,
      ],
      [
        for (final m in [
          data.glass.composerIsland,
          data.glass.panelButton,
          data.glass.topPanel,
        ]) ...[m.fill, m.strokeTop, m.strokeBottom, m.shadow],
      ],
    ];
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: palette.surfaceDim,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final color in row)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: SizedBox.square(
                            dimension: cell,
                            child: ColoredBox(color: color),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

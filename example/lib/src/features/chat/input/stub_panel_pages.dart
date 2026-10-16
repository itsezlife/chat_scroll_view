import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_shell/panel_shell.dart';

/// The GIF and sticker pages of the panel while the demo has no content for
/// them: a short note in the middle of the page, so the type tabs, the
/// composer's toggle icon and the page switch are real and only the content is
/// not.
///
/// Both pages declare nothing (no search, no strip, no actions): the shell
/// shows a bottom bar with the tabs alone over them.
abstract final class StubPanelPages {
  /// Id of the GIF page.
  static const String gifId = 'gif';

  /// Id of the sticker page.
  static const String stickersId = 'stickers';

  /// The GIF page.
  static PanelPage gif() => _stub(
    id: gifId,
    icon: ChromeIconId.gif,
    title: 'No GIFs yet',
    note: 'GIF search and trending will appear here when available.',
  );

  /// The sticker page.
  static PanelPage stickers() => _stub(
    id: stickersId,
    icon: ChromeIconId.stickers,
    title: 'No stickers yet',
    note: 'Sticker packs will appear here when available.',
  );

  static PanelPage _stub({
    required String id,
    required ChromeIconId icon,
    required String title,
    required String note,
  }) => PanelPage(
    id: id,
    tab: PanelTab(icon: icon, labelKey: id),
    builder: (context, host) => _StubBody(icon: icon, title: title, note: note),
  );
}

class _StubBody extends StatelessWidget {
  const _StubBody({
    required this.icon,
    required this.title,
    required this.note,
  });

  final ChromeIconId icon;
  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    final panel = ChromeThemeScope.panelOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChromeIcon(icon, size: 56, color: panel.categoryIcon),
            const SizedBox(height: 12),
            Text(
              title,
              textDirection: Directionality.of(context),
              style: TextStyle(
                color: panel.categoryIconSelected,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              note,
              textAlign: TextAlign.center,
              textDirection: Directionality.of(context),
              style: TextStyle(color: panel.categoryIcon, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

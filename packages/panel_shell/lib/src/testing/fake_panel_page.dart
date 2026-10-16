import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_shell/src/controller/panel_search_state.dart';
import 'package:panel_shell/src/page/panel_page.dart';
import 'package:panel_shell/src/page/panel_page_host.dart';

/// A page for shell tests: a coloured box that shows its own id and, while
/// search is open, the query, and that remembers the host it was built with.
///
/// [page] is the registry entry to hand to a `PanelShellController`; [host]
/// is the connection the page was last built against, so a test can drive the
/// page the way a real one would (`host.pick`, `host.reportScrollActivity`).
final class FakePanelPage {
  /// A fake page named [id].
  ///
  /// [labelKey] defaults to [id], and [icon] to a stock icon id.
  FakePanelPage(
    this.id, {
    String? labelKey,
    ChromeIconId? icon,
    bool search = false,
    bool topStrip = false,
    List<PageAction> actions = const [],
    Color color = const Color(0xFF808080),
  }) {
    page = PanelPage(
      id: id,
      tab: PanelTab(icon: icon ?? ChromeIconId.emoji, labelKey: labelKey ?? id),
      capabilities: PageCapabilities(
        search: search,
        topStrip: topStrip,
        actions: actions,
      ),
      builder: (context, host) {
        this.host = host;
        buildCount++;
        return _FakePageBody(id: id, host: host, color: color);
      },
    );
  }

  /// The page id.
  final String id;

  /// The registry entry.
  late final PanelPage page;

  /// The host the page was last built with, or null before its first build.
  PanelPageHost? host;

  /// How many times the page's builder ran.
  int buildCount = 0;
}

class _FakePageBody extends StatelessWidget {
  const _FakePageBody({
    required this.id,
    required this.host,
    required this.color,
  });

  final String id;
  final PanelPageHost host;
  final Color color;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: color,
    child: Center(
      child: ValueObservableBuilder<PanelSearchState>(
        observable: host.search,
        builder: (context, search) => Text(
          search.isOpen ? 'page $id: ${search.query}' : 'page $id',
          textDirection: Directionality.of(context),
          style: TextStyle(
            color: ChromeThemeScope.paletteOf(context).onSurface,
          ),
        ),
      ),
    ),
  );
}

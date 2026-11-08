import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_shell/src/controller/panel_search_state.dart';
import 'package:panel_shell/src/page/panel_page.dart';
import 'package:panel_shell/src/page/panel_page_host.dart';
import 'package:panel_shell/src/widgets/listen_value_builder.dart';
import 'package:panel_shell/src/widgets/panel_search_field.dart';

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
    SearchPlacement searchPlacement = SearchPlacement.pinned,
    bool topStrip = false,
    List<PageAction> actions = const [],
    Color color = const Color(0xFF808080),
  }) {
    page = PanelPage(
      id: id,
      tab: PanelTab(icon: icon ?? ChromeIconId.emoji, labelKey: labelKey ?? id),
      capabilities: PageCapabilities(
        search: search,
        searchPlacement: searchPlacement,
        topStrip: topStrip,
        actions: actions,
      ),
      builder: (context, host) {
        this.host = host;
        buildCount++;
        final body = _FakePageBody(
          id: id,
          host: host,
          color: color,
          owner: this,
        );
        if (searchPlacement != SearchPlacement.inline) return body;
        // An inline page places the shell's field among its own content.
        return Column(
          children: [
            const PanelSearchField(),
            Expanded(child: body),
          ],
        );
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

  /// How many times the page's body was mounted, and disposed: a page kept
  /// alive across a switch is mounted once.
  int mounts = 0;

  /// How many times the page's body was disposed.
  int disposals = 0;

  /// Whether the body's tickers were on at its last build (`TickerMode`),
  /// null before one.
  bool? tickersEnabled;
}

class _FakePageBody extends StatefulWidget {
  const _FakePageBody({
    required this.id,
    required this.host,
    required this.color,
    required this.owner,
  });

  final String id;
  final PanelPageHost host;
  final Color color;
  final FakePanelPage owner;

  @override
  State<_FakePageBody> createState() => _FakePageBodyState();
}

class _FakePageBodyState extends State<_FakePageBody> {
  String get id => widget.id;
  PanelPageHost get host => widget.host;
  Color get color => widget.color;

  @override
  void initState() {
    super.initState();
    widget.owner.mounts++;
  }

  @override
  void dispose() {
    widget.owner.disposals++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.owner.tickersEnabled = TickerMode.valuesOf(context).enabled;
    return _body(context);
  }

  Widget _body(BuildContext context) => ColoredBox(
    color: color,
    child: Center(
      child: ListenValueBuilder<PanelSearchState>(
        listenable: host.search,
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

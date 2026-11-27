import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_shell/src/page/page_availability.dart';

/// The pages' availability as the tabs below the shell draw it, and the
/// anchor of each tab's hint.
///
/// The shell puts it above its column; a tab reads its page's form here
/// rather than through every widget between, and only the tabs depend on
/// it, so a change rebuilds them and nothing else.
class PanelTabAvailabilityScope extends InheritedWidget {
  /// The [availability] of every page, with [links] anchoring their hints.
  const PanelTabAvailabilityScope({
    required this.availability,
    required this.links,
    required super.child,
    super.key,
  });

  /// The availability of each page, by id.
  final Map<String, PageAvailability> availability;

  /// The link a tab's hint follows, by page id.
  final PanelTabLinks links;

  /// How faint a dimmed tab is drawn.
  static const double dimmedOpacity = 0.15;

  /// The scope above [context], or null outside a shell.
  static PanelTabAvailabilityScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PanelTabAvailabilityScope>();

  @override
  bool updateShouldNotify(PanelTabAvailabilityScope oldWidget) =>
      !identical(availability, oldWidget.availability) ||
      !identical(links, oldWidget.links);
}

/// One [LayerLink] per page id, made on first use and kept for the shell's
/// life: a tab is the target, the hint the follower.
final class PanelTabLinks {
  final _links = <String, LayerLink>{};

  /// The link of page [pageId]'s tab.
  LayerLink of(String pageId) => _links.putIfAbsent(pageId, LayerLink.new);
}

/// A tab of [pageId] as its availability draws it: faint and spoken as not
/// available while dimmed, with the hint as its spoken hint, and the anchor
/// of that hint.
///
/// [tabBuilder] gets the semantic label and hint to put on the tab; its
/// result is wrapped in the faint opacity and the anchor. Outside a shell's
/// scope the tab is drawn as available.
class PanelTabAvailability extends StatelessWidget {
  /// The availability of the tab of [pageId], named [label].
  const PanelTabAvailability({
    required this.pageId,
    required this.label,
    required this.tabBuilder,
    super.key,
  });

  /// The tab's page.
  final String pageId;

  /// The tab's name.
  final String label;

  /// Builds the tab with its spoken label and hint.
  final Widget Function(BuildContext context, String label, String? hint)
  tabBuilder;

  @override
  Widget build(BuildContext context) {
    final scope = PanelTabAvailabilityScope.maybeOf(context);
    if (scope == null) return tabBuilder(context, label, null);
    final availability =
        scope.availability[pageId] ?? const PageAvailability.available();
    final (spoken, hint, opacity) = switch (availability) {
      PageAvailability$Dimmed(:final hint) => (
        ChromeStringsScope.panelOf(context).unavailableTab(label),
        hint,
        PanelTabAvailabilityScope.dimmedOpacity,
      ),
      _ => (label, null, 1.0),
    };
    return CompositedTransformTarget(
      link: scope.links.of(pageId),
      child: Opacity(
        opacity: opacity,
        child: tabBuilder(context, spoken, hint),
      ),
    );
  }
}

/// The hint at a dimmed tab: a tooltip box with the page's hint text, above
/// the tab when the tabs are at the bottom and below it when [below].
///
/// Follows the tab's [link], so it needs no overlay: the shell paints it
/// over its column, after the tabs. It takes no pointer and is announced
/// as a live region. Its own text root sets the chrome text style.
class PanelTabHint extends StatelessWidget {
  /// The [text] at the tab of [link].
  const PanelTabHint({
    required this.link,
    required this.text,
    this.below = false,
    super.key,
  });

  /// The tab's link.
  final LayerLink link;

  /// What the hint says.
  final String text;

  /// Whether the hint hangs below the tab (tabs at the top).
  final bool below;

  /// Space between the tab and the hint.
  static const double gap = 6;

  @override
  Widget build(BuildContext context) => CompositedTransformFollower(
    link: link,
    showWhenUnlinked: false,
    targetAnchor: below ? Alignment.bottomCenter : Alignment.topCenter,
    followerAnchor: below ? Alignment.topCenter : Alignment.bottomCenter,
    offset: Offset(0, below ? gap : -gap),
    child: ChromeTooltip(
      text: text,
      metrics: ChromeTooltipMetrics.hint,
      liveRegion: true,
    ),
  );
}

/// The content of a page whose availability is replaced: its text, centred,
/// as a plain text node; nothing for a null text.
class PanelReplacedPage extends StatelessWidget {
  /// A page showing [text].
  const PanelReplacedPage({required this.text, super.key});

  /// What the page shows in place of its content.
  final String? text;

  /// Space around the text.
  static const double padding = 24;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.of(context).palette;
    return switch (text) {
      final text? => Center(
        child: Padding(
          padding: const EdgeInsets.all(padding),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: ChromeTypography.of(
              context,
            ).copyWith(color: palette.onSurfaceMuted, fontSize: 15),
          ),
        ),
      ),
      null => const SizedBox.expand(),
    };
  }
}

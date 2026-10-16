import 'dart:async';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/src/emoji/emoji_categories.dart';
import 'package:panel_pages/src/page/catalog_strip.dart';

/// The category strip of the emoji page: one tab per category, the active one
/// following the catalogue, a tap landing on the category.
///
/// ## Landing rules
///
/// - A tab shows when the page holds a section of its category (the recents
///   tab only while the recents show). A strip with fewer than two tabs
///   navigates nothing and is not drawn.
/// - Tapping a tab scrolls to the **first** section of its category the page
///   shows. The tab is active at once, and stays active until the jump ends:
///   the catalogue's own scroll is ignored while the strip drives it, and a
///   tap while a jump runs is ignored, so the highlight and the motion cannot
///   disagree.
/// - Otherwise the active tab is the one of the section the user is in
///   (`PanelCatalogCurrentSectionChanged`), also after a jump ends, where the
///   viewport's own answer decides (the last category is active at the end of
///   the content even if it is too short to reach the top).
///
/// The strip is the page's own widget: its whole connection is the
/// [CatalogStripHandle]. It requires the chrome theme and strings scopes.
class EmojiCategoryStrip extends StatefulWidget {
  /// A strip over the sections of [handle].
  const EmojiCategoryStrip({required this.handle, super.key});

  /// What the page gives its strip.
  final CatalogStripHandle handle;

  /// Height of the strip.
  static const double height = 36;

  /// Side of a tab's touch area.
  static const double cell = 30;

  /// Side of a tab's picture.
  static const double iconSize = 24;

  /// Gap between tabs.
  static const double gap = 3;

  /// Horizontal inset of the first tab.
  static const double padH = 11;

  @override
  State<EmojiCategoryStrip> createState() => _EmojiCategoryStripState();
}

class _EmojiCategoryStripState extends State<EmojiCategoryStrip> {
  final _scroll = ScrollController();
  var _tabs = const <_StripTab>[];
  EmojiCategoryTab? _active;
  var _jumping = false;

  CatalogStripHandle get _handle => widget.handle;

  @override
  void initState() {
    super.initState();
    _tabs = _tabsOf(_handle.entries.value);
    _active = _tabOfSection(_handle.currentSectionId) ?? _tabs.firstOrNull?.tab;
    _handle.entries.addListener(_onEntries);
    _handle.scrollEvents.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(EmojiCategoryStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.handle, widget.handle)) return;
    oldWidget.handle.entries.removeListener(_onEntries);
    oldWidget.handle.scrollEvents.removeListener(_onScroll);
    _handle.entries.addListener(_onEntries);
    _handle.scrollEvents.addListener(_onScroll);
    _onEntries();
  }

  @override
  void dispose() {
    _handle.entries.removeListener(_onEntries);
    _handle.scrollEvents.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  // --- Following the catalogue ----------------------------------------------

  void _onEntries() {
    setState(() {
      _tabs = _tabsOf(_handle.entries.value);
      if (!_jumping) {
        _active =
            _tabOfSection(_handle.currentSectionId) ?? _tabs.firstOrNull?.tab;
      }
    });
  }

  void _onScroll(PanelCatalogScrollEvent event) {
    if (event is! PanelCatalogCurrentSectionChanged || _jumping) return;
    _select(_tabOfSection(event.sectionId));
  }

  void _select(EmojiCategoryTab? tab) {
    if (tab == null || tab == _active) return;
    setState(() => _active = tab);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealActive());
  }

  EmojiCategoryTab? _tabOfSection(String? sectionId) {
    if (sectionId == null) return null;
    for (final tab in _tabs) {
      if (tab.sectionIds.contains(sectionId)) return tab.tab;
    }
    return null;
  }

  static List<_StripTab> _tabsOf(List<CatalogStripEntry> entries) => [
    for (final tab in EmojiCategories.tabs) ?_StripTab.of(tab, entries),
  ];

  // --- Landing --------------------------------------------------------------

  Future<void> _onTap(_StripTab tab) async {
    if (_jumping) return;
    setState(() {
      _active = tab.tab;
      _jumping = true;
    });
    try {
      await _handle.jumpToSection(tab.sectionIds.first);
    } finally {
      if (mounted) {
        setState(() {
          _jumping = false;
          _active = _tabOfSection(_handle.currentSectionId) ?? tab.tab;
        });
      }
    }
  }

  void _revealActive() {
    if (!mounted || !_scroll.hasClients) return;
    final index = _tabs.indexWhere((tab) => tab.tab == _active);
    if (index < 0) return;
    const step = EmojiCategoryStrip.cell + EmojiCategoryStrip.gap;
    final start = EmojiCategoryStrip.padH + index * step;
    final end = start + EmojiCategoryStrip.cell;
    final view = _scroll.position.viewportDimension;
    final offset = _scroll.offset;
    if (start < offset) {
      unawaited(
        _scroll.animateTo(
          start - EmojiCategoryStrip.padH,
          duration: const Duration(milliseconds: 200),
          curve: Curves.decelerate,
        ),
      );
    } else if (end > offset + view) {
      unawaited(
        _scroll.animateTo(
          end - view + EmojiCategoryStrip.padH,
          duration: const Duration(milliseconds: 200),
          curve: Curves.decelerate,
        ),
      );
    }
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_tabs.length < 2) return const SizedBox.shrink();
    final panel = ChromeThemeScope.panelOf(context);
    final strings = ChromeStringsScope.of(context);
    final motion = ChromeMotionScope.of(context);
    return Semantics(
      container: true,
      label: strings.semantics.categoryStripLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: panel.background,
          border: Border(bottom: BorderSide(color: panel.hairline, width: 0.5)),
        ),
        child: SizedBox(
          height: EmojiCategoryStrip.height,
          width: double.infinity,
          child: ListView.separated(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: EmojiCategoryStrip.padH,
              vertical: 3,
            ),
            itemCount: _tabs.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: EmojiCategoryStrip.gap),
            itemBuilder: (context, index) {
              final tab = _tabs[index];
              return _TabButton(
                tab: tab.tab,
                label: tab.tab.titleGroup == null
                    ? strings.panel.recentlyUsedTitle
                    : strings.panel.categoryTitle(tab.tab.titleGroup!),
                selected: tab.tab == _active,
                tokens: panel,
                duration: motion.durationOf(MotionRole.fade),
                onTap: () => unawaited(_onTap(tab)),
              );
            },
          ),
        ),
      ),
    );
  }
}

// A tab with the sections of the page it covers, in display order.
class _StripTab {
  const _StripTab(this.tab, this.sectionIds);

  final EmojiCategoryTab tab;
  final List<String> sectionIds;

  static _StripTab? of(EmojiCategoryTab tab, List<CatalogStripEntry> entries) {
    final ids = [
      for (final entry in entries)
        if (tab.covers(entry.collection.id)) entry.sectionId,
    ];
    return ids.isEmpty ? null : _StripTab(tab, ids);
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.label,
    required this.selected,
    required this.tokens,
    required this.duration,
    required this.onTap,
  });

  final EmojiCategoryTab tab;
  final String label;
  final bool selected;
  final PanelTokens tokens;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    onTap: onTap,
    child: ExcludeSemantics(
      child: FocusableActionDetector(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: EmojiCategoryStrip.cell,
            height: EmojiCategoryStrip.cell,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: selected ? 1 : 0),
              duration: duration,
              curve: Curves.decelerate,
              builder: (context, t, _) => DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Alpha on the fill: no saveLayer.
                  color: tokens.tabSelector.withValues(
                    alpha: tokens.tabSelector.a * t,
                  ),
                ),
                child: Center(
                  child: ChromeIcon(
                    tab.icon,
                    size: EmojiCategoryStrip.iconSize,
                    color: Color.lerp(
                      tokens.categoryIcon,
                      tokens.categoryIconSelected,
                      t,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

import 'dart:async';
import 'dart:math' as math;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/src/emoji/emoji_categories.dart';
import 'package:panel_pages/src/page/catalog_strip.dart';
import 'package:panel_shell/panel_shell.dart';

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
/// - After the jump the tapped tab stays active until the user scrolls into
///   another section, even where the catalogue could not bring the header to
///   the top because the content ends first (a category within the last
///   screenful is reached, and the end of the content is in the last
///   category): the tap is the user's own word.
/// - Otherwise the active tab is the one of the section the user is in
///   (`PanelCatalogCurrentSectionChanged`).
///
/// ## Arrangements
///
/// Under the touch arrangement the strip is a row of round tabs above the
/// catalogue, scrolling sideways when they do not fit. Under the pointer
/// arrangement it is pinned below the catalogue: a 1 px separator over
/// [height] px of icons on [PanelTokens.stripFill], the icons spread over the
/// width (scrolling only when each would get less than a tab's room), the
/// active category marked by a [highlightSize] square that **slides** to the
/// next icon over the `selectionSlide` motion role (and is simply there on the
/// first selection, or when animations are off), no paint on hover, and the
/// click cursor over an icon.
///
/// The strip is the page's own widget: its whole connection is the
/// [CatalogStripHandle]. It requires the chrome theme and strings scopes, and
/// reads the arrangement from `PanelArrangementScope`.
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

  /// Height of the line over the strip where it is pinned at the bottom (the
  /// pointer arrangement); it is not part of [height].
  static const double separatorExtent = 1;

  /// Side of the square that marks the active category (pointer).
  static const double highlightSize = 28;

  /// Corner radius of that square.
  static const double highlightRadius = 8;

  /// Horizontal inset of the first icon (pointer).
  static const double pointerPadH = 3;

  /// The least width an icon gets before the strip scrolls (pointer).
  static const double pointerMinPitch = 33;

  /// Identifies the sliding square of the pointer arrangement.
  @visibleForTesting
  static const Key highlightKey = ValueKey<String>('emoji-strip-highlight');

  @override
  State<EmojiCategoryStrip> createState() => _EmojiCategoryStripState();
}

class _EmojiCategoryStripState extends State<EmojiCategoryStrip> {
  final _scroll = ScrollController();
  var _tabs = const <_StripTab>[];
  EmojiCategoryTab? _active;
  var _jumping = false;
  // How wide the icon of a tab is under the pointer arrangement, as the last
  // layout gave it; the reveal of an active tab needs it outside build.
  var _pitch = EmojiCategoryStrip.pointerMinPitch;
  late StreamSubscription<PanelCatalogScrollEvent> _scrollEvents;

  CatalogStripHandle get _handle => widget.handle;

  @override
  void initState() {
    super.initState();
    _tabs = _tabsOf(_handle.entries.value);
    _active = _tabOfSection(_handle.currentSectionId) ?? _tabs.firstOrNull?.tab;
    _handle.entries.addListener(_onEntries);
    _scrollEvents = _handle.scrollEvents.listen(_onScroll);
  }

  @override
  void didUpdateWidget(EmojiCategoryStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.handle, widget.handle)) return;
    oldWidget.handle.entries.removeListener(_onEntries);
    unawaited(_scrollEvents.cancel());
    _handle.entries.addListener(_onEntries);
    _scrollEvents = _handle.scrollEvents.listen(_onScroll);
    _onEntries();
  }

  @override
  void dispose() {
    _handle.entries.removeListener(_onEntries);
    unawaited(_scrollEvents.cancel());
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
    if (_jumping) return;
    if (event case PanelCatalogCurrentSectionChanged(:final sectionId)) {
      _select(_tabOfSection(sectionId));
    }
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
        setState(() => _jumping = false);
      }
    }
  }

  void _revealActive() {
    if (!mounted || !_scroll.hasClients) return;
    final index = _tabs.indexWhere((tab) => tab.tab == _active);
    if (index < 0) return;
    final pointer =
        PanelArrangementScope.of(context) == PanelArrangement.pointer;
    final start = pointer
        ? EmojiCategoryStrip.pointerPadH + index * _pitch
        : EmojiCategoryStrip.padH +
              index * (EmojiCategoryStrip.cell + EmojiCategoryStrip.gap);
    final end = start + (pointer ? _pitch : EmojiCategoryStrip.cell);
    final margin = pointer
        ? EmojiCategoryStrip.pointerPadH
        : EmojiCategoryStrip.padH;
    final view = _scroll.position.viewportDimension;
    final offset = _scroll.offset;
    // The strip slides on the fade role: under an instant speed (a zero duration, which
    // `moveTo` turns into a jump) the tab lands at once.
    final spec = ChromeMotionScope.of(context).specOf(MotionRole.fade);
    if (start < offset) {
      unawaited(
        _scroll.position.moveTo(
          start - margin,
          duration: spec.duration,
          curve: spec.curve,
        ),
      );
    } else if (end > offset + view) {
      unawaited(
        _scroll.position.moveTo(
          end - view + margin,
          duration: spec.duration,
          curve: spec.curve,
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
    if (PanelArrangementScope.of(context) == PanelArrangement.pointer) {
      return _buildPinned(context, panel, strings, motion);
    }
    return Semantics(
      container: true,
      label: strings.semantics.categoryStripLabel,
      child: ColoredBox(
        color: panel.background,
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
                label: switch (tab.tab.titleGroup) {
                  final group? => strings.panel.categoryTitle(group),
                  null => strings.panel.recentlyUsedTitle,
                },
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

  // The strip under the pointer arrangement. Kept apart from the touch build
  // so that one stays as it was.
  Widget _buildPinned(
    BuildContext context,
    PanelTokens panel,
    ChromeStrings strings,
    ChromeMotionData motion,
  ) {
    final slide = motion.specOf(MotionRole.selectionSlide);
    final slideDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : slide.duration;
    return Semantics(
      container: true,
      label: strings.semantics.categoryStripLabel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: EmojiCategoryStrip.separatorExtent,
            width: double.infinity,
            child: ColoredBox(color: panel.hairline),
          ),
          ColoredBox(
            color: panel.stripFill,
            child: SizedBox(
              height: EmojiCategoryStrip.height,
              width: double.infinity,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final count = _tabs.length;
                  const padH = EmojiCategoryStrip.pointerPadH;
                  final pitch = math.max(
                    EmojiCategoryStrip.pointerMinPitch,
                    (constraints.maxWidth - 2 * padH) / count,
                  );
                  _pitch = pitch;
                  final active = _tabs.indexWhere((t) => t.tab == _active);
                  return SingleChildScrollView(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: 2 * padH + count * pitch,
                      height: EmojiCategoryStrip.height,
                      child: Stack(
                        children: [
                          // Created when the first category becomes active, so
                          // it is placed, not moved there.
                          if (active >= 0)
                            AnimatedPositionedDirectional(
                              key: EmojiCategoryStrip.highlightKey,
                              duration: slideDuration,
                              curve: slide.curve,
                              start:
                                  padH +
                                  active * pitch +
                                  (pitch - EmojiCategoryStrip.highlightSize) /
                                      2,
                              top:
                                  (EmojiCategoryStrip.height -
                                      EmojiCategoryStrip.highlightSize) /
                                  2,
                              width: EmojiCategoryStrip.highlightSize,
                              height: EmojiCategoryStrip.highlightSize,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: panel.tabSelector,
                                  borderRadius: BorderRadius.circular(
                                    EmojiCategoryStrip.highlightRadius,
                                  ),
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsetsDirectional.symmetric(
                              horizontal: padH,
                            ),
                            child: Row(
                              children: [
                                for (final tab in _tabs)
                                  SizedBox(
                                    width: pitch,
                                    child: Center(
                                      child: _TabButton(
                                        tab: tab.tab,
                                        label: switch (tab.tab.titleGroup) {
                                          final group? =>
                                            strings.panel.categoryTitle(group),
                                          null =>
                                            strings.panel.recentlyUsedTitle,
                                        },
                                        selected: tab.tab == _active,
                                        tokens: panel,
                                        duration: motion.durationOf(
                                          MotionRole.fade,
                                        ),
                                        onTap: () => unawaited(_onTap(tab)),
                                        marked: false,
                                        extent:
                                            EmojiCategoryStrip.highlightSize,
                                        cursor: SystemMouseCursors.click,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
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
    this.marked = true,
    this.extent = EmojiCategoryStrip.cell,
    this.cursor = MouseCursor.defer,
  });

  final EmojiCategoryTab tab;
  final String label;
  final bool selected;
  final PanelTokens tokens;
  final Duration duration;
  final VoidCallback onTap;

  // Whether the selected tab is painted on a circle of its own (touch); the
  // pinned strip marks it with the sliding square instead.
  final bool marked;
  final double extent;
  final MouseCursor cursor;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    onTap: onTap,
    child: ExcludeSemantics(
      child: FocusableActionDetector(
        mouseCursor: cursor,
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
            width: extent,
            height: extent,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: selected ? 1 : 0),
              duration: duration,
              curve: Curves.decelerate,
              builder: (context, t, _) => DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // The idle icon colour at a low alpha, on the fill: the
                  // wash is a tint of the icon, and no saveLayer. The pinned
                  // strip marks its active tab with the sliding square.
                  color: marked
                      ? tokens.categoryIcon.withValues(
                          alpha: tokens.categoryIcon.a * 0.18 * t,
                        )
                      : null,
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

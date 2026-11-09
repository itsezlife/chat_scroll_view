import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/src/emoji/emoji_categories.dart';
import 'package:panel_pages/src/page/catalog_strip.dart';
import 'package:panel_pages/src/strip/panel_strip.dart';
import 'package:panel_shell/panel_shell.dart';

/// The strip along the top of the stickers page: a tab for the recents, when
/// the page has some, and one per pack, drawn by the pack's cover.
///
/// The reference mobile client's `ScrollSlidingTabStrip` of type `TAB` (the
/// stickers tab of the emoji view): [height] tall, each tab [tabWidth] wide
/// with the picture [iconSize] square in it, the row [padH] in from both ends
/// and scrolling sideways when the packs do not fit. A pill [pillSize] square
/// marks the active tab.
///
/// ## The active tab
///
/// It is the pack of the section the user is in (`PanelCatalogCurrentSectionChanged`),
/// or, after a tap, the tapped pack: a tap scrolls the catalogue to the head of
/// the pack's section, marks the tab at once, and until the jump ends ignores
/// both the catalogue's own scroll and a second tap, so the mark and the motion
/// cannot disagree. The tab stays marked after the jump until the user scrolls
/// into another section. There is one source of truth for the scroll, the
/// catalogue's; the strip only follows it.
///
/// ## The covers
///
/// A pack's tab shows its cover, the first sticker when the pack names none.
/// An animated cover plays and loops while its tab is in the strip's view, on
/// the shared playback clock (its pause layers pause it), decoded at its size
/// on the screen as every animated cell is; a still cover stays still. The covers repaint on
/// their own and never rebuild the strip, and the strip gives them back when
/// it leaves the tree.
///
/// ## The mark
///
/// Slides from tab to tab in 350 ms ease-out quint, retargeting from where it
/// is, swelling to 1.25 of [pillSize] wide and flattening to 0.9 tall half way
/// ([pillSizeAt]). A host with motion off, or the system's disabled animations,
/// gets it in place at once.
///
/// It slides only for what the user did: a tap, or a scroll of theirs (a
/// drag, a fling, the wheel, an animated scroll) carrying the catalogue into
/// another section. What the user did not do places the mark and the row at
/// once: the first build, a new set of tabs, and a catalogue repositioned by
/// a command (`PanelCatalogProgrammaticJump`: a fresh open restarting the
/// page, a host's jump), whose section change is placed until the next motion
/// of the user's starts. The reference mobile client selects its tab on an
/// open with no animated change (`firstTabUpdate`) and jumps its grid; a
/// slide there would play while the panel opens, or after, when its tickers
/// come back. A command that cuts a tapped tab's jump short ends the tap: the
/// mark goes where the catalogue landed.
///
/// The strip is the page's own widget: its whole connection is the
/// [CatalogStripHandle]. It requires the chrome theme, strings and motion
/// scopes. Draws nothing when the page has no pack and no recents.
class StickerPackStrip extends StatefulWidget {
  /// A strip over the sections of [handle], drawing covers through [assets]
  /// (none are drawn when it is null).
  const StickerPackStrip({required this.handle, this.assets, super.key});

  /// What the page gives its strip.
  final CatalogStripHandle handle;

  /// Where the covers of packs are drawn from, or null to draw none.
  final AssetCacheScope? assets;

  /// Height of the strip: `createFrame(MATCH_PARENT, 36)` of `stickersTab`.
  static const double height = 36;

  /// Width of a tab: `StickerTabView.SMALL_WIDTH`.
  static const double tabWidth = 33;

  /// Side of a pack's cover: `StickerTabView.IMAGE_SMALL_SIZE`.
  static const double iconSize = 26;

  /// Side of the recents' icon: `StickerTabView.IMAGE_ICON_SMALL_SIZE`.
  static const double recentsIconSize = 24;

  /// Radius of a cover's corners: `imageView.setRoundRadius(dp(6))`.
  static const double coverRadius = 6;

  /// Inset of the first tab: `tabsContainer.setPadding(dp(9.5f), 0, dp(9.5f), 0)`.
  static const double padH = 9.5;

  /// Side of the mark at rest: `sz = dp(30)` in `dispatchDraw`.
  static const double pillSize = PanelStripMetrics.pillSide;

  /// Identifies the mark of the active tab.
  @visibleForTesting
  static const Key markKey = ValueKey<String>('sticker-pack-strip-mark');

  /// The size of the mark when the slide to the next tab is [progress] of its
  /// way (0 at the start, 1 at the end, already eased): widest and flattest
  /// half way, [pillSize] square at either end.
  ///
  /// `w = sz * (1.25 - .25 * |.5 - p| * 2)`, `h = sz * (.9 + .1 * |.5 - p| * 2)`.
  static Size pillSizeAt(double progress) =>
      PanelStripSwell.stickers.apply(const Size.square(pillSize), progress);

  @override
  State<StickerPackStrip> createState() => _StickerPackStripState();
}

// What the reference's `ScrollSlidingTabStrip` measures differently from the
// emoji strip: tabs the strip's height tall and [StickerPackStrip.tabWidth]
// wide with no gap, from [StickerPackStrip.padH] in, the pill swelling as its
// `dispatchDraw` draws it, and a pack's cover playing.
const PanelStripMetrics _metrics = PanelStripMetrics(
  tabWidth: StickerPackStrip.tabWidth,
  tabHeight: StickerPackStrip.height,
  gap: 0,
  padH: StickerPackStrip.padH,
  iconSize: StickerPackStrip.recentsIconSize,
  coverSize: StickerPackStrip.iconSize,
  swell: PanelStripSwell.stickers,
  coverPlays: true,
);

// A tab and the section it leads to.
class _Tab {
  const _Tab(this.sectionId, this.collection);

  final String sectionId;
  final Collection collection;

  bool get isRecents => collection.id == CollectionId.recent;

  ContentKey? get cover =>
      collection.metadata.cover ??
      switch (collection.contents) {
        CollectionContents$Loaded(:final items) => items.firstOrNull?.key,
        _ => null,
      };
}

class _StickerPackStripState extends State<StickerPackStrip>
    with SingleTickerProviderStateMixin {
  // `scrollOffset = dp(StickerTabView.SMALL_WIDTH)`: how far from an edge
  // `scrollToChild` leaves a tab it scrolled to.
  static const double _reveal = StickerPackStrip.tabWidth;

  // Made in initState, not lazily: a strip that never had a tab would
  // otherwise first make it in dispose, looking up its ticker mode in a tree
  // that is coming down.
  late final PanelStripSlide _slide;
  final _row = ScrollController();
  // Which covers play. A notifier, not state: a scroll of the strip moves the
  // range, and only the tabs' players follow it, never the whole strip.
  final _inView = ValueNotifier<PanelStripRange>(PanelStripRange.none);
  late StreamSubscription<PanelCatalogScrollEvent> _scrollEvents;
  var _tabs = const <_Tab>[];
  String? _active;
  var _jumping = false;
  // Set by a programmatic jump of the catalogue until a motion of the user's
  // starts: the section changes it brings are placed, not slid.
  var _placing = false;
  // Whether the mark's last move was a slide: the tabs' colours ease with it,
  // or change at once with a mark that was placed.
  var _slid = false;

  CatalogStripHandle get _handle => widget.handle;

  PanelStripRow get _strip => PanelStripRow(_metrics, _tabs.length);

  // --- Lifecycle ------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _slide = PanelStripSlide(vsync: this);
    _tabs = _tabsOf(_handle.entries.value);
    _active = _tabFor(_handle.currentSectionId) ?? _tabs.firstOrNull?.sectionId;
    _handle.entries.addListener(_onEntries);
    _scrollEvents = _handle.scrollEvents.listen(_onScroll);
    _row.addListener(_onRowScroll);
    _aim(animate: false);
  }

  @override
  void didUpdateWidget(StickerPackStrip oldWidget) {
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
    _slide.dispose();
    _row.dispose();
    _inView.dispose();
    super.dispose();
  }

  // --- Following the catalogue ----------------------------------------------

  static List<_Tab> _tabsOf(List<CatalogStripEntry> entries) => [
    for (final entry in entries)
      if (entry.collection.id == CollectionId.recent ||
          entry.collection.id is CollectionId$Set)
        _Tab(entry.sectionId, entry.collection),
  ];

  String? _tabFor(String? sectionId) {
    for (final tab in _tabs) {
      if (tab.sectionId == sectionId) return tab.sectionId;
    }
    return null;
  }

  void _onEntries() {
    setState(() {
      _tabs = _tabsOf(_handle.entries.value);
      if (!_jumping) {
        _active =
            _tabFor(_handle.currentSectionId) ?? _tabs.firstOrNull?.sectionId;
      }
    });
    // A new set of tabs moves the tabs at once; a slide of the mark would
    // trail behind its own tab.
    _aim(animate: false);
  }

  void _onScroll(PanelCatalogScrollEvent event) {
    switch (event) {
      case PanelCatalogProgrammaticJump():
        _placing = true;
        // The command took over from a tapped tab's jump, whose end would
        // arrive only after the section the command landed in.
        _jumping = false;
      case PanelCatalogUserDragStart() ||
          PanelCatalogFlingStart() ||
          PanelCatalogViewportScrolled() ||
          PanelCatalogAnimateStart() ||
          PanelCatalogSectionJumpStart():
        _placing = false;
      case PanelCatalogCurrentSectionChanged(:final sectionId) when !_jumping:
        final tab = _tabFor(sectionId);
        if (tab == null || tab == _active) return;
        setState(() => _active = tab);
        _aim(animate: !_placing);
      default:
        break;
    }
  }

  Future<void> _onTap(_Tab tab) async {
    if (_jumping) return;
    setState(() {
      _active = tab.sectionId;
      _jumping = true;
      _placing = false;
    });
    _aim(animate: true);
    try {
      await _handle.jumpToSection(tab.sectionId);
    } finally {
      if (mounted) setState(() => _jumping = false);
    }
  }

  // --- The mark and the scroll ----------------------------------------------

  int? get _activeIndex {
    final index = _tabs.indexWhere((tab) => tab.sectionId == _active);
    return index < 0 ? null : index;
  }

  bool get _still => PanelStripSlide.isStill(context);

  // Points the mark at the active tab and scrolls it into view.
  void _aim({required bool animate}) {
    final index = _activeIndex;
    if (index == null) return;
    final moving = animate && !_still;
    _slid = moving;
    _slide.aim(index, moving: moving);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollTo(index, animate: moving);
    });
  }

  // `scrollToChild`: nothing when the tab is already in view; otherwise the
  // tab lands [_reveal] in from the edge it was beyond, the first tab at the
  // start.
  void _scrollTo(int index, {required bool animate}) {
    if (!_row.hasClients) return;
    final position = _row.position;
    final left = _strip.boundsOf(index).left;
    final wanted = index > 0 ? left - _reveal : left;
    double? to;
    if (wanted < position.pixels) {
      to = wanted;
    } else if (wanted + _reveal >
        position.pixels + position.viewportDimension - _reveal * 2) {
      to = wanted - position.viewportDimension + _reveal * 3;
    }
    if (to == null) return;
    PanelStripSlide.scroll(
      _row,
      to.clamp(0, position.maxScrollExtent),
      animate: animate,
    );
  }

  // --- The covers in view ---------------------------------------------------

  void _onRowScroll() {
    if (_row.hasClients) _showTabsOf(_row.position);
  }

  // The scroll moves the range; a new size of the strip or a new set of tabs
  // moves it too, and arrives as a metrics change (the first layout is one).
  void _showTabsOf(ScrollMetrics metrics) =>
      _inView.value = _strip.rangeOf(metrics);

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_tabs.isEmpty) return const SizedBox.shrink();
    final strings = ChromeStringsScope.of(context);
    final tokens = ChromeThemeScope.panelOf(context);
    final strip = _strip;
    return Semantics(
      container: true,
      label: strings.semantics.stickerPackStripLabel,
      // The shell's background: see-through on glass.
      child: ColoredBox(
        color: PanelBackgroundScope.of(context),
        child: SizedBox(
          height: StickerPackStrip.height,
          width: double.infinity,
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (notification) {
              _showTabsOf(notification.metrics);
              return false;
            },
            child: SingleChildScrollView(
              controller: _row,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: strip.width,
                height: StickerPackStrip.height,
                child: Stack(
                  children: [
                    AnimatedBuilder(
                      animation: _slide.controller,
                      builder: (context, _) {
                        final pill = strip.pillAt(_slide);
                        return PositionedDirectional(
                          start: pill.left,
                          top: pill.top,
                          width: pill.width,
                          height: pill.height,
                          child: PanelStripPill(
                            key: StickerPackStrip.markKey,
                            tokens: tokens,
                            height: pill.height,
                          ),
                        );
                      },
                    ),
                    // Keyed by section, so a tab added or moved in front
                    // (the recents arriving) moves the others' covers with
                    // them; by position each cover would be handed its
                    // neighbour's content and load again.
                    for (final (i, tab) in _tabs.indexed)
                      PositionedDirectional(
                        key: ValueKey<String>(tab.sectionId),
                        start: strip.boundsOf(i).left,
                        top: 0,
                        width: StickerPackStrip.tabWidth,
                        height: StickerPackStrip.height,
                        child: _TabButton(
                          index: i,
                          inView: _inView,
                          label: tab.isRecents
                              ? strings.panel.recentlyUsedTitle
                              : tab.collection.metadata.title ?? '',
                          cover: tab.isRecents ? null : tab.cover,
                          selected: tab.sectionId == _active,
                          tokens: tokens,
                          assets: widget.assets,
                          duration: _slid
                              ? PanelStripMetrics.slideDuration
                              : Duration.zero,
                          onTap: () => unawaited(_onTap(tab)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One tab: the recents' icon in the idle or selected colour, or a pack's
/// cover.
class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.index,
    required this.inView,
    required this.label,
    required this.cover,
    required this.selected,
    required this.tokens,
    required this.assets,
    required this.duration,
    required this.onTap,
  });

  /// Where the tab is in the strip.
  final int index;

  /// The tabs the strip's viewport shows.
  final ValueListenable<PanelStripRange> inView;

  final String label;
  final ContentKey? cover;
  final bool selected;
  final PanelTokens tokens;
  final AssetCacheScope? assets;
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
          child: Center(child: _picture()),
        ),
      ),
    ),
  );

  Widget _picture() => switch ((cover, assets)) {
    (null, _) => PanelStripIcon(
      icon: EmojiCategories.recents.icon,
      size: _metrics.iconSize,
      selected: selected,
      tokens: tokens,
      duration: duration,
    ),
    // The whole cover, playing and looping: the reference client's tab plays
    // an animated cover (filter `40_40`, `40_40_firstframe` only in its lite
    // mode, which here is the clock's `lowPower` layer). A still cover is a
    // still paintable and never moves. Off the strip's screen the binding
    // stops, as the reference strip clears the images of the tabs out of
    // view.
    (final cover?, final scope?) => PanelStripCover(
      content: cover,
      scope: scope,
      size: _metrics.coverSize,
      plays: _metrics.coverPlays,
      tokens: tokens,
      radius: StickerPackStrip.coverRadius,
      index: index,
      inView: inView,
    ),
    (_, null) => const SizedBox.shrink(),
  };
}

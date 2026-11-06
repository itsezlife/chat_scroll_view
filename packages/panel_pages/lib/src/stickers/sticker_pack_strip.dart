import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart' show FrameAtlas;
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/src/emoji/emoji_categories.dart';
import 'package:panel_pages/src/page/catalog_strip.dart';
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
/// the shared playback clock (its pause layers pause it), decoded no larger
/// than [coverMaxPixels]; a still cover stays still. The covers repaint on
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

  /// The most pixels a side of a cover is decoded at: the smallest cell of
  /// the frame pools ([FrameAtlas.defaultSizeClasses]).
  ///
  /// [iconSize] at a density of 3 is 78 pixels, which would take a 128 cell,
  /// four times the bytes, for a picture 26 wide (and a clip is decoded at
  /// its cell, so at 128). The reference client decodes at 40 dp; this strip
  /// spends less, a little softer on the densest screens.
  static final int coverMaxPixels = FrameAtlas.defaultSizeClasses.first;

  /// Radius of a cover's corners: `imageView.setRoundRadius(dp(6))`.
  static const double coverRadius = 6;

  /// Inset of the first tab: `tabsContainer.setPadding(dp(9.5f), 0, dp(9.5f), 0)`.
  static const double padH = 9.5;

  /// Side of the mark at rest: `sz = dp(30)` in `dispatchDraw`.
  static const double pillSize = 30;

  /// Identifies the mark of the active tab.
  @visibleForTesting
  static const Key markKey = ValueKey<String>('sticker-pack-strip-mark');

  /// The size of the mark when the slide to the next tab is [progress] of its
  /// way (0 at the start, 1 at the end, already eased): widest and flattest
  /// half way, [pillSize] square at either end.
  ///
  /// `w = sz * (1.25 - .25 * |.5 - p| * 2)`, `h = sz * (.9 + .1 * |.5 - p| * 2)`.
  static Size pillSizeAt(double progress) {
    final far = (0.5 - progress).abs() * 2;
    return Size(pillSize * (1.25 - .25 * far), pillSize * (.9 + .1 * far));
  }

  @override
  State<StickerPackStrip> createState() => _StickerPackStripState();
}

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

// The tabs from [start] up to [end], not included: those the strip's viewport
// shows, in part or whole.
@immutable
class _TabRange {
  const _TabRange(this.start, this.end);

  // The tabs a viewport of [metrics] shows.
  factory _TabRange.of(ScrollMetrics metrics, int tabCount) {
    const width = StickerPackStrip.tabWidth;
    final from = metrics.pixels - StickerPackStrip.padH;
    return _TabRange(
      (from / width).floor().clamp(0, tabCount),
      ((from + metrics.viewportDimension) / width).ceil().clamp(0, tabCount),
    );
  }

  // Before the first layout: nothing plays yet.
  static const _TabRange none = _TabRange(0, 0);

  final int start;
  final int end;

  bool contains(int index) => index >= start && index < end;

  @override
  bool operator ==(Object other) =>
      other is _TabRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

class _StickerPackStripState extends State<StickerPackStrip>
    with SingleTickerProviderStateMixin {
  // `currentPositionAnimated`: 350 ms ease-out quint.
  static const Duration _slideDuration = Duration(milliseconds: 350);
  static const Duration _scrollDuration = Duration(milliseconds: 250);
  static const Curve _curve = Curves.easeOutQuint;

  // `scrollOffset = dp(StickerTabView.SMALL_WIDTH)`: how far from an edge
  // `scrollToChild` leaves a tab it scrolled to.
  static const double _reveal = StickerPackStrip.tabWidth;

  // Made in initState, not lazily: a strip that never had a tab would
  // otherwise first make it in dispose, looking up its ticker mode in a tree
  // that is coming down.
  late final AnimationController _slide;
  final _row = ScrollController();
  // Which covers play. A notifier, not state: a scroll of the strip moves the
  // range, and only the tabs' players follow it, never the whole strip.
  final _inView = ValueNotifier<_TabRange>(_TabRange.none);
  late StreamSubscription<PanelCatalogScrollEvent> _scrollEvents;
  var _tabs = const <_Tab>[];
  String? _active;
  var _jumping = false;

  // Where the mark was when its slide began, in tab indices, and where it
  // goes.
  double _from = 0;
  double _to = 0;
  var _placed = false;

  CatalogStripHandle get _handle => widget.handle;

  // --- Lifecycle ------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _slide = AnimationController(vsync: this, duration: _slideDuration);
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
    _aim(animate: _placed);
  }

  void _onScroll(PanelCatalogScrollEvent event) {
    if (_jumping) return;
    if (event case PanelCatalogCurrentSectionChanged(:final sectionId)) {
      final tab = _tabFor(sectionId);
      if (tab == null || tab == _active) return;
      setState(() => _active = tab);
      _aim(animate: true);
    }
  }

  Future<void> _onTap(_Tab tab) async {
    if (_jumping) return;
    setState(() {
      _active = tab.sectionId;
      _jumping = true;
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

  bool get _still {
    final motion = ChromeMotionScope.maybeOf(context);
    return MediaQuery.maybeDisableAnimationsOf(context) == true ||
        motion?.specOf(MotionRole.selectionSlide).duration == Duration.zero;
  }

  // Points the mark at the active tab and scrolls it into view.
  void _aim({required bool animate}) {
    final index = _activeIndex;
    if (index == null) return;
    final moving = animate && !_still;
    if (!_placed || index.toDouble() != _to) {
      // Retargets from where the mark is, as `AnimatedFloat` does.
      final now = lerpDouble(_from, _to, _curve.transform(_slide.value))!;
      _from = moving ? now : index.toDouble();
      _to = index.toDouble();
      if (moving) {
        unawaited(_slide.forward(from: 0));
      } else {
        _slide.value = 1;
      }
    }
    _placed = true;
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
    final left = StickerPackStrip.padH + index * StickerPackStrip.tabWidth;
    final wanted = index > 0 ? left - _reveal : left;
    double? to;
    if (wanted < position.pixels) {
      to = wanted;
    } else if (wanted + _reveal >
        position.pixels + position.viewportDimension - _reveal * 2) {
      to = wanted - position.viewportDimension + _reveal * 3;
    }
    if (to == null) return;
    to = to.clamp(0, position.maxScrollExtent);
    if ((position.pixels - to).abs() < .5) return;
    if (animate) {
      unawaited(_row.animateTo(to, duration: _scrollDuration, curve: _curve));
    } else {
      _row.jumpTo(to);
    }
  }

  // --- The covers in view ---------------------------------------------------

  void _onRowScroll() {
    if (_row.hasClients) _showTabsOf(_row.position);
  }

  // The scroll moves the range; a new size of the strip or a new set of tabs
  // moves it too, and arrives as a metrics change (the first layout is one).
  void _showTabsOf(ScrollMetrics metrics) =>
      _inView.value = _TabRange.of(metrics, _tabs.length);

  Rect _pillAt() {
    final a = _curve.transform(_slide.value);
    final at = lerpDouble(_from, _to, a)!;
    final size = StickerPackStrip.pillSizeAt(a);
    final centre =
        StickerPackStrip.padH + (at + .5) * StickerPackStrip.tabWidth;
    return Rect.fromCenter(
      center: Offset(centre, StickerPackStrip.height / 2),
      width: size.width,
      height: size.height,
    );
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_tabs.isEmpty) return const SizedBox.shrink();
    final strings = ChromeStringsScope.of(context);
    final tokens = ChromeThemeScope.panelOf(context);
    final width =
        StickerPackStrip.padH * 2 + _tabs.length * StickerPackStrip.tabWidth;
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
                width: width,
                height: StickerPackStrip.height,
                child: Stack(
                  children: [
                    AnimatedBuilder(
                      animation: _slide,
                      builder: (context, _) {
                        final pill = _pillAt();
                        return PositionedDirectional(
                          start: pill.left,
                          top: pill.top,
                          width: pill.width,
                          height: pill.height,
                          child: DecoratedBox(
                            key: StickerPackStrip.markKey,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                pill.height / 2,
                              ),
                              // The idle icon colour at a low alpha: the wash
                              // is a tint of the icon, as the emoji strip's.
                              color: tokens.categoryIcon.withValues(
                                alpha: tokens.categoryIcon.a * 0.18,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    for (final (i, tab) in _tabs.indexed)
                      PositionedDirectional(
                        start:
                            StickerPackStrip.padH +
                            i * StickerPackStrip.tabWidth,
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
                          duration: _still ? Duration.zero : _slideDuration,
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
  final ValueListenable<_TabRange> inView;

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
          child: Center(child: _picture(context)),
        ),
      ),
    ),
  );

  Widget _picture(BuildContext context) {
    final cover = this.cover;
    final scope = assets;
    if (cover == null) {
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(end: selected ? 1 : 0),
        duration: duration,
        curve: Curves.easeOutQuint,
        builder: (context, t, _) => ChromeIcon(
          EmojiCategories.recents.icon,
          size: StickerPackStrip.recentsIconSize,
          color: Color.lerp(
            tokens.categoryIcon,
            tokens.categoryIconSelected,
            t,
          ),
        ),
      );
    }
    if (scope == null) return const SizedBox.shrink();
    // The whole cover, playing and looping: the reference client's tab plays
    // an animated cover (filter `40_40`, `40_40_firstframe` only in its lite
    // mode, which here is the clock's `lowPower` layer). A still cover is a
    // still paintable and never moves. The view repaints through its binding,
    // so the strip is not rebuilt for a frame.
    final pixels = math.min(
      (StickerPackStrip.iconSize * MediaQuery.devicePixelRatioOf(context))
          .ceil(),
      StickerPackStrip.coverMaxPixels,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(StickerPackStrip.coverRadius),
      child: SizedBox.square(
        dimension: StickerPackStrip.iconSize,
        child: ValueListenableBuilder<_TabRange>(
          valueListenable: inView,
          // Off the strip's screen the binding stops, so a tab scrolled away
          // neither repaints nor keeps its frame lease (nor a video slot), as
          // the reference strip clears the images of the tabs out of view.
          builder: (context, range, view) =>
              TickerMode(enabled: range.contains(index), child: view!),
          child: ContentView(
            content: cover,
            scope: scope,
            preset: AssetPreset(
              size: const Size.square(StickerPackStrip.iconSize),
              spec: AssetSpec(pixelWidth: pixels, pixelHeight: pixels),
              profile: const AssetProfile(animate: true),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_chrome/chat_chrome.dart';
import 'package:chat_chrome/src/panel/emoji_catalog_data_source.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:panel_catalog/panel_catalog.dart';

/// Embeddable unicode emoji grid with overlay category strip.
///
/// Owns catalog presentation via [PanelCatalogViewport], category navigation,
/// search results layout, and skin-tone long-press chrome. Does **not** own the
/// panel shell, bottom type tabs, or recents persistence policy — inject those
/// via [dataSource], [recents], and host callbacks.
///
/// **Layout**: sectioned catalog projected by the panel catalog viewport (not
/// per-cell widgets). Category jumps call [PanelCatalogController.jumpToSection]
/// (near smooth scroll vs far stitch — engine-owned path selection via
/// [kFarPathDistanceGateFactor] flat-row gate). Strip re-taps are ignored
/// while [PanelCatalogController.isSectionJumpActive].
///
/// **Rebuild isolation**: strip slide and selected category index live on
/// [ValueNotifier]s so scroll does not rebuild the viewport subtree. Prefer
/// [searchController] / [searchModeListenable] when the host MUST avoid
/// rebuilding this page on every keystroke.
///
/// **Embedding**: use the [EmojiGridView] typedef when mounting outside
/// [KeyboardPanel]. Keep-alive is enabled so a pager may retain this page.
class EmojiPage extends StatefulWidget {
  /// Creates the emoji grid (also exported as [EmojiGridView]).
  const EmojiPage({
    required this.dataSource,
    required this.recents,
    required this.recentlyUsedLabel,
    required this.onEmojiSelected,
    this.recentsStripIcon,
    this.searchQuery = '',
    this.searchController,
    this.searchMode = false,
    this.searchModeListenable,
    this.showCategoryStrip = true,
    this.searchFieldTranslationY,
    this.searchFieldShadow,
    this.searchFocusNode,
    this.searchHintText,
    this.searchResultsLabel,
    this.searchEmptyLabel,
    this.onOpenSearch,
    this.onClearRecents,
    super.key,
  });

  /// Catalog, search, and skin-tone prefs.
  ///
  /// The page listens via [EmojiDataSource.addDataListener] and rebuilds
  /// sections when the source notifies.
  final EmojiDataSource dataSource;

  /// Frequently-used glyphs (most-used first).
  ///
  /// Empty → no synthetic recents section. The panel shell typically defers
  /// applying pending recents until dismiss.
  final List<String> recents;

  /// Host-localized title for the synthetic recents section header.
  final String recentlyUsedLabel;

  /// Strip icon for the synthetic recents section.
  ///
  /// Defaults to [EmojiTabAssets.recentsStripIcon] when null.
  final EmojiStripIcon? recentsStripIcon;

  /// Insert into the composer.
  ///
  /// [source] MUST reflect how the glyph was chosen so the data source can
  /// apply recents policy (`grid` / `recent` / `search`).
  final void Function(String glyph, {required EmojiPickSource source})
  onEmojiSelected;

  /// Long-press on a recent cell — host SHOULD confirm before clearing.
  final VoidCallback? onClearRecents;

  /// Keyword query when [searchController] is null.
  ///
  /// Non-empty → keyword hits. Empty + [searchMode] → frequently-used only.
  /// Ignored while [searchController] is non-null (controller text wins).
  final String searchQuery;

  /// Optional live query source — page listens without a parent rebuild.
  ///
  /// When non-null, [searchQuery] is ignored.
  final TextEditingController? searchController;

  /// Whether search chrome is open when [searchModeListenable] is null.
  ///
  /// Picks report [EmojiPickSource.search] while search mode is active.
  /// Ignored while [searchModeListenable] is non-null.
  final bool searchMode;

  /// Optional live search-mode flag (panel shell).
  ///
  /// When set, category strip visibility is `!value` and overrides
  /// [showCategoryStrip].
  final ValueListenable<bool>? searchModeListenable;

  /// Whether to paint the overlay category strip.
  ///
  /// Hosts typically pass `false` while searching. Overridden by
  /// [searchModeListenable] when that listenable is non-null.
  final bool showCategoryStrip;

  /// Written by this page: sticky search-field Y (idle browse).
  ///
  /// While search mode is open the page writes `0` (field pinned). When
  /// [searchFocusNode] / [onOpenSearch] are set, this page paints
  /// [EmojiSearchField] with `Positioned` + `Transform.translate` under the
  /// category strip (Telegram `setTranslationY`).
  final ValueNotifier<double>? searchFieldTranslationY;

  /// Written by this page: search-field bottom shadow while search is open.
  final ValueNotifier<bool>? searchFieldShadow;

  /// Focus node for the sticky [EmojiSearchField] (owned by the panel shell).
  final FocusNode? searchFocusNode;

  /// Search hint (host l10n).
  final String? searchHintText;

  /// Section header for keyword hits (`StickerOrEmojiSearchResult`).
  final String? searchResultsLabel;

  /// Empty keyword-search placeholder (`NoEmojiFound`).
  final String? searchEmptyLabel;

  /// Fired when the user taps the sticky field while search is closed.
  final VoidCallback? onOpenSearch;

  /// Horizontal inset of the glyph grid.
  static const double gridPadH = 5;

  /// Top inset that clears the overlay category strip.
  ///
  /// Sticky search adds [EmojiSearchField.height] on top when the panel wires
  /// [searchFieldTranslationY] ([PanelCatalogViewport.padding.top]).
  static const double gridPadTop = 36;

  /// Bottom inset that clears the panel bottom chrome (with slack).
  static const double gridPadBottom = 44;

  /// Drawn emoji glyph size (phone).
  static const double glyphSize = 34;

  /// Section header row height.
  static const double headerHeight = 27;

  /// Section header type size.
  static const double headerFontSize = 15;

  /// Extra start inset for section header titles inside horizontal padding.
  static const double headerStartInset = 8;

  /// Empty keyword-search label size (`NoEmojiFound`).
  static const double searchEmptyFontSize = 16;

  /// Top inset for empty keyword-search text (Telegram HELP cell).
  static const double searchEmptyPadTop = 10;

  /// Minimum empty-search body height when the panel is short.
  static const double searchEmptyMinHeight = 120;

  /// Cell pitch used to derive column count from width.
  static const double cellPitch = 45;

  @override
  State<EmojiPage> createState() => EmojiPageState();
}

/// State for [EmojiPage].
///
/// Exposed for widget tests and hosts that need [jumpToSection],
/// [categoryIndex], or [stripOffset]. Prefer driving navigation from the
/// category strip; do not mutate [catalogController] from outside except in
/// tests.
///
/// Category strip taps call [jumpToSection], which forwards to
/// [PanelCatalogController.jumpToSection]. While a section jump is in flight,
/// [jumpToSection] is a silent no-op so [categoryIndex] and scroll target stay
/// aligned with the in-flight motion.
class EmojiPageState extends State<EmojiPage>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  // --- Diagnostics ----------------------------------------------------------

  static final PanelCatalogDevLog _shellLog = PanelCatalogDevLog(
    'KeyboardPanel',
  );

  double? _searchLogLastOffset;
  double? _searchLogLastTy;
  double? _searchLogLastStripY;
  bool? _searchLogLastStripShadow;
  bool? _searchLogLastSpacerGone;

  // --- Viewport / catalog ---------------------------------------------------

  final PanelCatalogController _catalogController = PanelCatalogController();
  late final MemoryCatalogAssetCache _assetCache;
  late final EmojiCatalogDataSource _catalogDataSource;

  var _spanCount = 1;
  var _rowCellExtent = EmojiPage.cellPitch;
  var _viewportWidth = 0.0;
  var _viewportHeight = 0.0;
  var _contentMaxOffset = 0.0;

  // --- Category strip (notifier-scoped; scroll MUST NOT rebuild the grid) ---

  final ValueNotifier<int> _categoryIndex = ValueNotifier<int>(0);
  final ValueNotifier<double> _stripOffset = ValueNotifier<double>(0);
  final ValueNotifier<bool> _stripShadowVisible = ValueNotifier<bool>(false);

  AnimationController? _stripReveal;

  // --- Skin-tone picker session ---------------------------------------------

  EmojiColorPickerSession? _picker;
  String? _pickerBase;
  var _pickerIsRecent = false;

  // --- Search cache ---------------------------------------------------------

  /// Cells for the last completed keyword search ([_loadedSearchQuery]).
  List<({String pickGlyph, String displayGlyph, bool supportsSkinTone})>
  _searchCells = const [];

  /// Query that produced [_searchCells]; empty when not in keyword results.
  String _loadedSearchQuery = '';

  /// Restartable debounce for keyword search.
  Timer? _searchDebounce;

  /// Delayed leading-icon progress (Telegram 65ms).
  Timer? _searchProgressDelay;

  /// Monotonic generation to ignore stale [EmojiDataSource.search] replies.
  var _searchGen = 0;

  /// Leading search icon busy flag.
  final ValueNotifier<bool> _searchBusy = ValueNotifier<bool>(false);

  /// Debounced scroll-idle callback for [EmojiPage.onGridScrollIdle].
  Timer? _scrollIdleTimer;

  // --- Test / host observables ----------------------------------------------

  /// Selected category strip index (`0` = first section, often recents).
  int get categoryIndex => _categoryIndex.value;

  /// Category strip vertical translation (`0` = fully visible, negative = hidden).
  double get stripOffset => _stripOffset.value;

  /// Whether the strip bottom shadow is shown.
  bool get stripShadowVisible => _stripShadowVisible.value;

  /// Catalog scroll controller (tests / host scroll metrics).
  PanelCatalogController get catalogController => _catalogController;

  /// Current catalog content offset.
  double get catalogScrollOffset => _catalogController.offset;

  /// Max scroll offset when layout is known, else `0`.
  double get catalogMaxScrollOffset => _contentMaxOffset;

  /// Resolved [PanelCatalogViewport.padding.top] (strip + search spacer).
  @visibleForTesting
  double get catalogPaddingTop => _catalogPaddingTop;

  /// Catalog offset for sticky search / strip geometry.
  ///
  /// Uses [_effectiveCatalogOffset] during user drag (pre-clamp overscroll).
  /// During section jumps uses live [PanelCatalogController.offset] and optional
  /// [catalogOffset] preview so far teleports are not clamped to a stale
  /// [_contentMaxOffset].
  double _offsetForSearchGeometry({double? catalogOffset}) {
    if (catalogOffset != null) return catalogOffset;
    if (_catalogController.isSectionJumpActive) {
      return _catalogController.offset.clamp(0.0, double.infinity);
    }
    return _effectiveCatalogOffset;
  }

  /// Catalog offset clamped for sticky chrome geometry.
  ///
  /// [PanelCatalogController.scrollBy] notifies shell listeners before the
  /// viewport clamps — search/strip math MUST use this, not raw [offset].
  double get _effectiveCatalogOffset {
    final raw = _catalogController.offset;
    final max = _contentMaxOffset;
    if (max <= 0) return raw.clamp(0.0, double.infinity);
    return raw.clamp(0.0, max);
  }

  @override
  bool get wantKeepAlive => true;

  // --- Derived projections (widget / listenables) ---------------------------

  /// Live search text: [EmojiPage.searchController] wins over [EmojiPage.searchQuery].
  String get _activeSearchQuery =>
      widget.searchController?.text ?? widget.searchQuery;

  /// Whether picks report [EmojiPickSource.search].
  bool get _searchMode =>
      widget.searchModeListenable?.value ?? widget.searchMode;

  /// Whether the overlay category strip is painted.
  bool get _showCategoryStrip => widget.searchModeListenable != null
      ? !widget.searchModeListenable!.value
      : widget.showCategoryStrip;

  /// Whether [KeyboardPanel] wired the sticky search overlay (strip + search band).
  bool get _hasStickySearchOverlay =>
      widget.searchFieldTranslationY != null &&
      widget.searchController != null &&
      widget.onOpenSearch != null;

  /// Top catalog inset: category strip + search spacer.
  ///
  /// Master used [gridPadTop] on [SliverPadding] plus a leading
  /// `_SearchSpacerItem` of [EmojiSearchField.height] in the flat list.
  /// [PanelCatalogViewport.padding.top] folds both into one inset.
  double get _catalogPaddingTop {
    final stripInset = _showCategoryStrip && _loadedSearchQuery.isEmpty
        ? EmojiPage.gridPadTop
        : 0.0;
    final searchSpacerInset = _hasStickySearchOverlay
        ? EmojiSearchField.height
        : 0.0;
    return stripInset + searchSpacerInset;
  }

  /// Strip inset for [PanelCatalogViewport.headerLandingInset] (master padTop).
  double get _headerLandingInset =>
      _showCategoryStrip && _loadedSearchQuery.isEmpty
      ? EmojiPage.gridPadTop
      : 0.0;

  EdgeInsets get _catalogPadding {
    final viewPadding = MediaQuery.maybeViewPaddingOf(context);
    final bottom = EmojiPage.gridPadBottom + (viewPadding?.bottom ?? 0);
    return EdgeInsets.fromLTRB(
      EmojiPage.gridPadH,
      _catalogPaddingTop,
      EmojiPage.gridPadH,
      bottom,
    );
  }

  // --- Lifecycle ------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _assetCache = MemoryCatalogAssetCache();
    _catalogDataSource = EmojiCatalogDataSource(
      emojiSource: widget.dataSource,
      assetCache: _assetCache,
    );
    _catalogController.addScrollListener(_onCatalogScrollEvent);
    _stripOffset.addListener(_onStripOffsetChanged);
    widget.dataSource.addDataListener(_onDataChanged);
    widget.searchController?.addListener(_onSearchController);
    widget.searchModeListenable?.addListener(_onSearchModeListenable);
    _rebuildCatalog();
    _scheduleSearch(_activeSearchQuery);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateSearchGeometry();
      unawaited(warmAhead());
    });
  }

  /// Cold-start warm-up for the first `[screens]` viewport heights of glyphs.
  ///
  /// Forwards to [PanelCatalogController.warmAhead]. Silent no-op when the
  /// viewport is not yet bound.
  Future<void> warmAhead({double screens = 2.5}) =>
      _catalogController.warmAhead(screens: screens);

  @override
  void didUpdateWidget(EmojiPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataSource != widget.dataSource) {
      oldWidget.dataSource.removeDataListener(_onDataChanged);
      widget.dataSource.addDataListener(_onDataChanged);
      _catalogDataSource.dispose();
      _catalogDataSource = EmojiCatalogDataSource(
        emojiSource: widget.dataSource,
        assetCache: _assetCache,
      );
      _rebuildCatalog();
    } else if (!identical(oldWidget.recents, widget.recents) ||
        oldWidget.recentlyUsedLabel != widget.recentlyUsedLabel ||
        oldWidget.recentsStripIcon != widget.recentsStripIcon) {
      _rebuildCatalog();
    }
    if (!identical(oldWidget.searchController, widget.searchController)) {
      oldWidget.searchController?.removeListener(_onSearchController);
      widget.searchController?.addListener(_onSearchController);
      _scheduleSearch(_activeSearchQuery);
    } else if (widget.searchController == null &&
        oldWidget.searchQuery != widget.searchQuery) {
      _scheduleSearch(widget.searchQuery);
    }
    if (!identical(
      oldWidget.searchModeListenable,
      widget.searchModeListenable,
    )) {
      oldWidget.searchModeListenable?.removeListener(_onSearchModeListenable);
      widget.searchModeListenable?.addListener(_onSearchModeListenable);
      if (mounted) setState(() {});
    } else if (widget.searchModeListenable == null &&
        (oldWidget.searchMode != widget.searchMode ||
            oldWidget.showCategoryStrip != widget.showCategoryStrip)) {
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _scrollIdleTimer?.cancel();
    widget.dataSource.removeDataListener(_onDataChanged);
    widget.searchController?.removeListener(_onSearchController);
    widget.searchModeListenable?.removeListener(_onSearchModeListenable);
    _searchDebounce?.cancel();
    _searchProgressDelay?.cancel();
    _searchBusy.dispose();
    _picker?.cancel();
    _stripReveal?.dispose();
    _stripOffset.removeListener(_onStripOffsetChanged);
    _categoryIndex.dispose();
    _stripOffset.dispose();
    _stripShadowVisible.dispose();
    _catalogController.removeScrollListener(_onCatalogScrollEvent);
    _catalogController.dispose();
    _catalogDataSource.dispose();
    super.dispose();
  }

  // --- Data / search listeners ----------------------------------------------

  /// Catalog or prefs changed — rebuild catalog projection.
  void _onDataChanged() {
    _rebuildCatalog();
    if (_loadedSearchQuery.isNotEmpty) {
      unawaited(_loadSearch(_loadedSearchQuery));
    }
    if (mounted) setState(() {});
  }

  void _onSearchController() => _scheduleSearch(_activeSearchQuery);

  void _onSearchModeListenable() {
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateSearchGeometry();
    });
  }

  void _onStripOffsetChanged() => _updateSearchGeometry();

  void _onCatalogScrollEvent(PanelCatalogScrollEvent event) {
    switch (event) {
      case PanelCatalogOffsetChanged():
      case PanelCatalogProgrammaticJump():
        _updateSearchGeometry();
        _maybeSyncCategoryIndex();
      case PanelCatalogViewportScrolled(:final delta):
        _handleStripHideOnScroll(delta);
        _dismissSearchFocusOnScroll(delta);
        _scheduleScrollIdle();
      case PanelCatalogUserDragStart():
        _dismissSearchFocusOnUserDrag();
      case PanelCatalogSectionJumpStart():
        _updateSearchGeometry();
      case PanelCatalogSectionJumpEnd():
        _updateSearchGeometry();
      case PanelCatalogAnimateStart():
        _updateSearchGeometry();
      default:
        break;
    }
  }

  void _maybeSyncCategoryIndex() {
    if (_catalogController.isSectionJumpActive) return;
    final index = _sectionIndexForOffset(_effectiveCatalogOffset);
    if (index != _categoryIndex.value) {
      _categoryIndex.value = index;
    }
  }

  void _dismissSearchFocusOnUserDrag() {
    if (_catalogController.isSectionJumpActive) return;
    final focus = widget.searchFocusNode;
    if (focus == null || !focus.hasFocus) return;
    focus.unfocus();
  }

  void _scheduleScrollIdle() {
    _scrollIdleTimer?.cancel();
    _scrollIdleTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      _maybeSyncCategoryIndex();
    });
  }

  // --- Catalog rebuild ------------------------------------------------------

  void _rebuildCatalog() {
    _catalogDataSource.rebuild(
      recents: widget.recents,
      recentlyUsedLabel: widget.recentlyUsedLabel,
      recentsStripIcon: widget.recentsStripIcon,
      searchQuery: _loadedSearchQuery,
      searchCells: _searchCells,
      searchResultsLabel: widget.searchResultsLabel ?? 'Search result',
    );
    _updateContentMaxOffset();
  }

  _Cell _cellForCatalogItem(UnicodeEmojiItem item) {
    final supports = item.supportsSkinTone;
    final display = supports
        ? EmojiSkinTone.apply(
            item.glyph,
            widget.dataSource.skinToneFor(item.glyph),
          )
        : item.glyph;
    return _Cell(
      pickGlyph: item.glyph,
      displayGlyph: display,
      supportsSkinTone: supports,
    );
  }

  // --- Search load ----------------------------------------------------------

  void _setSearchBusy(bool busy) {
    if (_searchBusy.value == busy) return;
    _searchBusy.value = busy;
  }

  void _scheduleSearch(String query) {
    final q = query.trim();
    _searchDebounce?.cancel();
    _searchProgressDelay?.cancel();

    if (q.isEmpty) {
      _searchGen++;
      _setSearchBusy(false);
      if (_loadedSearchQuery.isNotEmpty || _searchCells.isNotEmpty) {
        setState(() {
          _loadedSearchQuery = '';
          _searchCells = const [];
        });
        _rebuildCatalog();
      }
      return;
    }

    _searchProgressDelay = Timer(KeyboardPanelMotion.searchProgressDelay, () {
      if (!mounted) return;
      if (_activeSearchQuery.trim() != q) return;
      _setSearchBusy(true);
    });
    _searchDebounce = Timer(KeyboardPanelMotion.searchDebounce, () {
      unawaited(_loadSearch(q));
    });
  }

  Future<void> _loadSearch(String query) async {
    final gen = ++_searchGen;
    final items = await widget.dataSource.search(query);
    if (!mounted || gen != _searchGen) return;
    if (_activeSearchQuery.trim() != query) return;
    final cells =
        <({String pickGlyph, String displayGlyph, bool supportsSkinTone})>[];
    for (final item in items) {
      if (item case final UnicodeEmojiItem unicode) {
        final cell = _cellForCatalogItem(unicode);
        cells.add((
          pickGlyph: cell.pickGlyph,
          displayGlyph: cell.displayGlyph,
          supportsSkinTone: cell.supportsSkinTone,
        ));
      }
    }
    _setSearchBusy(false);
    setState(() {
      _loadedSearchQuery = query;
      _searchCells = cells;
    });
    _rebuildCatalog();
    _catalogController.jumpTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateSearchGeometry();
    });
  }

  // --- Layout helpers -------------------------------------------------------

  List<EmojiCategoryStripTab> _stripTabs() => _catalogDataSource.stripTabs
      .map((t) => EmojiCategoryStripTab(id: t.id, icon: t.icon))
      .toList(growable: false);

  int _columnCount(double width) {
    final inner = math.max(0.0, width - EmojiPage.gridPadH * 2);
    return math.max(1, inner ~/ EmojiPage.cellPitch);
  }

  double _cellExtentForWidth(double width, int columns) {
    final inner = math.max(0.0, width - EmojiPage.gridPadH * 2);
    return inner / columns;
  }

  void _updateContentMaxOffset() {
    if (_viewportWidth <= 0 || _viewportHeight <= 0) return;
    final sections = _catalogDataSource.sections;
    var y = _catalogPadding.top;
    for (final section in sections) {
      y += EmojiPage.headerHeight;
      final rowCount = section.leaves.isEmpty
          ? 0
          : (section.leaves.length + _spanCount - 1) ~/ _spanCount;
      y += rowCount * _rowCellExtent;
    }
    y += _catalogPadding.bottom;
    _contentMaxOffset = math.max(0, y - _viewportHeight);
  }

  int _sectionIndexForOffset(double offset) {
    final sections = _catalogDataSource.sections;
    if (sections.isEmpty) return 0;

    final padTop = _showCategoryStrip && _loadedSearchQuery.isEmpty
        ? EmojiPage.gridPadTop
        : 0.0;
    final probe = offset + padTop + 1;
    var index = 0;
    var y = _catalogPadding.top;
    for (var s = 0; s < sections.length; s++) {
      if (y <= probe) {
        index = s;
      } else {
        break;
      }
      y += EmojiPage.headerHeight;
      final leaves = sections[s].leaves;
      if (leaves.isNotEmpty) {
        final rowCount = (leaves.length + _spanCount - 1) ~/ _spanCount;
        y += rowCount * _rowCellExtent;
      }
    }
    return index;
  }

  // --- Scroll / category strip ----------------------------------------------

  /// Silent when [ty] / strip / shadow are unchanged (common after the sticky
  /// search has fully collapsed). Avoids notifier churn and log spam on every
  /// scroll tick while still refreshing when [catalogOffset] is forced.
  void _updateSearchGeometry({double? catalogOffset}) {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase != SchedulerPhase.idle &&
        phase != SchedulerPhase.postFrameCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateSearchGeometry(catalogOffset: catalogOffset);
      });
      return;
    }

    final tyNotifier = widget.searchFieldTranslationY;
    final shadowNotifier = widget.searchFieldShadow;

    if (_searchMode) {
      tyNotifier?.value = 0;
      final scrolledUnder = _effectiveCatalogOffset > 0.5;
      if (shadowNotifier != null && shadowNotifier.value != scrolledUnder) {
        shadowNotifier.value = scrolledUnder;
      }
      if (_stripShadowVisible.value) {
        _stripShadowVisible.value = false;
      }
      _logSearchGeometry(
        ty: 0,
        spacerGone: true,
        showShadow: scrolledUnder,
        searchOpen: true,
      );
      return;
    }

    final padTop = EmojiPage.gridPadTop;
    final offset = _offsetForSearchGeometry(catalogOffset: catalogOffset);
    var ty = padTop - offset;
    if (ty < -EmojiSearchField.height) {
      ty = -EmojiSearchField.height;
    }
    final forceTyUpdate =
        catalogOffset != null || _catalogController.isSectionJumpActive;
    var tyChanged = false;
    if (tyNotifier != null &&
        (forceTyUpdate || (tyNotifier.value - ty).abs() > 0.1)) {
      tyNotifier.value = ty;
      tyChanged = true;
      if (forceTyUpdate) {
        SchedulerBinding.instance.ensureVisualUpdate();
      }
    }
    if (shadowNotifier != null && shadowNotifier.value) {
      shadowNotifier.value = false;
    }

    final stripY = _stripOffset.value;
    final translatedBottom = EmojiCategoryStripOverlay.shadowProbe + stripY;
    final spacerBottom = ty + EmojiSearchField.height;
    final spacerGone = offset >= padTop + EmojiSearchField.height - 0.5;
    final showShadow =
        translatedBottom > 0 && (spacerGone || spacerBottom < translatedBottom);
    final shadowChanged = _stripShadowVisible.value != showShadow;
    if (shadowChanged) {
      _stripShadowVisible.value = showShadow;
    }
    // Skip geometry logs when nothing moved — every scrollBy used to spam
    // KeyboardPanel while the sticky search was already parked.
    if (!tyChanged && !shadowChanged && !forceTyUpdate) {
      return;
    }
    _logSearchGeometry(
      ty: ty,
      spacerGone: spacerGone,
      showShadow: showShadow,
      searchOpen: false,
      padTop: padTop,
      offset: offset,
      stripY: stripY,
      spacerBottom: spacerBottom,
      probeBottom: translatedBottom,
    );
  }

  void _logSearchGeometry({
    required double ty,
    required bool spacerGone,
    required bool showShadow,
    required bool searchOpen,
    double? padTop,
    double? offset,
    double? stripY,
    double? spacerBottom,
    double? probeBottom,
  }) {
    if (!_shellLog.enabled) return;
    final effective = offset ?? _effectiveCatalogOffset;
    final raw = _catalogController.offset;
    final strip = stripY ?? _stripOffset.value;
    final changed =
        _searchLogLastOffset != effective ||
        _searchLogLastTy != ty ||
        _searchLogLastStripY != strip ||
        _searchLogLastStripShadow != showShadow ||
        _searchLogLastSpacerGone != spacerGone;
    if (!changed) return;
    _searchLogLastOffset = effective;
    _searchLogLastTy = ty;
    _searchLogLastStripY = strip;
    _searchLogLastStripShadow = showShadow;
    _searchLogLastSpacerGone = spacerGone;
    _shellLog.event('search.geometry', {
      'offset': DevLogFormat.f(effective),
      if ((raw - effective).abs() > 0.1) 'rawOff': DevLogFormat.f(raw),
      'ty': DevLogFormat.f(ty),
      'stripY': DevLogFormat.f(strip),
      'spacerGone': spacerGone,
      'shadow': showShadow,
      'searchOpen': searchOpen,
      if (padTop != null) 'padTop': DevLogFormat.f(padTop),
      if (spacerBottom != null) 'spacerBot': DevLogFormat.f(spacerBottom),
      if (probeBottom != null) 'probeBot': DevLogFormat.f(probeBottom),
      'maxOff': DevLogFormat.f(_contentMaxOffset),
    });
  }

  void _dismissSearchFocusOnScroll(double delta) {
    if (delta == 0 || _catalogController.isSectionJumpActive) return;
    final focus = widget.searchFocusNode;
    if (focus == null || !focus.hasFocus) return;
    focus.unfocus();
  }

  void _handleStripHideOnScroll(double dy) {
    if (_catalogController.isSectionJumpActive || !_showCategoryStrip) return;
    if (dy == 0) return;

    if (dy > 0) {
      final padTop = EmojiPage.gridPadTop;
      final spacerTop = padTop - _effectiveCatalogOffset;
      if (spacerTop + EmojiSearchField.height >= padTop) {
        return;
      }
    }

    final atTop = _effectiveCatalogOffset <= 0;
    if (dy > 0 && atTop) {
      if (_stripOffset.value != 0) {
        _stripOffset.value = 0;
      }
      return;
    }

    final next = (_stripOffset.value - dy).clamp(
      -EmojiCategoryStrip.height * 3,
      0.0,
    );
    final painted = next.clamp(-EmojiCategoryStrip.height, 0.0);
    if (painted != _stripOffset.value) {
      _stripOffset.value = painted;
    }
  }

  /// Reveals the category strip, then lands section `0` under the strip inset.
  ///
  /// Runs [revealStrip], then [jumpToSection] for index `0`. Strip selection
  /// moves to the first category; scroll path (near animate vs far stitch) is
  /// owned by [jumpToSection]. Search mode is unchanged.
  ///
  /// Silent when [jumpToSection] ignores re-entry
  /// ([PanelCatalogController.isSectionJumpActive]).
  Future<void> scrollToFirstCategory() async {
    await revealStrip();
    await jumpToSection(0);
  }

  /// Animates category strip `translationY` to `0` (150ms EASE_OUT_QUINT).
  Future<void> revealStrip() async {
    final from = _stripOffset.value;
    if (from >= -0.5) {
      _stripOffset.value = 0;
      return;
    }
    _stripReveal?.dispose();
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _stripReveal = controller;
    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutQuint,
    );
    void tick() {
      _stripOffset.value = from * (1 - animation.value);
    }

    animation.addListener(tick);
    try {
      await controller.forward();
      _stripOffset.value = 0;
    } finally {
      animation.removeListener(tick);
      controller.dispose();
      if (identical(_stripReveal, controller)) {
        _stripReveal = null;
      }
    }
  }

  /// Scroll so section [index]'s header sits under the category strip inset.
  ///
  /// [index] is a section index (`0..sectionCount-1`). Out-of-range values are
  /// no-ops. Path selection (near animate vs far stitch) is engine-owned.
  ///
  /// **Re-entry:** when [PanelCatalogController.isSectionJumpActive], returns
  /// immediately without updating [categoryIndex] or forwarding to the
  /// controller — the strip selection and scroll target stay on the in-flight
  /// jump.
  ///
  /// **Side effects** (when not ignored): resets [stripOffset] to visible,
  /// updates [categoryIndex].
  Future<void> jumpToSection(int index) async {
    if (index < 0 || index >= _catalogDataSource.sections.length) return;
    if (_catalogController.isSectionJumpActive) return;
    _categoryIndex.value = index;
    _stripOffset.value = 0;
    try {
      await _catalogController.jumpToSection(index);
    } finally {
      _updateSearchGeometry();
    }
  }

  // --- Viewport leaf callbacks ----------------------------------------------

  void _onLeafTap(CatalogLeaf leaf) {
    final meta = _catalogDataSource.metaFor(leaf);
    if (_shellLog.enabled) {
      _shellLog.event('leaf.tap', {
        'key': leaf.assetKey.toString(),
        'meta': meta != null,
        'recent': meta?.isRecent,
      });
    }
    if (meta == null) return;
    _onTap(meta.pickGlyph, source: meta.pickSource, isRecent: meta.isRecent);
  }

  bool _leafLongPressEligible(CatalogLeaf leaf) {
    final meta = _catalogDataSource.metaFor(leaf);
    if (meta == null) return false;
    return meta.isRecent || meta.supportsSkinTone;
  }

  void _onLeafLongPressStart(CatalogLeaf leaf, LongPressStartDetails details) {
    final meta = _catalogDataSource.metaFor(leaf);
    if (meta == null) return;
    _onLongPressStart(
      meta.pickGlyph,
      isRecent: meta.isRecent,
      details: details,
    );
  }

  void _onLeafLongPressMove(
    CatalogLeaf leaf,
    LongPressMoveUpdateDetails details,
  ) {
    _onLongPressMove(details);
  }

  void _onLeafLongPressEnd(CatalogLeaf leaf, LongPressEndDetails details) {
    unawaited(_onLongPressEnd(details));
  }

  // --- Pick / skin-tone -----------------------------------------------------

  void _onTap(
    String glyph, {
    required EmojiPickSource source,
    required bool isRecent,
  }) {
    HapticFeedback.selectionClick();
    final base = EmojiSkinTone.strip(glyph);
    final out = isRecent
        ? glyph
        : EmojiSkinTone.apply(base, widget.dataSource.skinToneFor(base));
    final resolved = _searchMode ? EmojiPickSource.search : source;
    widget.onEmojiSelected(out, source: resolved);
  }

  void _onLongPressStart(
    String glyph, {
    required bool isRecent,
    required LongPressStartDetails details,
  }) {
    if (isRecent) {
      HapticFeedback.mediumImpact();
      widget.onClearRecents?.call();
      return;
    }

    final base = EmojiSkinTone.strip(glyph);
    if (!EmojiSkinTone.supports(base)) return;

    _picker?.cancel();
    final initial = widget.dataSource.skinToneFor(base);

    _pickerIsRecent = isRecent;
    _pickerBase = base;
    _picker = EmojiColorPickerSession.show(
      context: context,
      base: base,
      anchorGlobal: details.globalPosition,
      initialSelection: initial,
    );
  }

  void _onLongPressMove(LongPressMoveUpdateDetails details) {
    _picker?.updateFromGlobalX(details.globalPosition.dx);
  }

  Future<void> _onLongPressEnd(LongPressEndDetails details) async {
    final session = _picker;
    final base = _pickerBase;
    final isRecent = _pickerIsRecent;
    _picker = null;
    _pickerBase = null;
    if (session == null || base == null) return;

    session.complete();
    final chosen = await session.future;
    if (chosen == null || !mounted) return;

    if (!isRecent) {
      await widget.dataSource.setSkinTone(base, EmojiSkinTone.indexOf(chosen));
    }
    HapticFeedback.selectionClick();
    widget.onEmojiSelected(
      chosen,
      source: _searchMode ? EmojiPickSource.search : EmojiPickSource.grid,
    );
  }

  // --- Build ----------------------------------------------------------------

  /// Sticky search host under the strip (panel supplies focus / open callback).
  Widget? _stickySearchOverlay() {
    final focus = widget.searchFocusNode;
    final controller = widget.searchController;
    final onOpen = widget.onOpenSearch;
    final tyListenable = widget.searchFieldTranslationY;
    if (focus == null ||
        controller == null ||
        onOpen == null ||
        tyListenable == null) {
      return null;
    }
    final shadowListenable = widget.searchFieldShadow;
    final modeListenable = widget.searchModeListenable;
    final colors = ChatChromeTheme.of(context);
    // Outer builder: clip + TY only. Inner builder: search-field chrome so a
    // strip/TY tick does not rebuild [EmojiSearchField] every scroll frame.
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      bottom: 0,
      child: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          tyListenable,
          _stripOffset,
          ?modeListenable,
        ]),
        child: ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[
            _searchBusy,
            ?shadowListenable,
            ?modeListenable,
          ]),
          builder: (context, _) {
            final searchOpen = modeListenable?.value ?? widget.searchMode;
            return ColoredBox(
              color: colors.panelBackground,
              child: EmojiSearchField(
                controller: controller,
                focusNode: focus,
                searchOpen: searchOpen,
                showShadow: shadowListenable?.value ?? false,
                searchBusy: _searchBusy.value,
                searchSettled: _loadedSearchQuery.isNotEmpty,
                hintText: widget.searchHintText ?? 'Search',
                onOpenSearch: onOpen,
              ),
            );
          },
        ),
        builder: (context, child) {
          final searchOpen = modeListenable?.value ?? widget.searchMode;
          final ty = searchOpen ? 0.0 : tyListenable.value;
          final stripBottom = searchOpen || !_showCategoryStrip
              ? 0.0
              : EmojiCategoryStrip.height + _stripOffset.value + 1;
          return ClipRect(
            clipper: _TopEdgeClipper(stripBottom.clamp(0.0, double.infinity)),
            child: Align(
              alignment: Alignment.topCenter,
              child: Transform.translate(offset: Offset(0, ty), child: child),
            ),
          );
        },
      ),
    );
  }

  Widget _clipGridBelowChrome({required Widget child}) {
    final tyListenable = widget.searchFieldTranslationY;
    final hasSearchOverlay = _hasStickySearchOverlay;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        _stripOffset,
        ?tyListenable,
        ?widget.searchModeListenable,
      ]),

      child: child,
      builder: (context, child) {
        final searchOpen =
            widget.searchModeListenable?.value ?? widget.searchMode;
        final stripBottom = _showCategoryStrip
            ? EmojiCategoryStrip.height + _stripOffset.value + 1
            : 0.0;
        final searchBottom = hasSearchOverlay && !searchOpen
            ? tyListenable!.value + EmojiSearchField.height + 1
            : 0.0;
        final clipTop = math
            .max(stripBottom, searchBottom)
            .clamp(0.0, double.infinity);
        return ClipRect(clipper: _TopEdgeClipper(clipTop), child: child);
      },
    );
  }

  PanelCatalogThemeData _catalogTheme(
    ChatChromeColors colors,
    Brightness brightness,
  ) {
    final base = PanelCatalogThemeData.forBrightness(brightness);
    return base.copyWith(
      sectionHeaderStyle: base.sectionHeaderStyle.copyWith(
        color: colors.panelStickerSetName,
        fontSize: EmojiPage.headerFontSize,
      ),
      sectionHeaderStartInset: EmojiPage.headerStartInset,
      leafPressHighlightColor: brightness == Brightness.dark
          ? EmojiGlyphCell.listSelectorDark
          : EmojiGlyphCell.listSelectorLight,
    );
  }

  Widget? _emptySearchOverlay() {
    if (!_catalogDataSource.isSearchEmpty) return null;
    final colors = ChatChromeTheme.of(context);
    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(
              top: EmojiSearchField.height + EmojiPage.searchEmptyPadTop,
            ),
            child: Text(
              widget.searchEmptyLabel ?? 'No emoji found',
              style: TextStyle(
                color: colors.panelEmptyText,
                fontSize: EmojiPage.searchEmptyFontSize,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Scrolls so [displayGlyph]'s cell center sits near the viewport middle.
  @visibleForTesting
  void scrollDisplayGlyphIntoView(String displayGlyph) {
    final centerY = _contentCenterYForDisplayGlyph(displayGlyph);
    if (centerY == null) return;
    final target = (centerY - _viewportHeight * 0.45).clamp(
      0.0,
      _contentMaxOffset,
    );
    _catalogController.jumpTo(target);
  }

  double? _contentCenterYForDisplayGlyph(String displayGlyph) {
    if (_viewportWidth <= 0) return null;
    final sections = _catalogDataSource.sections;
    final padding = _catalogPadding;
    var y = padding.top;

    for (final section in sections) {
      y += EmojiPage.headerHeight;
      final leaves = section.leaves;
      for (var i = 0; i < leaves.length; i++) {
        final col = i % _spanCount;
        if (col == 0 && i > 0) {
          y += _rowCellExtent;
        }
        final leaf = leaves[i];
        if (leaf is UnicodeCatalogLeaf && leaf.glyph == displayGlyph) {
          return y + _rowCellExtent / 2;
        }
      }
      if (leaves.isNotEmpty) {
        y += _rowCellExtent;
      }
    }
    return null;
  }

  /// Section index containing [displayGlyph], or null when absent.
  @visibleForTesting
  int? sectionIndexForDisplayGlyph(String displayGlyph) {
    final sections = _catalogDataSource.sections;
    for (var s = 0; s < sections.length; s++) {
      for (final leaf in sections[s].leaves) {
        if (leaf is UnicodeCatalogLeaf && leaf.glyph == displayGlyph) {
          return s;
        }
      }
    }
    return null;
  }

  /// Global tap center for a display glyph (widget tests).
  @visibleForTesting
  Offset? globalCenterForDisplayGlyph(String displayGlyph) {
    if (_viewportWidth <= 0 || _viewportHeight <= 0) return null;
    final sections = _catalogDataSource.sections;
    final padding = _catalogPadding;
    var y = padding.top;
    final usableWidth = _viewportWidth - padding.horizontal;
    final cellW = usableWidth / _spanCount;

    for (final section in sections) {
      y += EmojiPage.headerHeight;
      final leaves = section.leaves;
      for (var i = 0; i < leaves.length; i++) {
        final col = i % _spanCount;
        if (col == 0 && i > 0) {
          y += _rowCellExtent;
        }
        final leaf = leaves[i];
        if (leaf is UnicodeCatalogLeaf && leaf.glyph == displayGlyph) {
          final x = padding.left + col * cellW + cellW / 2;
          final contentCenterY = y + _rowCellExtent / 2;
          final viewportY = contentCenterY - _catalogController.offset;
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return null;
          return box.localToGlobal(Offset(x, viewportY));
        }
      }
      if (leaves.isNotEmpty) {
        y += _rowCellExtent;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = ChatChromeTheme.of(context);
    final brightness = Theme.of(context).brightness;
    final stripTabs = _stripTabs();
    final showStrip =
        _showCategoryStrip &&
        stripTabs.isNotEmpty &&
        _loadedSearchQuery.isEmpty;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _clipGridBelowChrome(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final prevHeight = _viewportHeight;
              _viewportHeight = constraints.maxHeight;
              _viewportWidth = constraints.maxWidth;
              final columns = _columnCount(constraints.maxWidth);
              final cell = _cellExtentForWidth(constraints.maxWidth, columns);
              final spanChanged =
                  columns != _spanCount || (cell - _rowCellExtent).abs() > 0.5;
              final heightChanged =
                  (constraints.maxHeight - prevHeight).abs() > 0.5;
              if (spanChanged) {
                _spanCount = columns;
                _rowCellExtent = cell;
              }
              if (spanChanged || heightChanged) {
                _updateContentMaxOffset();
                if (_shellLog.enabled) {
                  final inner =
                      constraints.maxWidth - _catalogPadding.horizontal;
                  _shellLog.event('shell.layout', {
                    'width': DevLogFormat.f(constraints.maxWidth),
                    'height': DevLogFormat.f(constraints.maxHeight),
                    'inner': DevLogFormat.f(inner),
                    'columns': columns,
                    'span': _spanCount,
                    'cell': DevLogFormat.f(_rowCellExtent),
                    'pitch': EmojiPage.cellPitch,
                    'padT': DevLogFormat.f(_catalogPadding.top),
                    'padB': DevLogFormat.f(_catalogPadding.bottom),
                    'extent': DevLogFormat.f(_contentMaxOffset),
                    'sections': _catalogDataSource.sections.length,
                  });
                }
              }
              return PanelCatalogTheme(
                data: _catalogTheme(colors, brightness),
                child: PanelCatalogViewport(
                  dataSource: _catalogDataSource,
                  assetCache: _assetCache,
                  controller: _catalogController,
                  spanCount: _spanCount,
                  cellExtent: _rowCellExtent,
                  headerExtent: EmojiPage.headerHeight,
                  padding: _catalogPadding,
                  headerLandingInset: _headerLandingInset,
                  cacheType: CatalogAssetCacheType.keyboard,
                  onLeafTap: _onLeafTap,
                  onLeafLongPressStart: _onLeafLongPressStart,
                  onLeafLongPressMove: _onLeafLongPressMove,
                  onLeafLongPressEnd: _onLeafLongPressEnd,
                  leafLongPressEligible: _leafLongPressEligible,
                ),
              );
            },
          ),
        ),
        ?_emptySearchOverlay(),
        ?_stickySearchOverlay(),
        if (showStrip)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[
                _stripOffset,
                _stripShadowVisible,
                _categoryIndex,
              ]),
              builder: (context, _) => Transform.translate(
                offset: Offset(0, _stripOffset.value),
                child: EmojiCategoryStripOverlay(
                  tabs: stripTabs,
                  selectedIndex: _categoryIndex.value.clamp(
                    0,
                    stripTabs.length - 1,
                  ),
                  onSelect: jumpToSection,
                  shadowVisible: _stripShadowVisible.value,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// --- Private models ---------------------------------------------------------

/// Pre-resolved grid cell — skin-tone / display work happens when sections
/// rebuild (data / prefs), not inside item builders.
@immutable
class _Cell {
  const _Cell({
    required this.pickGlyph,
    required this.displayGlyph,
    required this.supportsSkinTone,
  });

  final String pickGlyph;
  final String displayGlyph;
  final bool supportsSkinTone;
}

/// Clips painting below [top] (Telegram `emojiContainer.drawChild` top edge).
final class _TopEdgeClipper extends CustomClipper<Rect> {
  _TopEdgeClipper(this.top);

  final double top;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, top, size.width, size.height);

  @override
  bool shouldReclip(covariant _TopEdgeClipper oldClipper) =>
      oldClipper.top != top;
}

/// Alias for embedding the grid outside [KeyboardPanel].
typedef EmojiGridView = EmojiPage;

import 'dart:async';
import 'dart:math' as math;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/src/menu/catalog_context_menu.dart';
import 'package:panel_pages/src/pack_sheet/pack_sheet.dart';
import 'package:panel_pages/src/pack_sheet/pack_sheet_action.dart';
import 'package:panel_pages/src/pack_sheet/pack_sheet_drag.dart';
import 'package:panel_pages/src/pack_sheet/pack_sheet_frame.dart';
import 'package:panel_pages/src/policy/catalog_page_policy.dart';
import 'package:panel_pages/src/preview/catalog_content_preview.dart';
import 'package:panel_pages/src/preview/catalog_preview_mark.dart';
import 'package:panel_pages/src/preview/content_preview_item.dart';
import 'package:panel_pages/src/preview/content_preview_menu.dart';
import 'package:panel_pages/src/preview/content_preview_session.dart';
import 'package:panel_pages/src/snapshot/catalog_snapshot_builder.dart';
import 'package:panel_pages/src/theme/chrome_catalog_theme.dart';
import 'package:panel_shell/panel_shell.dart';

/// How a pack sheet lays its grid out: the part of a sheet that depends on
/// what it shows.
enum PackSheetGrid {
  /// One pack of stickers or masks: five columns of 82 tall rows.
  stickers,

  /// One pack of custom emoji: as many square columns as fit 45 wide.
  emoji,

  /// Several packs of custom emoji: each under its own header with an
  /// Add or Remove button, eight to a row and two rows at most.
  severalEmoji,
}

/// The pack sheet's body, shared by the sticker and the emoji sheet: it looks
/// the packs up, follows their install states in the library, and shows the
/// header, the grid and the bottom button. The kind-specific choices are
/// [grid]'s.
///
/// Internal: hosts use `StickerPackSheet` and `EmojiPackSheet`.
class PackSheetView extends StatefulWidget {
  /// The sheet of [packIds].
  const PackSheetView({
    required this.packIds,
    required this.grid,
    required this.packs,
    required this.library,
    required this.assets,
    required this.onEditsRequested,
    this.onPick,
    this.onUnavailable,
    this.links,
    this.previews,
    this.onLibraryEditRequested,
    this.previewEmoji,
    super.key,
  });

  /// The packs shown, in order.
  final List<PackId> packIds;

  /// How the grid is laid out.
  final PackSheetGrid grid;

  /// Where the packs are looked up.
  final PackSource packs;

  /// Read for the install states; never edited by the sheet.
  final ContentLibrary library;

  /// What the grid draws through.
  final AssetCacheScope assets;

  /// Asked to apply the edits of a button.
  final PackEditsRequested onEditsRequested;

  /// The user tapped an item, or null for a grid whose taps do nothing.
  final ValueChanged<PackSheetItem>? onPick;

  /// A pack could not be shown (not found, or its lookup failed); the sheet
  /// has closed and the host tells the user.
  final ValueChanged<PackLookup>? onUnavailable;

  /// Share and Copy Link, or null for no menu.
  final PackSheetLinks? links;

  /// The host's handle on content previews, or null for none: with it a
  /// sticker grid previews a held or tapped sticker (an emoji grid never
  /// does).
  final ContentPreviewController? previews;

  /// Asked for the preview's library edits (favourites), or null for none.
  final ValueChanged<LibraryEdit>? onLibraryEditRequested;

  /// An emoji drawn large above the card on touch, or null.
  final ContentKey? previewEmoji;

  // --- Metrics --------------------------------------------------------------

  /// The header band, 50 tall.
  static const double headerExtent = 50;

  /// The title: 20 bold.
  static const double titleSize = 20;

  /// The weight of every bold text of the sheet is the medium face (weight
  /// 500), not a bold one.
  static const FontWeight boldWeight = FontWeight.w500;

  /// The title's inset from either side.
  static const double titleInset = 18;

  /// The menu button: 40 square, 5 in from the top and the end edge.
  static const double menuButtonExtent = 40;

  /// The grabber: 36 x 4, radius 2.
  static const Size grabberSize = Size(36, 4);

  /// The header's shadow line: 48 below the header's top, one logical pixel
  /// tall.
  static const double shadowLineTop = 48;

  /// How long the shadow line takes to fade in or out (`setDuration(150)`).
  static const Duration shadowFade = Duration(milliseconds: 150);

  /// The row of a sticker pack.
  static const double stickerRowExtent = 82;

  /// The side a sticker is drawn at in its cell.
  static const double stickerExtent = 66;

  /// The narrowest emoji column.
  static const double emojiColumnWidth = 45;

  /// Columns of a pack among several.
  static const int severalColumns = 8;

  /// Items shown of each pack among several: two rows.
  static const int severalLimit = 16;

  /// The grid's side padding and its bottom padding.
  static const EdgeInsets gridPadding = EdgeInsets.fromLTRB(10, 0, 10, 8);

  /// The add button: 48 tall, 8 from every edge of its bar, fully rounded,
  /// on a 64 bar.
  static const double buttonExtent = 48;

  /// The margin around the filled add button.
  static const double buttonMargin = 8;

  /// The label of the bottom button: 14 bold.
  static const double buttonTextSize = 14;

  /// The preview emoji's side (140), and the gap between it and the card's
  /// top (20); it is drawn only while the card's top is at
  /// least both below the top of the screen (`y < sz + p` hides it).
  static const double previewEmojiExtent = 140;

  /// See [previewEmojiExtent].
  static const double previewEmojiGap = 20;

  /// How long the preview emoji takes to fade out (`AnimatedFloat` of 320
  /// ms on `EASE_OUT_QUINT`); it scales from 1 to 0.6 as it fades.
  static const Duration previewEmojiFade = Duration(milliseconds: 320);

  /// The tallest the grid is in a box under a pointer: 320 for stickers, 197
  /// for emoji.
  static double boxGridMaxHeight(PackSheetGrid grid) =>
      grid == PackSheetGrid.stickers ? 320 : 197;

  @override
  State<PackSheetView> createState() => _PackSheetViewState();
}

class _PackSheetViewState extends State<PackSheetView>
    with TickerProviderStateMixin {
  final _catalog = PanelCatalogController();
  // The grid's cells under an open preview: none pressed, the shown one
  // smaller.
  late final _mark = CatalogPreviewMark(
    leafAt: _catalog.leafAt,
    onChanged: () {
      if (mounted) setState(() {});
    },
  );
  final _snapshots = listen.ValueNotifier<CatalogSnapshot>(
    const CatalogSnapshot.empty(),
  );
  late final _builder = CatalogSnapshotBuilder(policy: _policyFor());
  late final List<listen.ValueListenable<List<PackId>>> _states = [
    for (final kind in PackKind.values) ...[
      widget.library.installedPacks(kind),
      widget.library.archivedPacks(kind),
    ],
  ];
  final _menu = CatalogContextMenuController();
  ContentPreviewSession? _session;
  PointerDeviceKind _lastKind = PointerDeviceKind.touch;
  var _closed = false;

  /// The grid's scroll offset, which the card's top, its background and the
  /// headers over the grid follow; the rest of the sheet does not rebuild.
  final _offset = ValueNotifier<double>(0);
  late final StreamSubscription<PanelCatalogScrollEvent> _scrolls;

  /// How far an emoji card's background has closed over the status bar, over 350 ms on an ease-out quint.
  late final _closing = AnimationController(vsync: this);

  /// The frame of the last build, which the offset is read against.
  PackSheetFrame _frame = const PackSheetFrame.fixed(0);

  /// Where the box's top was on the screen at the last build.
  double _boxTop = 0;

  /// The preview emoji's alpha: 1 while it shows, faded to 0 once hidden,
  /// and never shown again (`previewImageVisible` only turns false).
  late final _previewAlpha = AnimationController(
    vsync: this,
    value: widget.previewEmoji == null ? 0 : 1,
  );
  var _previewHidden = false;
  Animation<double>? _routeAnimation;

  /// The pack a sheet of several opened on its own by a tap on one of its
  /// items, or null.
  PackId? _alone;

  List<PackId> get _shown => switch (_alone) {
    final id? => [id],
    null => widget.packIds,
  };

  PackSheetGrid get _grid => _alone == null ? widget.grid : PackSheetGrid.emoji;

  bool get _isEmoji => _grid != PackSheetGrid.stickers;

  @override
  void initState() {
    super.initState();
    widget.packs.changes.addListener(_changed);
    for (final list in _states) {
      list.addListener(_changed);
    }
    for (final id in widget.packIds) {
      // The answer arrives through [changes]; a failure is an answer.
      widget.packs.lookup(id).ignore();
    }
    _scrolls = _catalog.events.listen((event) {
      switch (event) {
        case PanelCatalogOffsetChanged(:final offset):
          _offset.value = offset;
          _followStatusBar();
          _checkPreviewRoom();
        // `onScrolled` while `scrollingByUser`: the user moved the grid.
        case PanelCatalogUserDragStart():
          _hidePreview();
        case _:
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  @override
  void dispose() {
    widget.packs.changes.removeListener(_changed);
    for (final list in _states) {
      list.removeListener(_changed);
    }
    // Before the session: its closing would ask a defunct state to rebuild.
    _mark.dispose();
    _session?.cancel();
    _scrolls.cancel().ignore();
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _previewAlpha.dispose();
    _menu.dispose();
    _catalog.dispose();
    _snapshots.dispose();
    _offset.dispose();
    _closing.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (identical(animation, _routeAnimation)) return;
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = animation?..addStatusListener(_onRouteStatus);
  }

  // The sheet is going, however it was closed (`dismiss` hides it).
  void _onRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse) _hidePreview();
  }

  void _hidePreview() {
    if (_previewHidden || widget.previewEmoji == null || !mounted) return;
    _previewHidden = true;
    final speed = ChromeMotionScope.maybeOf(context)?.speed;
    _previewAlpha.animateTo(
      0,
      duration:
          speed?.scale(PackSheetView.previewEmojiFade) ??
          PackSheetView.previewEmojiFade,
      curve: Curves.easeOutQuint,
    );
  }

  // `if (y < sz + p) previewImageVisible = false`: no room above the card's
  // background, and it goes for good.
  void _checkPreviewRoom() {
    if (_previewHidden || widget.previewEmoji == null) return;
    final top =
        _boxTop +
        _frame
            .emojiBackdrop(_frame.cardTopAt(_offset.value), _closing.value)
            .top;
    if (top <
        PackSheetView.previewEmojiExtent + PackSheetView.previewEmojiGap) {
      _hidePreview();
    }
  }

  void _changed() {
    if (!mounted || _closed) return;
    for (final id in _shown) {
      if (widget.packs.peek(id) case final lookup
          when lookup is PackLookup$NotFound || lookup is PackLookup$Failed) {
        _close();
        widget.onUnavailable?.call(lookup);
        return;
      }
    }
    setState(() {});
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _hidePreview();
    Navigator.maybeOf(context)?.maybePop();
  }

  /// The packs found so far, in order, or null while any is still loading.
  List<Pack>? get _found {
    final found = <Pack>[];
    for (final id in _shown) {
      if (widget.packs.peek(id) case PackLookup$Found(:final pack)) {
        found.add(pack);
      } else {
        return null;
      }
    }
    return found;
  }

  _PackSheetGridPolicy _policyFor() => _PackSheetGridPolicy(grid: _grid);

  void _publish(List<Pack> packs) {
    _builder.policy = _policyFor();
    final snapshot = _builder.build([
      for (final pack in packs)
        _grid == PackSheetGrid.severalEmoji ? _limited(pack) : pack.collection,
    ], strings: ChromeStringsScope.panelOf(context));
    // Published after the frame: the viewport listens and repaints itself.
    _snapshots.value = snapshot;
  }

  static Collection _limited(Pack pack) {
    final collection = pack.collection;
    return Collection(
      id: collection.id,
      metadata: collection.metadata,
      contents: CollectionContents.loaded([
        for (final item in pack.items.take(PackSheetView.severalLimit))
          CollectionItem.described(item),
      ]),
    );
  }

  PackSheetItem? _itemOf(CatalogLeafHit hit) {
    final collection = _builder.collectionOf(hit.sectionId);
    if (collection == null) return null;
    final packs = _found ?? const <Pack>[];
    for (final pack in packs) {
      if (pack.collectionId == collection.id && hit.index < pack.count) {
        return (item: pack.items[hit.index], pack: pack);
      }
    }
    return null;
  }

  // An emoji card's background closes over the status bar once its top
  // reaches it, and opens again when it leaves: animated, not tied to the
  // offset (`statusBarT` is an `AnimatedFloat`).
  void _followStatusBar() {
    if (!_isEmoji) return;
    final target = _frame.closesAt(_frame.cardTopAt(_offset.value)) ? 1.0 : 0.0;
    if (_closing.value == target && !_closing.isAnimating) return;
    final speed = ChromeMotionScope.maybeOf(context)?.speed;
    _closing.animateTo(
      target,
      duration: speed?.scale(_statusBarMorph) ?? _statusBarMorph,
      curve: Curves.easeOutQuint,
    );
  }

  static const Duration _statusBarMorph = Duration(milliseconds: 350);

  // --- Interaction ----------------------------------------------------------

  void _onTap(CatalogLeafHit hit) {
    final item = _itemOf(hit);
    if (item == null) return;
    if (widget.grid == PackSheetGrid.severalEmoji && _alone == null) {
      setState(() => _alone = item.pack.id);
      return;
    }
    // A tap on a sticker opens its preview with the menu at once.
    if (_preview case final preview?) {
      _replaceSession(
        ContentPreviewSession.show(
          context: context,
          item: preview.itemOf(hit)!,
          assets: widget.assets,
          actions: preview.actions,
          library: preview.controller.library,
          kind: _lastKind,
          openMenu: true,
          controller: preview.controller,
          itemAt: _itemAt(preview),
        ),
        hit,
      );
      return;
    }
    _pick(item);
  }

  // The sheet goes and the host sends or inserts the pick.
  void _pick(PackSheetItem item) {
    final pick = widget.onPick;
    if (pick == null) return;
    _close();
    pick(item);
  }

  /// The preview of the grid, or null where nothing is previewed: an emoji
  /// grid, or no controller.
  CatalogContentPreview? get _preview => switch (widget.previews) {
    final controller? when _grid == PackSheetGrid.stickers =>
      CatalogContentPreview(
        controller: controller,
        assets: widget.assets,
        // Send only when opened for a composer; View Pack never, the pack is
        // open.
        actions: ContentPreviewActions(
          send: widget.onPick == null ? null : _sendPreviewed,
          editLibrary: widget.onLibraryEditRequested,
        ),
        inRecents: (_) => false,
        packOf: (hit) => _itemOf(hit)?.pack.id,
      ),
    _ => null,
  };

  void _sendPreviewed(ContentPreviewItem previewed) {
    for (final pack in _found ?? const <Pack>[]) {
      for (final item in pack.items) {
        if (item.key == previewed.key) {
          _pick((item: item, pack: pack));
          return;
        }
      }
    }
  }

  ContentPreviewItem? Function(Offset) _itemAt(CatalogContentPreview preview) =>
      (global) => switch (_mark.leafAt(global)) {
        final hit? => preview.itemOf(hit),
        null => null,
      };

  void _replaceSession(ContentPreviewSession? session, [CatalogLeafHit? hit]) {
    _session?.cancel();
    _session = session;
    switch ((session, hit)) {
      case (final session?, final hit?):
        _mark.follow(session, hit);
      case _:
        _mark.clear();
    }
  }

  // A right-click on a sticker opens the preview's items as a context menu,
  // as on the panel's grid.
  void _onSecondaryTap(CatalogLeafHit hit, Offset globalPosition) {
    final preview = _preview;
    if (preview == null) return;
    final entries = preview.entriesOf(hit, ChromeStringsScope.panelOf(context));
    if (entries.isEmpty) return;
    _replaceSession(null);
    _menu.show(
      globalPosition: globalPosition,
      entries: entries,
      onSelected: (id) => preview.perform(hit, id),
    );
  }

  // A pack's own button among several toggles it and leaves the sheet up.
  void _togglePack(Pack pack) {
    if (PackSheetAction.of([pack], widget.library.installStateOf)
        case final action?) {
      widget.onEditsRequested(action.requests);
    }
  }

  void _onButton(PackSheetAction action) {
    // The sheet is dismissed, then the set is toggled.
    _close();
    widget.onEditsRequested(action.requests);
  }

  bool _longPressEligible(CatalogLeafHit hit) =>
      _preview?.previews(hit) ?? false;

  void _onLongPressStart(CatalogLeafHit hit, LongPressStartDetails details) {
    final preview = _preview;
    if (preview == null) return;
    _replaceSession(
      preview.begin(context, hit, kind: _lastKind, leafAt: _mark.leafAt),
      hit,
    );
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final arrangement = PanelArrangementScope.of(context);
    final strings = ChromeStringsScope.packSheetOf(context);
    final palette = ChromeThemeScope.of(context).palette;
    final packs = _found;
    final action = switch (packs) {
      final packs? => PackSheetAction.of(packs, widget.library.installStateOf),
      null => null,
    };
    if (packs != null) _publish(packs);
    final touch = arrangement == PanelArrangement.touch;
    // The bottom sheet's drag owner; none for the box under a pointer.
    final sheetDrag = PackSheetDragScope.maybeOf(context);
    final media = MediaQuery.of(context);
    final width = touch ? media.size.width : PackSheet.boxWidth;
    final gridExtent = _gridExtent(packs, width);
    final buttonBar = switch (action) {
      null => 0.0,
      PackSheetAction(removes: true) => PackSheetView.buttonExtent,
      _ => PackSheetView.buttonExtent + 2 * PackSheetView.buttonMargin,
    };
    final bottomInset = touch ? media.padding.bottom : 0.0;
    final frame = _frame = touch
        ? PackSheetFrame.touch(
            screen: media.size,
            statusBar: media.padding.top,
            content:
                PackSheetView.headerExtent +
                gridExtent +
                buttonBar +
                bottomInset,
            grid: _grid,
          )
        : PackSheetFrame.fixed(
            PackSheetView.headerExtent +
                math.min(gridExtent, PackSheetView.boxGridMaxHeight(_grid)) +
                buttonBar,
          );
    final gridTop = frame.topInset + PackSheetView.headerExtent;
    final gridBottom = buttonBar + bottomInset;
    final title = switch (packs) {
      [final pack] => pack.title,
      _ => '',
    };
    final grid = packs == null
        ? const Center(child: _Spinner())
        : Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) => _lastKind = event.kind,
            child: PanelCatalogViewport(
              snapshots: _snapshots,
              assets: widget.assets,
              controller: _catalog,
              padding: PackSheetView.gridPadding.copyWith(
                top: PackSheetView.gridPadding.top + frame.lead,
              ),
              onLeafTap: _onTap,
              onLeafSecondaryTap: _preview == null ? null : _onSecondaryTap,
              leafLongPressEligible: _longPressEligible,
              leafLongPressDelay: (_, kind) =>
                  CatalogContentPreview.delayOf(kind),
              onLeafLongPressStart: _onLongPressStart,
              onLeafLongPressMove: (_, details) => _session?.update(details),
              onLeafLongPressEnd: (_, details) => _session?.end(details),
              leafPreview: _mark.value,
              overscrollSink: sheetDrag,
            ),
          );
    final header = _Header(
      title: title,
      close: !touch,
      links: switch ((widget.links, packs)) {
        (final links?, [final pack]) => switch (links.linkOf(pack.id)) {
          final link? => (links, link),
          null => null,
        },
        _ => null,
      },
    );
    final severalHeaders = switch (packs) {
      final packs? when _grid == PackSheetGrid.severalEmoji => [
        for (final (index, top) in _sectionTops(packs, width).indexed)
          (top: top, pack: packs[index]),
      ],
      _ => const <({double top, Pack pack})>[],
    };
    // Where the box's top is on the screen: the grabber fades as the card
    // nears the status bar.
    final boxTop = _boxTop = touch ? media.size.height - frame.height : 0.0;
    final previewEmoji = touch ? widget.previewEmoji : null;
    if (previewEmoji != null && !_previewHidden) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkPreviewRoom());
    }
    final body = ListenableBuilder(
      listenable: Listenable.merge([_offset, _closing, _previewAlpha]),
      child: grid,
      builder: (context, grid) {
        final offset = _offset.value;
        final cardTop = frame.cardTopAt(offset);
        final backdrop = _isEmoji
            ? frame.emojiBackdrop(cardTop, _closing.value)
            : frame.stickersBackdrop(cardTop);
        final grabber = _isEmoji
            ? (
                // Lower by 10; alpha is `y / 20`, clamped, before it.
                top: backdrop.top + 10,
                alpha: ((boxTop + backdrop.top) / 20).clamp(0.0, 1.0),
              )
            : (
                // 6 below the card; alpha over 16 above the status bar.
                top: cardTop + 6,
                alpha: ((boxTop + cardTop + 6 - frame.topInset) / 16).clamp(
                  0.0,
                  1.0,
                ),
              );
        final previewAlpha = _previewAlpha.value;
        return Stack(
          // The preview emoji stands above the box.
          clipBehavior: Clip.none,
          children: [
            if (previewEmoji != null && previewAlpha > 0)
              Positioned(
                left: (width - PackSheetView.previewEmojiExtent) / 2,
                top:
                    backdrop.top -
                    PackSheetView.previewEmojiGap -
                    PackSheetView.previewEmojiExtent,
                width: PackSheetView.previewEmojiExtent,
                height: PackSheetView.previewEmojiExtent,
                child: _PreviewEmoji(
                  content: previewEmoji,
                  assets: widget.assets,
                  alpha: previewAlpha,
                ),
              ),
            Positioned.fill(
              child: CustomPaint(
                painter: _BackdropPainter(
                  top: backdrop.top,
                  radius: touch ? backdrop.radius : 0,
                  color: palette.surface,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: gridTop,
              bottom: gridBottom,
              child: grid!,
            ),
            if (severalHeaders.isNotEmpty)
              Positioned(
                left: PackSheetView.gridPadding.left,
                right: PackSheetView.gridPadding.right,
                top: gridTop,
                bottom: gridBottom,
                child: ClipRect(
                  child: Stack(
                    children: [
                      for (final (:top, :pack) in severalHeaders)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: frame.lead + top - offset,
                          height: _PackHeader.extent,
                          child: _PackHeader(
                            key: ValueKey(pack.id),
                            pack: pack,
                            installed:
                                widget.library.installStateOf(pack.id) ==
                                PackInstallState.installed,
                            onToggle: () => _togglePack(pack),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            // A press above the card closes the sheet.
            if (cardTop > 0)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: cardTop,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => _close(),
                ),
              ),
            if (touch)
              Positioned(
                top: grabber.top,
                left: 0,
                right: 0,
                child: Center(
                  child: _Grabber(
                    color: palette.onSurfaceMuted.withValues(
                      alpha: palette.onSurfaceMuted.a * grabber.alpha,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: cardTop,
              height: PackSheetView.headerExtent,
              child: switch (sheetDrag) {
                final sink? => _HeaderDrag(
                  sink: sink,
                  grid: _catalog,
                  child: header,
                ),
                null => header,
              },
            ),
            Positioned(
              left: 0,
              right: 0,
              top: cardTop + PackSheetView.shadowLineTop,
              height: 1,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: frame.scrolledUnderHeaderAt(offset) ? 1 : 0,
                  duration:
                      ChromeMotionScope.maybeOf(
                        context,
                      )?.speed.scale(PackSheetView.shadowFade) ??
                      PackSheetView.shadowFade,
                  child: ColoredBox(color: palette.separator),
                ),
              ),
            ),
            if (action != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: bottomInset,
                child: _BottomButton(
                  label: action.labelIn(strings),
                  removes: action.removes,
                  onPressed: () => _onButton(action),
                ),
              ),
          ],
        );
      },
    );
    return ChromeCatalogTheme(
      child: CatalogContextMenuHost(
        host: null,
        controller: _menu,
        child: SizedBox(
          height: frame.height,
          child: touch
              ? body
              : ClipRRect(
                  borderRadius: BorderRadius.circular(
                    PackSheetFrame.stickersRadius,
                  ),
                  child: body,
                ),
        ),
      ),
    );
  }

  // The grid's height for [packs] across [width]: at least three rows of
  // stickers or two of emoji while loading or for a short pack
  // (`Math.max(isEmoji() ? 2 : 3, rows)`).
  double _gridExtent(List<Pack>? packs, double width) {
    final usable = width - PackSheetView.gridPadding.horizontal;
    final pad = PackSheetView.gridPadding.bottom;
    switch (_grid) {
      case PackSheetGrid.stickers:
        final count = packs?.firstOrNull?.count ?? 0;
        final rows = math.max(3, (count / 5).ceil());
        return rows * PackSheetView.stickerRowExtent + pad;
      case PackSheetGrid.emoji:
        final columns = math.max(
          1,
          (usable / PackSheetView.emojiColumnWidth).floor(),
        );
        final count = packs?.firstOrNull?.count ?? 0;
        final rows = math.max(2, (count / columns).ceil());
        return rows * (usable / columns) + pad;
      case PackSheetGrid.severalEmoji:
        if (packs == null) {
          return 2 * usable / PackSheetView.severalColumns + pad;
        }
        final last = packs.lastOrNull;
        if (last == null) return pad;
        return _sectionTops(packs, width).last +
            _severalSectionExtent(last, usable) +
            pad;
    }
  }

  // Where each pack's header is in a grid of several, from the grid's
  // content top: each section is its 56 header and its rows of eight.
  static List<double> _sectionTops(List<Pack> packs, double width) {
    final usable = width - PackSheetView.gridPadding.horizontal;
    var top = PackSheetView.gridPadding.top;
    final tops = <double>[];
    for (final pack in packs) {
      tops.add(top);
      top += _severalSectionExtent(pack, usable);
    }
    return tops;
  }

  static double _severalSectionExtent(Pack pack, double usable) {
    final shown = math.min(pack.count, PackSheetView.severalLimit);
    return _PackHeader.extent +
        (shown / PackSheetView.severalColumns).ceil() *
            (usable / PackSheetView.severalColumns);
  }
}

// --- Grid policy -------------------------------------------------------------

/// The geometry of a sheet's grid, as the catalogue's snapshot builder asks
/// for it. A pack's header among several is a blank band here: the sheet
/// draws it over the grid ([_PackHeader]), with what the catalogue's
/// headers cannot show (its count, a pill that cross-fades).
final class _PackSheetGridPolicy extends CatalogPagePolicy {
  _PackSheetGridPolicy({required this.grid});

  final PackSheetGrid grid;

  @override
  String titleOf(Collection collection, PanelStrings strings) => '';

  @override
  SectionLayout? layoutOf(
    Collection collection, {
    PanelArrangement arrangement = PanelArrangement.touch,
  }) => switch (grid) {
    PackSheetGrid.stickers => const SectionLayout.grid(
      spanCount: 5,
      cellExtent: PackSheetView.stickerRowExtent,
      glyphExtent: PackSheetView.stickerExtent,
      headerExtent: 0,
    ),
    PackSheetGrid.emoji => const SectionLayout.grid(
      desiredCellWidth: PackSheetView.emojiColumnWidth,
      cellAspect: 1,
      headerExtent: 0,
    ),
    PackSheetGrid.severalEmoji => const SectionLayout.grid(
      spanCount: PackSheetView.severalColumns,
      cellAspect: 1,
      headerExtent: _PackHeader.extent,
    ),
  };

  @override
  CatalogContentBox? contentBoxOf(Collection collection) =>
      grid == PackSheetGrid.stickers ? CatalogContentBox.glyph : null;
}

// --- Parts -------------------------------------------------------------------

/// The card's background from [top] down, its top corners rounded by
/// [radius]: the sheet's own drawing, so it can follow the grid and reach
/// over the status bar.
class _BackdropPainter extends CustomPainter {
  const _BackdropPainter({
    required this.top,
    required this.radius,
    required this.color,
  });

  final double top;
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromLTRBAndCorners(
        0,
        top,
        size.width,
        size.height,
        topLeft: Radius.circular(radius),
        topRight: Radius.circular(radius),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_BackdropPainter oldDelegate) =>
      oldDelegate.top != top ||
      oldDelegate.radius != radius ||
      oldDelegate.color != color;
}

/// The emoji the sheet was opened for, over the dim above the card: it fades
/// at [alpha] and shrinks to 0.6 with it (`.6f + .4f * alpha`).
class _PreviewEmoji extends StatelessWidget {
  const _PreviewEmoji({
    required this.content,
    required this.assets,
    required this.alpha,
  });

  final ContentKey content;
  final AssetCacheScope assets;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    const side = PackSheetView.previewEmojiExtent;
    final density = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return IgnorePointer(
      child: Opacity(
        opacity: alpha.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.6 + 0.4 * alpha,
          child: ContentView(
            content: content,
            scope: assets,
            preset: AssetPreset(
              size: const Size.square(side),
              spec: AssetSpec.atDensity(
                logicalWidth: side,
                logicalHeight: side,
                devicePixelRatio: density,
              ),
              profile: const AssetProfile(animate: true),
            ),
          ),
        ),
      ),
    );
  }
}

/// The grabber (`sheet_scrollUp`), its alpha already in [color].
class _Grabber extends StatelessWidget {
  const _Grabber({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: PackSheetView.grabberSize.width,
      height: PackSheetView.grabberSize.height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.close,
    required this.links,
  });

  final String title;
  final bool close;
  final (PackSheetLinks, Uri)? links;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.of(context).palette;
    final strings = ChromeStringsScope.packSheetOf(context);
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsetsDirectional.only(
              start: PackSheetView.titleInset,
              end: PackSheetView.titleInset + PackSheetView.menuButtonExtent,
              top: 6,
              bottom: 6,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.onSurface,
                  fontSize: PackSheetView.titleSize,
                  fontWeight: PackSheetView.boldWeight,
                ),
              ),
            ),
          ),
        ),
        PositionedDirectional(
          top: 5,
          end: 5,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (links case (final links, final link))
                _MenuButton(links: links, link: link),
              if (close)
                _IconButton(
                  label: strings.closeAction,
                  painter: _CrossPainter(palette.onSurfaceMuted),
                  onPressed: () => Navigator.maybeOf(context)?.maybePop(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The header band as a handle on the sheet: a vertical drag anywhere on it
/// (the grabber, the title, the empty band) goes to the sheet's drag owner
/// through [sink], before the grid under it can take the press.
///
/// The owner moves first, as it does for a drag on the grid at its top: a
/// drag down pulls the sheet, a drag up first undoes the pull, and what the
/// owner declines raises the card by scrolling [grid]. The header's buttons
/// keep their taps; a drag that starts on one still moves the sheet.
class _HeaderDrag extends StatelessWidget {
  const _HeaderDrag({
    required this.sink,
    required this.grid,
    required this.child,
  });

  final CatalogOverscrollSink sink;
  final PanelCatalogController grid;
  final Widget child;

  // A mouse never drags the sheet, as it never drags the grid.
  static const Set<PointerDeviceKind> _devices = {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
  };

  void _update(DragUpdateDetails details) {
    final dy = details.primaryDelta ?? details.delta.dy;
    final rest = dy - sink.onDelta(dy);
    // Finger up reveals what is below: the grid's offset grows.
    if (rest != 0) grid.scrollBy(-rest);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    // A handle for the finger only: the sheet's semantics close it through
    // the barrier, and scroll actions here would stand over the header's.
    excludeFromSemantics: true,
    supportedDevices: _devices,
    onVerticalDragStart: (_) => sink.onStart?.call(),
    onVerticalDragUpdate: _update,
    onVerticalDragEnd: (details) => sink.onEnd(details.primaryVelocity ?? 0),
    onVerticalDragCancel: () => sink.onEnd(0),
    child: child,
  );
}

/// The header of one pack among several (not single): its title, how many emoji it holds, and a button that adds
/// it (a filled pill) or removes it (accent text), which cross-fade with a
/// scale as the pack's install state changes.
class _PackHeader extends StatefulWidget {
  const _PackHeader({
    required this.pack,
    required this.installed,
    required this.onToggle,
    super.key,
  });

  /// The header's band.
  static const double extent = 56;

  /// The title: 17 bold, 10 down, 8 in.
  static const double titleSize = 17;

  /// The count: 13 in the muted colour, 31.66 down, 8 in.
  static const double subtitleSize = 13;

  /// The button: 28 tall, 15.66 down, 5.66 from the end; the title stops 16
  /// short of its far edge.
  static const double buttonExtent = 28;

  /// How long the buttons take to trade places (`setDuration(250)`,
  /// `EASE_OUT_QUINT`).
  static const Duration toggleDuration = Duration(milliseconds: 250);

  final Pack pack;
  final bool installed;
  final VoidCallback onToggle;

  @override
  State<_PackHeader> createState() => _PackHeaderState();
}

class _PackHeaderState extends State<_PackHeader>
    with SingleTickerProviderStateMixin {
  // 0 shows Add, 1 shows Remove (`toggleT`).
  late final _toggle = AnimationController(
    vsync: this,
    value: widget.installed ? 1 : 0,
  );

  @override
  void didUpdateWidget(_PackHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.installed == widget.installed) return;
    final speed = ChromeMotionScope.maybeOf(context)?.speed;
    _toggle.animateTo(
      widget.installed ? 1 : 0,
      duration:
          speed?.scale(_PackHeader.toggleDuration) ??
          _PackHeader.toggleDuration,
      curve: Curves.easeOutQuint,
    );
  }

  @override
  void dispose() {
    _toggle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.of(context).palette;
    final strings = ChromeStringsScope.packSheetOf(context);
    final installed = widget.installed;
    Widget faded(Widget child, {required bool remove}) => AnimatedBuilder(
      animation: _toggle,
      child: child,
      builder: (context, child) {
        final shown = remove ? _toggle.value : 1 - _toggle.value;
        // At rest only one button is there; both while they trade places.
        if (shown <= 0) return const SizedBox.shrink();
        return Opacity(
          opacity: shown.clamp(0.0, 1.0),
          child: Transform.scale(scale: shown, child: child),
        );
      },
    );
    TextStyle label(Color color) => TextStyle(
      color: color,
      fontSize: PackSheetView.buttonTextSize,
      fontWeight: PackSheetView.boldWeight,
    );
    final add = _HeaderButton(
      enabled: !installed,
      onPressed: widget.onToggle,
      padding: 18,
      color: palette.accent,
      child: Text(strings.addPackAction, style: label(palette.onAccent)),
    );
    final remove = _HeaderButton(
      enabled: installed,
      onPressed: widget.onToggle,
      padding: 12,
      child: Text(strings.removePackAction, style: label(palette.accent)),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Stack(
            children: [
              PositionedDirectional(
                start: 8,
                end: 0,
                top: 10,
                child: Text(
                  widget.pack.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.onSurface,
                    fontSize: _PackHeader.titleSize,
                    fontWeight: PackSheetView.boldWeight,
                  ),
                ),
              ),
              PositionedDirectional(
                start: 8,
                end: 0,
                top: 31.66,
                child: Text(
                  strings.emojiCount(widget.pack.count),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.onSurfaceMuted,
                    fontSize: _PackHeader.subtitleSize,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16 - 5.66),
        Padding(
          padding: const EdgeInsets.only(top: 15.66),
          child: Stack(
            alignment: AlignmentDirectional.centerEnd,
            children: [faded(add, remove: false), faded(remove, remove: true)],
          ),
        ),
        const SizedBox(width: 5.66),
      ],
    );
  }
}

/// One of a pack header's buttons: [child] in a 28 tall band, [padding] in
/// from either side, on a fully rounded [color] fill when there is one.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.enabled,
    required this.onPressed,
    required this.padding,
    required this.child,
    this.color,
  });

  final bool enabled;
  final VoidCallback onPressed;
  final double padding;
  final Color? color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    return IgnorePointer(
      // The one faded out keeps its place but takes no press.
      ignoring: !enabled,
      child: Semantics(
        button: true,
        excludeSemantics: !enabled,
        child: ChromeInk(
          color: switch (color) {
            null => ChromeCatalogTheme.pressInkOf(palette),
            _ => palette.onAccent.withAlpha(0x24),
          },
          hoverColor: ChromeCatalogTheme.hoverWashOf(palette),
          borderRadius: BorderRadius.circular(_PackHeader.buttonExtent / 2),
          onTap: onPressed,
          child: Container(
            height: _PackHeader.buttonExtent,
            padding: EdgeInsets.symmetric(horizontal: padding),
            alignment: Alignment.center,
            decoration: switch (color) {
              final color? => BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(
                  _PackHeader.buttonExtent / 2,
                ),
              ),
              null => null,
            },
            child: child,
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.label,
    required this.painter,
    required this.onPressed,
  });

  final String label;
  final CustomPainter painter;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: ChromeInk(
      color: ChromeCatalogTheme.pressInkOf(ChromeThemeScope.paletteOf(context)),
      hoverColor: ChromeCatalogTheme.hoverWashOf(
        ChromeThemeScope.paletteOf(context),
      ),
      circleRadius: PackSheetView.menuButtonExtent / 2,
      onTap: onPressed,
      child: SizedBox.square(
        dimension: PackSheetView.menuButtonExtent,
        child: CustomPaint(painter: painter),
      ),
    ),
  );
}

class _MenuButton extends StatefulWidget {
  const _MenuButton({required this.links, required this.link});

  final PackSheetLinks links;
  final Uri link;

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  final _menu = MenuController();

  static const _share = 'share';
  static const _copy = 'copy';

  void _choose(String id) {
    _menu.close();
    switch (id) {
      case _share:
        widget.links.onShare(widget.link);
      case _copy:
        widget.links.onCopy(widget.link);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ChromeStringsScope.packSheetOf(context);
    final palette = ChromeThemeScope.of(context).palette;
    return RawMenuAnchor(
      controller: _menu,
      overlayBuilder: (context, info) => Positioned(
        top: info.anchorRect.bottom,
        right: math.max(0, info.overlaySize.width - info.anchorRect.right),
        // Hangs from the button's end corner, with the appear motion.
        child: ChromeAppear(
          origin: Alignment.topRight,
          rows: 2,
          borderRadius: BorderRadius.circular(CatalogContextMenuPanel.radius),
          revealColor: palette.surfaceRaised,
          shadows: CatalogContextMenuPanel.shadowsOf(palette),
          child: CatalogContextMenuPanel(
            entries: [
              CatalogMenuEntry.item(id: _share, label: strings.shareAction),
              CatalogMenuEntry.item(id: _copy, label: strings.copyLinkAction),
            ],
            onChoose: _choose,
            onDismiss: _menu.close,
            shadowed: false,
          ),
        ),
      ),
      child: _IconButton(
        label: strings.moreOptionsLabel,
        painter: _DotsPainter(palette.onSurfaceMuted),
        onPressed: () => _menu.isOpen ? _menu.close() : _menu.open(),
      ),
    );
  }
}

class _BottomButton extends StatelessWidget {
  const _BottomButton({
    required this.label,
    required this.removes,
    required this.onPressed,
  });

  final String label;
  final bool removes;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.of(context).palette;
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: removes ? palette.destructive : palette.onAccent,
        fontSize: PackSheetView.buttonTextSize,
        fontWeight: PackSheetView.boldWeight,
      ),
    );
    // Added: a filled pill inset 8 (`featuredStickers_addButton`); removed:
    // a flat bar the full width, its text in the attention colour
    // (`text_RedBold`).
    return Semantics(
      button: true,
      child: removes
          ? ChromeInk(
              color: ChromeCatalogTheme.pressInkOf(palette),
              hoverColor: ChromeCatalogTheme.hoverWashOf(palette),
              onTap: onPressed,
              child: SizedBox(
                height: PackSheetView.buttonExtent,
                child: Center(child: text),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(PackSheetView.buttonMargin),
              child: ChromeInk(
                color: palette.onAccent.withAlpha(0x24),
                hoverColor: palette.onAccent.withAlpha(0x12),
                borderRadius: BorderRadius.circular(
                  PackSheetView.buttonExtent / 2,
                ),
                onTap: onPressed,
                child: Container(
                  height: PackSheetView.buttonExtent,
                  decoration: BoxDecoration(
                    color: palette.accent,
                    borderRadius: BorderRadius.circular(
                      PackSheetView.buttonExtent / 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: text,
                ),
              ),
            ),
    );
  }
}

/// `RadialProgressView`: an arc turning in the accent while the packs load.
class _Spinner extends StatefulWidget {
  const _Spinner();

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner>
    with SingleTickerProviderStateMixin {
  // `RadialProgressView` turns once a second; reduce motion stops it.
  static const _turnPeriod = Duration(seconds: 1);

  late final _turn = AnimationController(vsync: this, duration: _turnPeriod);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final speed = ChromeMotionScope.maybeOf(context)?.speed;
    if (speed == null || !speed.isInstant) {
      if (!_turn.isAnimating) _turn.repeat();
    } else {
      _turn.stop();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    // A busy region, not a button: nothing here takes input.
    container: true,
    child: SizedBox.square(
      dimension: 40,
      child: CustomPaint(
        painter: _ArcPainter(
          _turn,
          ChromeThemeScope.of(context).palette.accent,
        ),
      ),
    ),
  );
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.turn, this.color) : super(repaint: turn);

  final Animation<double> turn;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      (Offset.zero & size).deflate(4),
      turn.value * 2 * math.pi,
      math.pi * 1.5,
      false,
      pen,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter oldDelegate) => oldDelegate.color != color;
}

/// `ic_ab_other`: three dots in a column.
class _DotsPainter extends CustomPainter {
  const _DotsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final centre = size.center(Offset.zero);
    for (final dy in const [-6.0, 0.0, 6.0]) {
      canvas.drawCircle(centre.translate(0, dy), 2, paint);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter oldDelegate) => oldDelegate.color != color;
}

/// `ic_close_white`: two strokes crossing, stroked as one path so a
/// translucent colour covers the crossing once.
class _CrossPainter extends CustomPainter {
  const _CrossPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final box = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: 12,
      height: 12,
    );
    final cross = Path()
      ..moveTo(box.left, box.top)
      ..lineTo(box.right, box.bottom)
      ..moveTo(box.right, box.top)
      ..lineTo(box.left, box.bottom);
    canvas.drawPath(cross, pen);
  }

  @override
  bool shouldRepaint(_CrossPainter oldDelegate) => oldDelegate.color != color;
}

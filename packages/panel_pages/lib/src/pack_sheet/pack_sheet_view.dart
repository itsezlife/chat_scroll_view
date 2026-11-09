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
import 'package:panel_pages/src/policy/catalog_page_policy.dart';
import 'package:panel_pages/src/snapshot/catalog_snapshot_builder.dart';
import 'package:panel_pages/src/theme/chrome_catalog_theme.dart';
import 'package:panel_shell/panel_shell.dart';

/// How a pack sheet lays its grid out: the part of a sheet that depends on
/// what it shows.
enum PackSheetGrid {
  /// One pack of stickers or masks: five columns of `82` tall rows
  /// (`StickersAlert`: `stickersPerRow = 5`, `itemHeight = dp(82)`).
  stickers,

  /// One pack of custom emoji: as many square columns as fit `45` wide
  /// (`StickersAlert.isEmoji`: `width / dp(45)`).
  emoji,

  /// Several packs of custom emoji: each under its own header with an
  /// Add or Remove button, eight to a row and two rows at most
  /// (`EmojiPacksAlert`: 40 spans of 5, `limitCount` 16).
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
    this.longPress,
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

  /// The preview a long press opens, or null for none.
  final PackSheetLongPress? longPress;

  // --- Metrics --------------------------------------------------------------

  /// The header band: `StickersAlert`'s title view, 50 tall.
  static const double headerExtent = 50;

  /// The title: 20 bold (`titleTextView.setTextSize(20)`, `bold()`).
  static const double titleSize = 20;

  /// The title's inset from either side (`setPadding(dp(18), ...)`).
  static const double titleInset = 18;

  /// The menu button: 40 square, 5 in from the top and the end edge.
  static const double menuButtonExtent = 40;

  /// The grabber: 36 x 4, radius 2, 6 below the sheet's top edge.
  static const Size grabberSize = Size(36, 4);

  /// The top corners of the bottom sheet (`dp(12)`).
  static const double topRadius = 12;

  /// The row of a sticker pack (`dp(82)`).
  static const double stickerRowExtent = 82;

  /// The side a sticker is drawn at in its cell.
  static const double stickerExtent = 66;

  /// The narrowest emoji column (`dp(45)`).
  static const double emojiColumnWidth = 45;

  /// Columns of a pack among several (`EmojiPacksAlert`: 40 spans / 5).
  static const int severalColumns = 8;

  /// Items shown of each pack among several: two rows
  /// (`EmojiPacksAlert` `limitCount`, 16).
  static const int severalLimit = 16;

  /// The grid's side padding (`gridView.setPadding(dp(10), ..., dp(10),
  /// dp(8))`) and its bottom padding.
  static const EdgeInsets gridPadding = EdgeInsets.fromLTRB(10, 0, 10, 8);

  /// The add button: 48 tall, 8 from every edge of its bar, fully rounded
  /// (`createSimpleSelectorRoundRectDrawable(dp(24), ...)`), on a 64 bar.
  static const double buttonExtent = 48;

  /// The margin around the filled add button.
  static const double buttonMargin = 8;

  /// The label of the bottom button: 14 bold.
  static const double buttonTextSize = 14;

  /// The grid wraps its content while the sheet is under this share of the
  /// screen's height (`contentSize < height / 5 * 3.2`), and otherwise opens
  /// [partHeight] of it tall.
  static const double wrapLimit = 3.2 / 5;

  /// The share of the screen a tall sheet opens to: the grid's top padding is
  /// two fifths of the screen.
  static const double partHeight = 3 / 5;

  /// The tallest the grid is in a box under a pointer: the desktop client's
  /// `stickersMaxHeight` (320) for stickers, its emoji height (197) otherwise.
  static double boxGridMaxHeight(PackSheetGrid grid) =>
      grid == PackSheetGrid.stickers ? 320 : 197;

  @override
  State<PackSheetView> createState() => _PackSheetViewState();
}

class _PackSheetViewState extends State<PackSheetView> {
  final _catalog = PanelCatalogController();
  final _snapshots = listen.ValueNotifier<CatalogSnapshot>(
    const CatalogSnapshot.empty(),
  );
  late final _builder = CatalogSnapshotBuilder(policy: _policyFor(const []));
  late final List<listen.ValueListenable<List<PackId>>> _states = [
    for (final kind in PackKind.values) ...[
      widget.library.installedPacks(kind),
      widget.library.archivedPacks(kind),
    ],
  ];
  CatalogLongPressSession? _session;
  PointerDeviceKind _lastKind = PointerDeviceKind.touch;
  var _closed = false;

  /// The pack a sheet of several opened on its own by a tap on one of its
  /// items (`EmojiPacksAlert`: a tap opens that pack alone), or null.
  PackId? _alone;

  List<PackId> get _shown => switch (_alone) {
    final id? => [id],
    null => widget.packIds,
  };

  PackSheetGrid get _grid => _alone == null ? widget.grid : PackSheetGrid.emoji;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  @override
  void dispose() {
    widget.packs.changes.removeListener(_changed);
    for (final list in _states) {
      list.removeListener(_changed);
    }
    _session?.cancel();
    _catalog.dispose();
    _snapshots.dispose();
    super.dispose();
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

  _PackSheetGridPolicy _policyFor(
    List<Pack> packs, [
    PackSheetStrings? strings,
  ]) => _PackSheetGridPolicy(
    grid: _grid,
    installed: {
      for (final pack in packs)
        pack.id:
            widget.library.installStateOf(pack.id) ==
            PackInstallState.installed,
    },
    strings: strings,
  );

  void _publish(List<Pack> packs, PackSheetStrings strings) {
    _builder.policy = _policyFor(packs, strings);
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

  // --- Interaction ----------------------------------------------------------

  void _onTap(CatalogLeafHit hit) {
    final item = _itemOf(hit);
    if (item == null) return;
    if (widget.grid == PackSheetGrid.severalEmoji && _alone == null) {
      setState(() => _alone = item.pack.id);
      return;
    }
    final pick = widget.onPick;
    if (pick == null) return;
    // The sheet goes and the host sends or inserts (`StickersAlert`
    // `onStickerSelected` then `dismiss`, `EmojiPacksAlert` inserts and
    // dismisses).
    _close();
    pick(item);
  }

  void _onSectionAction(String sectionId, String actionId) {
    final collection = _builder.collectionOf(sectionId);
    final pack = (_found ?? const <Pack>[])
        .where((pack) => pack.collectionId == collection?.id)
        .firstOrNull;
    if (pack == null) return;
    // A pack's own button among several toggles it and leaves the sheet up.
    if (PackSheetAction.of([pack], widget.library.installStateOf)
        case final action?) {
      widget.onEditsRequested(action.requests);
    }
  }

  void _onButton(PackSheetAction action) {
    // `StickersAlert`: the sheet is dismissed, then the set is toggled.
    _close();
    widget.onEditsRequested(action.requests);
  }

  bool _longPressEligible(CatalogLeafHit hit) => widget.longPress != null;

  void _onLongPressStart(CatalogLeafHit hit, LongPressStartDetails details) {
    _session?.cancel();
    _session = null;
    final begin = widget.longPress;
    final item = _itemOf(hit);
    final cell = _catalog.leafBoundsOf(hit);
    final viewport = _catalog.viewportBounds;
    if (begin == null || item == null || cell == null || viewport == null) {
      return;
    }
    _session = begin(
      context,
      item,
      details,
      kind: _lastKind,
      cellBounds: cell,
      viewportBounds: viewport,
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
    if (packs != null) _publish(packs, strings);
    final touch = arrangement == PanelArrangement.touch;
    final media = MediaQuery.of(context);
    final width = touch ? media.size.width : PackSheet.boxWidth;
    final gridExtent = _gridExtent(packs, width);
    final buttonBar = switch (action) {
      null => 0.0,
      PackSheetAction(removes: true) => PackSheetView.buttonExtent,
      _ => PackSheetView.buttonExtent + 2 * PackSheetView.buttonMargin,
    };
    final content = PackSheetView.headerExtent + gridExtent + buttonBar;
    final height = touch
        ? (content < media.size.height * PackSheetView.wrapLimit
              ? content
              : media.size.height * PackSheetView.partHeight)
        : PackSheetView.headerExtent +
              math.min(gridExtent, PackSheetView.boxGridMaxHeight(_grid)) +
              buttonBar;
    final title = switch (packs) {
      [final pack] => pack.title,
      _ => '',
    };
    return ChromeCatalogTheme(
      child: Container(
        height: height + (touch ? media.padding.bottom : 0),
        padding: EdgeInsets.only(bottom: touch ? media.padding.bottom : 0),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: touch
              ? const BorderRadius.vertical(
                  top: Radius.circular(PackSheetView.topRadius),
                )
              : BorderRadius.circular(PackSheetView.topRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _Header(
              title: title,
              grabber: touch,
              close: !touch,
              links: switch ((widget.links, packs)) {
                (final links?, [final pack]) => switch (links.linkOf(pack.id)) {
                  final link? => (links, link),
                  null => null,
                },
                _ => null,
              },
            ),
            Expanded(
              child: packs == null
                  ? const Center(child: _Spinner())
                  : Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (event) => _lastKind = event.kind,
                      child: PanelCatalogViewport(
                        snapshots: _snapshots,
                        assets: widget.assets,
                        controller: _catalog,
                        padding: PackSheetView.gridPadding,
                        onLeafTap: _onTap,
                        leafLongPressEligible: _longPressEligible,
                        onLeafLongPressStart: _onLongPressStart,
                        onLeafLongPressMove: (_, details) =>
                            _session?.update(details),
                        onLeafLongPressEnd: (_, details) =>
                            _session?.end(details),
                        onSectionAction: _onSectionAction,
                      ),
                    ),
            ),
            if (action != null)
              _BottomButton(
                label: action.labelIn(strings),
                removes: action.removes,
                onPressed: () => _onButton(action),
              ),
          ],
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
        final cell = usable / PackSheetView.severalColumns;
        var extent = pad;
        for (final pack in packs ?? const <Pack>[]) {
          final shown = math.min(pack.count, PackSheetView.severalLimit);
          extent +=
              _PackSheetGridPolicy.severalHeaderExtent +
              (shown / PackSheetView.severalColumns).ceil() * cell;
        }
        return packs == null ? 2 * cell + pad : extent;
    }
  }
}

// --- Grid policy -------------------------------------------------------------

/// The geometry and headers of a sheet's grid, as the catalogue's snapshot
/// builder asks for them. A new one per build: the install states the
/// several-packs headers show are a snapshot of the library's.
final class _PackSheetGridPolicy extends CatalogPagePolicy {
  _PackSheetGridPolicy({
    required this.grid,
    required this.installed,
    required this.strings,
  });

  /// The header of a pack among several: `EmojiPackHeader`, 56 tall.
  static const double severalHeaderExtent = 56;

  final PackSheetGrid grid;
  final Map<PackId, bool> installed;
  final PackSheetStrings? strings;

  @override
  String titleOf(Collection collection, PanelStrings strings) =>
      grid == PackSheetGrid.severalEmoji ? collection.metadata.title ?? '' : '';

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
      headerExtent: severalHeaderExtent,
    ),
  };

  @override
  CatalogContentBox? contentBoxOf(Collection collection) =>
      grid == PackSheetGrid.stickers ? CatalogContentBox.glyph : null;

  @override
  CatalogSectionAction? actionOf(
    Collection collection,
    PanelStrings strings, {
    PanelArrangement arrangement = PanelArrangement.touch,
  }) {
    final words = this.strings;
    if (grid != PackSheetGrid.severalEmoji || words == null) return null;
    final id = switch (collection.id) {
      CollectionId$Set(:final id) => PackId(id),
      _ => null,
    };
    if (id == null) return null;
    final isInstalled = installed[id] ?? false;
    return CatalogSectionAction(
      id: isInstalled ? 'remove' : 'add',
      label: isInstalled ? words.removePackAction : words.addPackAction,
    );
  }
}

// --- Parts -------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.grabber,
    required this.close,
    required this.links,
  });

  final String title;
  final bool grabber;
  final bool close;
  final (PackSheetLinks, Uri)? links;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.of(context).palette;
    final strings = ChromeStringsScope.packSheetOf(context);
    return SizedBox(
      height: PackSheetView.headerExtent,
      child: Stack(
        children: [
          if (grabber)
            Positioned(
              top: 6,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: PackSheetView.grabberSize.width,
                  height: PackSheetView.grabberSize.height,
                  decoration: BoxDecoration(
                    color: palette.onSurfaceMuted,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
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
                    fontWeight: FontWeight.w600,
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
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
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
        child: CatalogContextMenuPanel(
          entries: [
            CatalogMenuEntry.item(id: _share, label: strings.shareAction),
            CatalogMenuEntry.item(id: _copy, label: strings.copyLinkAction),
          ],
          onChoose: _choose,
          onDismiss: _menu.close,
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
        fontWeight: FontWeight.w600,
      ),
    );
    // Added: a filled pill inset 8 (`featuredStickers_addButton`); removed:
    // a flat bar the full width, its text in the attention colour
    // (`text_RedBold`).
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: removes
            ? SizedBox(
                height: PackSheetView.buttonExtent,
                child: Center(child: text),
              )
            : Padding(
                padding: const EdgeInsets.all(PackSheetView.buttonMargin),
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
  late final _turn = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

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

/// `ic_close_white`: two strokes crossing.
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
    canvas
      ..drawLine(box.topLeft, box.bottomRight, pen)
      ..drawLine(box.topRight, box.bottomLeft, pen);
  }

  @override
  bool shouldRepaint(_CrossPainter oldDelegate) => oldDelegate.color != color;
}

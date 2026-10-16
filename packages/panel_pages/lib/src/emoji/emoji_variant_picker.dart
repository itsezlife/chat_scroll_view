import 'dart:math' as math;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/src/overlay/chrome_overlay_scopes.dart';
import 'package:panel_pages/src/policy/catalog_page_policy.dart';
import 'package:panel_pages/src/theme/chrome_catalog_theme.dart';
import 'package:panel_shell/panel_shell.dart';

/// The geometry of the variant picker: a rounded card of options in one row
/// (or, for more than [maxColumns], rows) over the grid, inside a margin the
/// shadow is drawn in.
///
/// Every option is the **same cell the grid draws** ([cell], the pressed
/// cell's own size) and its glyph the same box and font scale the grid uses
/// (`catalogGlyphBoxExtent`, `TextGlyphProducer.defaultFontScale`), so an
/// emoji looks the same in the picker as under the finger and cannot be
/// cropped by a container smaller than the ink it is drawn with.
///
/// A picker of up to [maxColumns] options is one row with a separator after
/// the first (the emoji as it is, then the variants); one of more is a grid of
/// [maxColumns] columns with no separator.
@immutable
final class EmojiVariantPickerLayout {
  /// The layout of [count] options in cells of size [cell].
  const EmojiVariantPickerLayout({
    required this.count,
    required this.cell,
    this.titleExtent = 0,
  }) : assert(count > 0, 'a picker offers something');

  /// The band a titled picker keeps above its options: the reference desktop
  /// client's 6 px over a 12 px label, less 1.
  static const double titleBand = 21;

  /// Height of the title band above the options, or 0 for an untitled
  /// picker.
  final double titleExtent;

  /// Padding between the card's edge and the options, and around the
  /// separator.
  static const double pad = 8;

  /// Width of the separator after the first option.
  static const double separatorWidth = 1;

  /// Room around the card for its shadow; part of the picker's box, not of
  /// the card.
  static const double shadowMargin = 10;

  /// Corner radius of the card and of an option's highlight.
  static const double radius = 8;

  /// Inset of an option's highlight from its cell, the grid's hover inset,
  /// where the picker is given no highlight size.
  static const double highlightInset = 2;

  /// Distance between the picked cell and the card.
  static const double anchorGap = 2;

  /// Most options in a row; more wrap onto further rows.
  static const int maxColumns = 6;

  /// How many options.
  final int count;

  /// The size of one option: the grid's cell.
  final Size cell;

  /// Whether the options are one row with a separator after the first.
  bool get hasSeparator => count > 1 && count <= maxColumns;

  /// Options in a row.
  int get columns => math.min(count, maxColumns);

  /// Rows of options.
  int get rows => (count / columns).ceil();

  /// Size of the card.
  Size get card => Size(
    hasSeparator
        ? 4 * pad + separatorWidth + count * cell.width
        : 2 * pad + columns * cell.width,
    titleExtent + 2 * pad + rows * cell.height,
  );

  /// Size of the whole picker, the shadow margin included.
  Size get outer =>
      Size(card.width + 2 * shadowMargin, card.height + 2 * shadowMargin);

  /// Where option [index] is, in the card's own coordinates.
  Rect optionRect(int index) {
    final column = index % columns;
    final row = index ~/ columns;
    final left = hasSeparator
        ? (index == 0 ? pad : 3 * pad + separatorWidth + index * cell.width)
        : pad + column * cell.width;
    return Rect.fromLTWH(
      left,
      titleExtent + pad + row * cell.height,
      cell.width,
      cell.height,
    );
  }

  /// Where the separator is, in the card's own coordinates, or null for none.
  Rect? get separatorRect => hasSeparator
      ? Rect.fromLTWH(
          2 * pad + cell.width,
          titleExtent + pad,
          separatorWidth,
          cell.height,
        )
      : null;

  /// The option whose cell holds [local] (the card's own coordinates), or
  /// null when it is on a pad, the separator or outside the card.
  int? indexAt(Offset local) {
    for (var i = 0; i < count; i++) {
      if (optionRect(i).contains(local)) return i;
    }
    return null;
  }

  /// The option nearest to [local], whatever lies between: where a finger
  /// sliding along the row means.
  ///
  /// A single row ignores the vertical position, so a finger wandering above
  /// or below keeps its option; several rows read it too.
  int nearestIndex(Offset local) {
    // Distance from [value] to the span [low, high]: zero inside it.
    double outside(double value, double low, double high) => value < low
        ? low - value
        : value > high
        ? value - high
        : 0;
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < count; i++) {
      final rect = optionRect(i);
      final dx = outside(local.dx, rect.left, rect.right);
      final dy = rows == 1 ? 0 : outside(local.dy, rect.top, rect.bottom);
      final distance = dx * dx + dy * dy;
      if (distance < bestDistance) {
        best = i;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// The top left of the picker's box for a card shown against [cellBounds]
  /// inside [viewport] (both global).
  ///
  /// The card sits above the cell with [anchorGap] between, and below it when
  /// it would cross the top of the viewport. Horizontally it slides with the
  /// cell's column: left-aligned over the first, right-aligned over the last,
  /// proportionally in between, and never leaves the viewport.
  Offset originFor(Rect cellBounds, Rect viewport) {
    final box = outer;
    final columnsInGrid = math.max(
      1,
      (viewport.width / cellBounds.width).round(),
    );
    final column = ((cellBounds.left - viewport.left) / cellBounds.width)
        .round()
        .clamp(0, columnsInGrid - 1);
    final slide = columnsInGrid == 1
        ? 0.0
        : (viewport.width - box.width) * column / (columnsInGrid - 1);
    final left = math.max(
      viewport.left - shadowMargin,
      math.min(
        viewport.left + slide,
        viewport.right - box.width + shadowMargin,
      ),
    );
    final above = cellBounds.top - anchorGap - card.height - shadowMargin;
    final top = above + shadowMargin < viewport.top
        ? cellBounds.bottom + anchorGap - shadowMargin
        : above;
    return Offset(left, top);
  }
}

/// The options of an entry's variant picker, in display order: the base, then
/// each variant the catalogue holds for it.
///
/// The one rule for what the picker offers, so the grid, the picker and search
/// agree with the catalogue: an entry without variants has none and a long
/// press on it does nothing.
List<ContentKey$Unicode> emojiVariantOptions(EmojiEntry entry) => [
  entry.base,
  for (final variant in entry.variants) variant.key,
];

/// The card of options a variant picker draws.
///
/// Stateless: [selected] and the layout are given. [EmojiVariantSession] owns
/// the live selection and the overlay it is shown in.
class EmojiVariantPicker extends StatelessWidget {
  /// A picker of [options] in cells of size [cell], with option [selected]
  /// highlighted.
  ///
  /// [onChoose] is called with an option's index when it is tapped, for a
  /// pointer that is not the press that opened the picker and for assistive
  /// technology. [onHover] hears the option a mouse enters (with its index)
  /// and leaves (with null).
  const EmojiVariantPicker({
    required this.options,
    required this.cell,
    this.glyphExtent,
    this.highlightSize,
    this.title,
    this.selected,
    this.onChoose,
    this.onHover,
    super.key,
  });

  /// What is offered, in order.
  final List<ContentKey$Unicode> options;

  /// The size of one option: the pressed grid cell.
  final Size cell;

  /// The grid's fixed glyph box side, or null for the fraction of [cell].
  final double? glyphExtent;

  /// The size of the highlight of the option under the mouse, centred in its
  /// cell (the grid's hover box), or null to inset the cell by
  /// [EmojiVariantPickerLayout.highlightInset].
  final Size? highlightSize;

  /// A line above the options (12 px, the muted text colour, centred), or
  /// null for none.
  final String? title;

  /// Index of the highlighted option, or null for none.
  final int? selected;

  /// Called with the index of a tapped option, or null for a picker that is
  /// only looked at.
  final ValueChanged<int>? onChoose;

  /// Called as a mouse enters an option and leaves it, or null to ignore the
  /// mouse.
  final ValueChanged<int?>? onHover;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    final strings = ChromeStringsScope.semanticsOf(context);
    final layout = EmojiVariantPickerLayout(
      count: options.length,
      cell: cell,
      titleExtent: title == null ? 0 : EmojiVariantPickerLayout.titleBand,
    );
    final card = layout.card;
    final glyphBox = catalogGlyphBoxExtent(
      cell.width,
      cell.height,
      fixed: glyphExtent,
    );
    final wash = ChromeCatalogTheme.hoverWashOf(palette);
    return Semantics(
      container: true,
      label: strings.variantsAction,
      child: Padding(
        padding: const EdgeInsets.all(EmojiVariantPickerLayout.shadowMargin),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: BorderRadius.circular(
              EmojiVariantPickerLayout.radius,
            ),
            boxShadow: [
              BoxShadow(
                color: palette.shadow.withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SizedBox(
            width: card.width,
            height: card.height,
            child: Stack(
              children: [
                if (title case final text?)
                  Positioned(
                    left: EmojiVariantPickerLayout.pad,
                    right: EmojiVariantPickerLayout.pad,
                    top: 6,
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.onSurfaceMuted,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                if (layout.separatorRect case final separator?)
                  Positioned.fromRect(
                    rect: separator,
                    child: ColoredBox(color: palette.separator),
                  ),
                for (var i = 0; i < options.length; i++)
                  Positioned.fromRect(
                    rect: layout.optionRect(i),
                    child: _Option(
                      glyph: options[i].sequence,
                      glyphBox: glyphBox,
                      highlightSize: highlightSize,
                      selected: i == selected,
                      wash: wash,
                      color: palette.onSurface,
                      onTap: switch (onChoose) {
                        final choose? => () => choose(i),
                        null => null,
                      },
                      onHover: switch (onHover) {
                        final hover? => (inside) => hover(inside ? i : null),
                        null => null,
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// One option: the grid's cell with the grid's glyph box, and nothing that
// clips. An emoji font draws ink beyond the em box it lays out (Apple Color
// Emoji is the common case: a hand or a couple spills several pixels past it),
// so a container sized to the box crops the picture. The cell is larger than
// the box by design and the glyph may use the difference.
class _Option extends StatelessWidget {
  const _Option({
    required this.glyph,
    required this.glyphBox,
    required this.highlightSize,
    required this.selected,
    required this.wash,
    required this.color,
    required this.onTap,
    required this.onHover,
  });

  final String glyph;
  final double glyphBox;
  final Size? highlightSize;
  final bool selected;
  final Color wash;
  final Color color;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onHover;

  BoxDecoration get _highlight => BoxDecoration(
    color: wash,
    borderRadius: BorderRadius.circular(EmojiVariantPickerLayout.radius),
  );

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: glyph,
    onTap: onTap,
    child: ExcludeSemantics(
      child: MouseRegion(
        onEnter: onHover == null ? null : (_) => onHover!(true),
        onExit: onHover == null ? null : (_) => onHover!(false),
        cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (selected)
                Positioned.fill(
                  child: switch (highlightSize) {
                    final size? => Center(
                      child: SizedBox.fromSize(
                        size: size,
                        child: DecoratedBox(decoration: _highlight),
                      ),
                    ),
                    null => Padding(
                      padding: const EdgeInsets.all(
                        EmojiVariantPickerLayout.highlightInset,
                      ),
                      child: DecoratedBox(decoration: _highlight),
                    ),
                  },
                ),
              // The grid's rule: a glyph is drawn at a fixed fraction of its
              // box and only a sequence that lays out wider than the box
              // (a font that draws a family as separate faces) is brought
              // down to it, measured rather than clipped. Height is free.
              SizedBox(
                width: glyphBox,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    glyph,
                    textDirection: TextDirection.ltr,
                    softWrap: false,
                    maxLines: 1,
                    // The grid ignores the text scale; so does its twin.
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: glyphBox * TextGlyphProducer.defaultFontScale,
                      color: color,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// How a picker answers the end of the press that opened it.
enum EmojiVariantPickerMode {
  /// A finger: the highlight follows it along the row, wherever it is, and
  /// lifting chooses the option it is on.
  touch,

  /// A mouse that held the button for the long-press delay: lifting over an
  /// option chooses it, lifting elsewhere on the card closes it, lifting
  /// outside the card closes it without choosing.
  pointerHold,
}

/// A variant picker shown over the page for one press, and the gesture that
/// drives it.
///
/// The press that opened it keeps going: moving changes the highlighted
/// option ([update]) and lifting answers by the [mode] ([end]). A picker
/// opened without a pointer (a screen reader's long-press action, which has no
/// gesture to continue) stays until an option is tapped, and an interrupted
/// press ([cancel]) removes it without choosing.
///
/// ## Modal while it is up
///
/// The picker sits over the whole window on a barrier. A press anywhere else
/// (any button, so a right click too) dismisses it and goes no further, as the
/// press that closes a native popup does not also act on what is below it. It
/// fades in and out over the fade motion role.
///
/// ## Hold
///
/// The picker stands outside the panel, so the pointer moving onto it reads as
/// leaving the panel. The `hold` the caller took on the page's auto-hide as
/// the picker opened is released by the session as it starts to close,
/// however it closes.
///
/// What choosing does is the caller's: `onChosen` gets the option's key, once.
final class EmojiVariantSession implements CatalogLongPressSession {
  EmojiVariantSession._({
    required this.options,
    required this.onChosen,
    required this.mode,
    required this.layout,
    required this.glyphExtent,
    required this.highlightSize,
    required this.title,
    required PanelPageHold hold,
    required int? selected,
    required Rect card,
  }) : _hold = hold,
       _selected = selected,
       _card = card;

  /// Opens the picker for [options] against the pressed cell [cellBounds] in
  /// [viewportBounds] (both global), with option [initial] highlighted when
  /// [mode] is touch.
  ///
  /// The picker is placed in the nearest `Overlay` and re-provides the chrome
  /// theme, strings, motion and direction of [context], because the overlay
  /// sits outside the subtree they were scoped to.
  static EmojiVariantSession show({
    required BuildContext context,
    required List<ContentKey$Unicode> options,
    required ContentKey$Unicode initial,
    required Rect cellBounds,
    required Rect viewportBounds,
    required EmojiVariantPickerMode mode,
    required PanelPageHold hold,
    required ValueChanged<ContentKey$Unicode> onChosen,
    double? glyphExtent,
    Size? highlightSize,
    String? title,
  }) {
    final overlay = Overlay.of(context);
    final scopes = ChromeOverlayScopes.capture(context);
    final layout = EmojiVariantPickerLayout(
      count: options.length,
      cell: cellBounds.size,
      titleExtent: title == null ? 0 : EmojiVariantPickerLayout.titleBand,
    );
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    final originGlobal = layout.originFor(cellBounds, viewportBounds);
    final session = EmojiVariantSession._(
      options: options,
      onChosen: onChosen,
      mode: mode,
      layout: layout,
      glyphExtent: glyphExtent,
      highlightSize: highlightSize,
      title: title,
      hold: hold,
      selected: mode == EmojiVariantPickerMode.touch
          ? math.max(0, options.indexOf(initial))
          : null,
      card: (originGlobal & layout.outer).deflate(
        EmojiVariantPickerLayout.shadowMargin,
      ),
    );
    final fade = scopes.motion.specOf(MotionRole.fade);
    final origin = overlayBox.globalToLocal(originGlobal);
    session._entry = OverlayEntry(
      // In the text fields' tap group, barrier included: choosing a variant
      // or dismissing the picker is not a press outside the composer.
      builder: (context) => scopes.wrap(
        TextFieldTapRegion(
          child: _PickerOverlay(
            session: session,
            origin: origin,
            duration: fade.duration,
            curve: fade.curve,
          ),
        ),
      ),
    );
    overlay.insert(session._entry!);
    return session;
  }

  /// What the picker offers.
  final List<ContentKey$Unicode> options;

  /// Called once with the chosen option.
  final ValueChanged<ContentKey$Unicode> onChosen;

  /// How the end of the opening press is answered.
  final EmojiVariantPickerMode mode;

  /// The geometry the picker was laid out with.
  final EmojiVariantPickerLayout layout;

  /// The grid's fixed glyph box side, or null for the fraction of the cell.
  final double? glyphExtent;

  /// The highlight size of an option, or null for the inset cell.
  final Size? highlightSize;

  /// The line above the options, or null for none.
  final String? title;

  final PanelPageHold _hold;

  // The card without its shadow margin, in global coordinates.
  final Rect _card;
  final _open = listen.ValueNotifier<bool>(true);
  // Bumped whenever what the overlay draws changes.
  final _drawn = ValueNotifier<int>(0);
  OverlayEntry? _entry;
  int? _selected;
  var _closing = false;

  /// The highlighted option, or null for none.
  @visibleForTesting
  int? get selected => _selected;

  /// Whether the session ended, by a choice, a dismissal or a cancel.
  bool get isOver => !_open.value;

  @override
  listen.ValueListenable<bool> get isOpen => _open;

  void _select(int? index) {
    if (_closing || index == _selected) return;
    _selected = index;
    _drawn.value++;
  }

  @override
  void update(LongPressMoveUpdateDetails details) {
    if (_closing) return;
    final global = details.globalPosition;
    final local = global - _card.topLeft;
    _select(switch (mode) {
      EmojiVariantPickerMode.touch => layout.nearestIndex(local),
      _ => _card.contains(global) ? layout.indexAt(local) : null,
    });
  }

  @override
  void end(LongPressEndDetails details) {
    if (_closing) return;
    final global = details.globalPosition;
    final local = global - _card.topLeft;
    switch (mode) {
      case EmojiVariantPickerMode.touch:
        _choose(layout.nearestIndex(local));
      case EmojiVariantPickerMode.pointerHold:
        if (_card.contains(global)) {
          _chooseOrClose(layout.indexAt(local));
        } else {
          _close();
        }
    }
  }

  @override
  void cancel() {
    if (_entry != null) _finish();
  }

  void _chooseOrClose(int? index) {
    if (index == null) {
      _close();
    } else {
      _choose(index);
    }
  }

  void _choose(int index) {
    if (_closing) return;
    final chosen = options[index];
    _close();
    onChosen(chosen);
  }

  // Starts the way out: the hold goes now, so the panel's own rule is back in
  // force as the picker starts to fade, and the overlay leaves after it.
  void _close() {
    if (_closing) return;
    _closing = true;
    _hold.release();
    _open.value = false;
  }

  // At once: the page left, or the fade is over.
  void _finish() {
    _closing = true;
    _hold.release();
    if (_open.value) _open.value = false;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }
}

class _PickerOverlay extends StatefulWidget {
  const _PickerOverlay({
    required this.session,
    required this.origin,
    required this.duration,
    required this.curve,
  });

  final EmojiVariantSession session;
  final Offset origin;
  final Duration duration;
  final Curve curve;

  @override
  State<_PickerOverlay> createState() => _PickerOverlayState();
}

class _PickerOverlayState extends State<_PickerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _fade,
    curve: widget.curve,
  );

  EmojiVariantSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _session._open.addListener(_onOpenChanged);
    _fade.forward();
  }

  @override
  void dispose() {
    _session._open.removeListener(_onOpenChanged);
    _fade.dispose();
    super.dispose();
  }

  // Out: fades for as long as it faded in, passing presses on meanwhile, then
  // leaves the overlay.
  void _onOpenChanged() {
    if (_session._open.value) return;
    setState(() {});
    _fade.reverse().whenComplete(() {
      if (mounted) _session._finish();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return IgnorePointer(
      ignoring: !session._open.value,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => session._close(),
          ),
          Positioned(
            left: widget.origin.dx,
            top: widget.origin.dy,
            child: FadeTransition(
              opacity: _opacity,
              child: ListenableBuilder(
                listenable: session._drawn,
                builder: (context, _) => EmojiVariantPicker(
                  options: session.options,
                  cell: session.layout.cell,
                  glyphExtent: session.glyphExtent,
                  highlightSize: session.highlightSize,
                  title: session.title,
                  selected: session._selected,
                  onChoose: session._choose,
                  onHover: session.mode == EmojiVariantPickerMode.touch
                      ? null
                      : session._select,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

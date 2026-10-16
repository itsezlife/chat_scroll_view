import 'dart:math' as math;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_pages/src/policy/catalog_page_policy.dart';

/// The geometry of the variant picker: a rounded body of cells in rows, with
/// an arrow pointing down at the cell that was pressed.
///
/// A set of documented constants rather than tokens: the picker is Telegram's
/// popup, and its size is part of how it feels under a thumb.
abstract final class EmojiVariantPickerMetrics {
  /// Side of one option.
  static const double cell = 32;

  /// Gap between options, in a row and between rows.
  static const double gap = 4;

  /// Inset before the first option.
  static const double padH = 5;

  /// Vertical padding around the rows.
  static const double padV = 7.5;

  /// Height of the arrow below the body.
  static const double arrowHeight = 6;

  /// Corner radius of the body.
  static const double radius = 12;

  /// Most options in a row; more wrap onto further rows.
  static const int maxColumns = 6;

  /// Columns for [count] options.
  static int columnsFor(int count) => math.min(maxColumns, math.max(1, count));

  /// Rows for [count] options.
  static int rowsFor(int count) => (count / columnsFor(count)).ceil();

  /// Width of a picker of [count] options.
  static double widthFor(int count) {
    final columns = columnsFor(count);
    return columns * cell + (columns - 1) * gap + 2 * padH;
  }

  /// Height of the body of a picker of [count] options, arrow excluded.
  static double bodyHeightFor(int count) {
    final rows = rowsFor(count);
    return rows * cell + (rows - 1) * gap + 2 * padV;
  }

  /// Height of the picker with its arrow.
  static double heightFor(int count) => bodyHeightFor(count) + arrowHeight;

  /// Centre of option [index] in the picker's own coordinates.
  static Offset centerOf(int index, int count) {
    final columns = columnsFor(count);
    final column = index % columns;
    final row = index ~/ columns;
    return Offset(
      padH + column * (cell + gap) + cell / 2,
      padV + row * (cell + gap) + cell / 2,
    );
  }

  /// The option under [local] (the picker's own coordinates) out of [count],
  /// held to the options that exist.
  ///
  /// A single row ignores the vertical position, so a finger sliding along it
  /// may wander off above or below; with several rows it is read too.
  static int indexAt(Offset local, int count) {
    final columns = columnsFor(count);
    final rows = rowsFor(count);
    final column = ((local.dx - padH) / (cell + gap)).floor().clamp(
      0,
      columns - 1,
    );
    final row = rows == 1
        ? 0
        : ((local.dy - padV) / (cell + gap)).floor().clamp(0, rows - 1);
    return math.min(row * columns + column, count - 1);
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

/// The popup that offers an emoji's variants (skin tones and genders).
///
/// Stateless: [selected] and the arrow are given. [EmojiVariantSession] owns
/// the live selection and the overlay it is shown in.
class EmojiVariantPicker extends StatelessWidget {
  /// A picker of [options], with option [selected] highlighted and the arrow
  /// at [arrowX] in the picker's own coordinates (under the selection when
  /// null).
  ///
  /// [onChoose] is called with an option's index when it is tapped, for a
  /// pointer that is not the long press that opened the picker and for
  /// assistive technology.
  const EmojiVariantPicker({
    required this.options,
    required this.selected,
    this.arrowX,
    this.onChoose,
    super.key,
  });

  /// What is offered, in order.
  final List<ContentKey$Unicode> options;

  /// Index of the highlighted option.
  final int selected;

  /// Arrow tip, in the picker's own x; null centres it under [selected].
  final double? arrowX;

  /// Called with the index of a tapped option, or null for a picker that is
  /// only looked at.
  final ValueChanged<int>? onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = ChromeThemeScope.of(context);
    final strings = ChromeStringsScope.semanticsOf(context);
    final count = options.length;
    final arrow =
        arrowX ??
        EmojiVariantPickerMetrics.centerOf(
          math.min(selected, count - 1),
          count,
        ).dx;
    final highlight = theme.palette.iconIdle.withValues(alpha: 0.18);
    return Semantics(
      container: true,
      label: strings.variantsAction,
      child: PhysicalShape(
        clipper: _PickerShapeClipper(arrowX: arrow),
        color: theme.palette.surfaceRaised,
        elevation: 8,
        shadowColor: theme.palette.shadow.withValues(alpha: 0.35),
        child: SizedBox(
          width: EmojiVariantPickerMetrics.widthFor(count),
          height: EmojiVariantPickerMetrics.heightFor(count),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              EmojiVariantPickerMetrics.padH,
              EmojiVariantPickerMetrics.padV,
              EmojiVariantPickerMetrics.padH,
              EmojiVariantPickerMetrics.padV +
                  EmojiVariantPickerMetrics.arrowHeight,
            ),
            child: Wrap(
              spacing: EmojiVariantPickerMetrics.gap,
              runSpacing: EmojiVariantPickerMetrics.gap,
              children: [
                for (var i = 0; i < count; i++)
                  _Option(
                    glyph: options[i].sequence,
                    selected: i == selected,
                    highlight: highlight,
                    onTap: switch (onChoose) {
                      final choose? => () => choose(i),
                      null => null,
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.glyph,
    required this.selected,
    required this.highlight,
    required this.onTap,
  });

  final String glyph;
  final bool selected;
  final Color highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: glyph,
    onTap: onTap,
    child: ExcludeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: ColoredBox(
            color: selected ? highlight : const Color(0x00000000),
            child: SizedBox(
              width: EmojiVariantPickerMetrics.cell,
              height: EmojiVariantPickerMetrics.cell,
              // One line, scaled down to the cell: a sequence of several code
              // points (a couple, a tone) is one picture, never a wrapped
              // line, and a font that draws it wider than the cell still fits.
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    glyph,
                    textDirection: TextDirection.ltr,
                    softWrap: false,
                    maxLines: 1,
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    ),
                    style: const TextStyle(
                      fontSize: EmojiVariantPickerMetrics.cell * 0.82,
                      height: 1,
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

// The rounded body with a downward arrow, as one path.
class _PickerShapeClipper extends CustomClipper<Path> {
  const _PickerShapeClipper({required this.arrowX});

  final double arrowX;

  @override
  Path getClip(Size size) {
    const arrowH = EmojiVariantPickerMetrics.arrowHeight;
    const r = EmojiVariantPickerMetrics.radius;
    final bodyH = size.height - arrowH;
    final w = size.width;
    final ax = arrowX.clamp(r + 8, w - r - 8);
    return Path()
      ..moveTo(r, 0)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: const Radius.circular(r))
      ..lineTo(w, bodyH - r)
      ..arcToPoint(Offset(w - r, bodyH), radius: const Radius.circular(r))
      ..lineTo(ax + 7, bodyH)
      ..lineTo(ax, size.height)
      ..lineTo(ax - 7, bodyH)
      ..lineTo(r, bodyH)
      ..arcToPoint(Offset(0, bodyH - r), radius: const Radius.circular(r))
      ..lineTo(0, r)
      ..arcToPoint(const Offset(r, 0), radius: const Radius.circular(r))
      ..close();
  }

  @override
  bool shouldReclip(_PickerShapeClipper oldClipper) =>
      oldClipper.arrowX != arrowX;
}

/// A variant picker shown over the page for one long press, and the gesture
/// that drives it.
///
/// The long press that opened it keeps going: moving the finger changes the
/// highlighted option ([update]) and lifting it chooses that option ([end]).
/// A picker opened without a pointer (a screen reader's long-press action,
/// which has no gesture to continue) stays until an option is tapped or the
/// area around it is, and an interrupted press ([cancel]) removes it without
/// choosing.
///
/// What choosing does is the caller's: [onChosen] gets the option's key, once.
final class EmojiVariantSession implements CatalogLongPressSession {
  EmojiVariantSession._({
    required this.options,
    required this.onChosen,
    required int selected,
    required Offset origin,
  }) : _selected = selected,
       _origin = origin;

  /// Opens the picker for [options] above [anchor] (global coordinates, the
  /// pressed cell's centre), with option [initial] highlighted.
  ///
  /// The picker is placed in the nearest `Overlay` and re-provides the chrome
  /// theme, strings and direction of [context], because the overlay sits
  /// outside the subtree they were scoped to.
  static EmojiVariantSession show({
    required BuildContext context,
    required List<ContentKey$Unicode> options,
    required ContentKey$Unicode initial,
    required Offset anchor,
    required ValueChanged<ContentKey$Unicode> onChosen,
  }) {
    final overlay = Overlay.of(context);
    final theme = ChromeThemeScope.of(context);
    final strings = ChromeStringsScope.of(context);
    final direction = Directionality.of(context);
    final screen = MediaQuery.sizeOf(context);
    final count = options.length;
    final initialIndex = math.max(0, options.indexOf(initial));
    final width = EmojiVariantPickerMetrics.widthFor(count);
    final height = EmojiVariantPickerMetrics.heightFor(count);
    // The initial option sits under the finger, as far as the screen allows.
    final left = math.min<double>(
      math.max<double>(
        8,
        anchor.dx - EmojiVariantPickerMetrics.centerOf(initialIndex, count).dx,
      ),
      math.max<double>(8, screen.width - width - 8),
    );
    final top = math.min<double>(
      math.max<double>(8, anchor.dy - height - 4),
      math.max<double>(8, screen.height - height - 8),
    );
    final session = EmojiVariantSession._(
      options: options,
      onChosen: onChosen,
      selected: initialIndex,
      origin: Offset(left, top),
    );
    final arrowX = math.min<double>(
      math.max<double>(16, anchor.dx - left),
      width - 16,
    );
    session._entry = OverlayEntry(
      builder: (context) => Directionality(
        textDirection: direction,
        child: ChromeThemeScope.data(
          data: theme,
          child: ChromeStringsScope(
            strings: strings,
            child: Stack(
              children: [
                // Taps around the picker dismiss it.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: session.cancel,
                  ),
                ),
                Positioned(
                  left: left,
                  top: top,
                  child: EmojiVariantPicker(
                    options: options,
                    selected: session._selected,
                    arrowX: arrowX,
                    onChoose: session._choose,
                  ),
                ),
              ],
            ),
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

  final Offset _origin;
  OverlayEntry? _entry;
  int _selected;
  var _over = false;

  /// The highlighted option.
  @visibleForTesting
  int get selected => _selected;

  /// Whether the session ended, by a choice or a cancel.
  bool get isOver => _over;

  @override
  void update(LongPressMoveUpdateDetails details) {
    if (_over) return;
    final next = EmojiVariantPickerMetrics.indexAt(
      details.globalPosition - _origin,
      options.length,
    );
    if (next == _selected) return;
    _selected = next;
    _entry?.markNeedsBuild();
  }

  @override
  void end(LongPressEndDetails details) => _choose(_selected);

  @override
  void cancel() {
    if (_over) return;
    _finish();
  }

  void _choose(int index) {
    if (_over) return;
    _finish();
    onChosen(options[index]);
  }

  void _finish() {
    _over = true;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }
}

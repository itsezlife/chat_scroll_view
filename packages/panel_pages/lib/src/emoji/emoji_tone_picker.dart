import 'dart:async';
import 'dart:math' as math;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_pages/src/overlay/chrome_overlay_scopes.dart';
import 'package:panel_pages/src/policy/catalog_page_policy.dart';
import 'package:panel_shell/panel_shell.dart';

/// The geometry of the tone picker a finger opens: the reference mobile
/// client's.
///
/// One person: a row of [count] 32 px emoji (the emoji as it is, then its
/// tones), 5 px in and 4 px apart, in a window 15 px taller than an emoji
/// whose bottom 6.34 px are the arrow. Two people ([compound]): the emoji as
/// it is beside a 1 px separator, then a row of five tones per person.
@immutable
final class EmojiTonePickerLayout {
  /// The layout of [count] options, or of a two-person picker.
  const EmojiTonePickerLayout({required this.count, this.compound = false});

  /// Side of an emoji.
  static const double emojiSize = 32;

  /// Gap between two options of a row.
  static const double gap = 4;

  /// Height of the arrow under the card.
  static const double arrowHeight = 6.34;

  /// Width of the arrow.
  static const double arrowWidth = 18;

  /// Corner radius of the card.
  static const double radius = 5.5;

  /// Side of the mark under the selected option, and its radius.
  static const double markSize = 36;

  /// Corner radius of the mark.
  static const double markRadius = 4;

  /// Tones per person in a two-person picker.
  static const int tones = 5;

  /// Options of a one-person picker.
  final int count;

  /// Whether the picker is a two-person one.
  final bool compound;

  /// Size of the picker's window: the card, the shadow around it and the
  /// arrow below it.
  Size get size => compound
      ? const Size(emojiSize * 6 + 10 + 4 * 5 + 3, 11.66 + 2 * emojiSize)
      : Size(emojiSize * count + 10 + gap * (count - 1), 15 + emojiSize);

  /// The card's body, in the window: inset for the shadow, ending where the
  /// arrow starts.
  Rect get card => Rect.fromLTRB(
    1.33,
    1.67,
    size.width - 1.33,
    size.height - 2 - (arrowHeight - 2),
  );

  /// Where one-person option [index] is.
  Rect optionRect(int index) => Rect.fromLTWH(
    emojiSize * index + 5 + gap * index,
    5,
    emojiSize,
    emojiSize,
  );

  /// Where the emoji as it is sits in a two-person picker.
  Rect get neutralRect =>
      Rect.fromLTWH(5, (size.height - emojiSize) / 2, emojiSize, emojiSize);

  /// Where tone [tone] of person [row] sits in a two-person picker.
  Rect toneRect(int row, int tone) => Rect.fromLTWH(
    emojiSize * (1 + tone) + 8 + gap * (1 + tone),
    3 + (emojiSize + 1) * row,
    emojiSize,
    emojiSize,
  );

  /// The separator after the emoji as it is, in a two-person picker.
  Rect get separatorRect =>
      Rect.fromLTRB(8.45 + emojiSize, 2, 8.45 + emojiSize + 1, size.height - 6);

  /// The window's left for a picker over the cell [cell] whose option
  /// [selected] lands over the glyph (a two-person picker starts at the cell),
  /// held 5 px inside [bounds].
  double leftFor(Rect cell, int selected, Rect bounds) {
    final wanted = compound
        ? cell.left
        : cell.left + 6 - optionRect(selected).left;
    final most = bounds.right - 5 - size.width;
    return math.max(bounds.left + 5, math.min(wanted, most));
  }

  /// The window's top for a picker over [cell]: the arrow's tip on the top of
  /// the glyph's box.
  double topFor(Rect cell) =>
      cell.top + (cell.height - emojiSize) / 2 - size.height;
}

/// The tone picker a finger opens over the emoji grid: the reference mobile
/// client's card with an arrow under the pressed glyph.
///
/// A one-person picker marks [selected] (an option index; it may be between
/// two while the mark slides) and draws the option under it at full size,
/// the others at 0.9. A two-person picker marks [rowSelections], one tone
/// (or -1 for the emoji as it is) per person.
class EmojiTonePicker extends StatelessWidget {
  /// A picker of [options], or of [rowOptions] beside [options] first one.
  const EmojiTonePicker({
    required this.layout,
    required this.options,
    required this.selected,
    required this.marked,
    required this.arrowX,
    this.rowOptions,
    this.rowSelections = const [-1, -1],
    this.onChoose,
    super.key,
  });

  /// Called with the index of a one-person option chosen by an assistive
  /// tap, or null.
  final ValueChanged<int>? onChoose;

  /// The geometry.
  final EmojiTonePickerLayout layout;

  /// The options of a one-person picker; of a two-person one, the emoji as it
  /// is first.
  final List<ContentKey$Unicode> options;

  /// The tones of each person of a two-person picker, five per row.
  final List<List<ContentKey$Unicode?>>? rowOptions;

  /// The marked option of a one-person picker, as the mark is now.
  final double selected;

  /// The option the mark is on or sliding to.
  final int marked;

  /// The marked tone of each person (-1: the emoji as it is).
  final List<double> rowSelections;

  /// Where the arrow's tip is, from the window's left.
  final double arrowX;

  /// Identifies the mark of a one-person picker.
  @visibleForTesting
  static const Key markKey = ValueKey<String>('emoji-tone-picker-mark');

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    final mark = palette.onSurface.withAlpha(0x0F);
    final size = layout.size;
    Widget glyph(ContentKey$Unicode key, Rect rect, {double scale = 1}) =>
        Positioned.fromRect(
          rect: rect,
          // Drawn only: the option buttons below carry the names.
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Transform.scale(
                scale: scale,
                child: FittedBox(
                  child: Text(
                    key.sequence,
                    textDirection: TextDirection.ltr,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: EmojiTonePickerLayout.emojiSize,
                      height: 1,
                      color: palette.onSurface,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    Widget markAt(Rect rect, {Key? key, double opacity = 1}) =>
        Positioned.fromRect(
          key: key,
          rect: rect,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: mark.withValues(alpha: mark.a * opacity),
              borderRadius: BorderRadius.circular(
                EmojiTonePickerLayout.markRadius,
              ),
            ),
          ),
        );
    final card = layout.card;
    final strings = ChromeStringsScope.semanticsOf(context);
    final picker = SizedBox.fromSize(
      size: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fromRect(
            rect: card,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.surfaceRaised,
                borderRadius: BorderRadius.circular(
                  EmojiTonePickerLayout.radius,
                ),
                boxShadow: [
                  BoxShadow(
                    color: palette.shadow.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 1.5),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: arrowX - EmojiTonePickerLayout.arrowWidth / 2,
            top: size.height - EmojiTonePickerLayout.arrowHeight,
            width: EmojiTonePickerLayout.arrowWidth,
            height: EmojiTonePickerLayout.arrowHeight,
            child: CustomPaint(painter: _ArrowPainter(palette.surfaceRaised)),
          ),
          if (rowOptions case final rows?) ...[
            Positioned.fromRect(
              rect: layout.separatorRect,
              child: ColoredBox(color: palette.separator),
            ),
            for (var row = 0; row < rows.length; row++)
              markAt(
                _rowMark(row, rowSelections[row]),
                opacity: rowSelections[row] < 0 ? 0.5 : 1,
              ),
            glyph(options.first, layout.neutralRect),
            for (var row = 0; row < rows.length; row++)
              for (var tone = 0; tone < rows[row].length; tone++)
                if (rows[row][tone] case final key?)
                  _person(
                    key,
                    layout.toneRect(row, tone),
                    first: row == 0,
                    glyph: glyph,
                  ),
          ] else ...[
            markAt(_mark(selected), key: markKey),
            for (var i = 0; i < options.length; i++)
              glyph(
                options[i],
                layout.optionRect(i),
                scale:
                    0.9 + 0.1 * (1 - math.min(0.5, (i - selected).abs()) * 2),
              ),
            // What assistive technology reads and taps: one button per
            // option.
            for (var i = 0; i < options.length; i++)
              Positioned.fromRect(
                rect: layout.optionRect(i),
                child: Semantics(
                  button: true,
                  selected: i == marked,
                  label: options[i].sequence,
                  onTap: switch (onChoose) {
                    final choose? => () => choose(i),
                    null => null,
                  },
                ),
              ),
          ],
        ],
      ),
    );
    return Semantics(
      container: true,
      label: strings.variantsAction,
      child: picker,
    );
  }

  // A tone of one person of a two-person emoji: the emoji in that tone, the
  // half of the row's person in colour and the other half greyed, as the
  // reference client draws its halves (the first person is on the left).
  Widget _person(
    ContentKey$Unicode key,
    Rect rect, {
    required bool first,
    required Widget Function(ContentKey$Unicode key, Rect rect) glyph,
  }) {
    Widget half({required bool left, required Widget child}) => ClipRect(
      clipper: _HalfClipper(left: left),
      child: child,
    );
    final whole = glyph(key, Offset.zero & rect.size);
    return Positioned.fromRect(
      rect: rect,
      child: Stack(
        children: [
          half(
            left: first,
            child: Stack(children: [whole]),
          ),
          half(
            left: !first,
            child: ColorFiltered(
              colorFilter: const ColorFilter.matrix(_grey),
              child: Stack(children: [whole]),
            ),
          ),
        ],
      ),
    );
  }

  // Luminance, a little darker: the other person, out of play.
  static const List<double> _grey = [
    0.2126 * 0.6, 0.7152 * 0.6, 0.0722 * 0.6, 0, 0, //
    0.2126 * 0.6, 0.7152 * 0.6, 0.0722 * 0.6, 0, 0, //
    0.2126 * 0.6, 0.7152 * 0.6, 0.0722 * 0.6, 0, 0, //
    0, 0, 0, 1, 0,
  ];

  Rect _mark(double index) {
    final left =
        EmojiTonePickerLayout.emojiSize * index +
        5 +
        EmojiTonePickerLayout.gap * index;
    return Rect.fromLTWH(
      left - 2,
      3,
      EmojiTonePickerLayout.markSize,
      EmojiTonePickerLayout.markSize,
    );
  }

  // Over a tone of the row, or (at -1) over the emoji as it is, where the two
  // rows' marks meet at half strength.
  Rect _rowMark(int row, double tone) {
    if (tone < 0) return layout.neutralRect.inflate(2);
    return layout.toneRect(row, tone.round()).inflate(2);
  }
}

class _HalfClipper extends CustomClipper<Rect> {
  const _HalfClipper({required this.left});

  final bool left;

  @override
  Rect getClip(Size size) => left
      ? Rect.fromLTWH(0, 0, size.width / 2, size.height)
      : Rect.fromLTWH(size.width / 2, 0, size.width / 2, size.height);

  @override
  bool shouldReclip(_HalfClipper old) => old.left != left;
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close(),
    Paint()..color = color,
  );

  @override
  bool shouldRepaint(_ArrowPainter old) => old.color != color;
}

/// The reference mobile client's tone picker in use, from the long press that
/// opened it.
///
/// One person: the finger, once it has left a small slop around where the
/// press went down, marks the option under it (in 36 px steps along the row,
/// whatever its height), a tick of haptics on every change, the mark sliding
/// over 125 ms; lifting it chooses the marked option ([onChosen]) with a key
/// tap of haptics. Two people: lifting the finger leaves the picker up; a tap
/// or a drag on a row sets that person's tone, given to both while the other
/// has none, and each change is handed on at once ([onCompound]) without
/// closing; a press elsewhere closes it. Opening buzzes as a long press does.
final class EmojiToneSession implements CatalogLongPressSession {
  EmojiToneSession._({
    required this.layout,
    required this.options,
    required this.rowOptions,
    required this.onChosen,
    required this.onCompound,
    required PanelPageHold hold,
    required double selected,
    required List<int> rows,
    required Offset pressedAt,
    required double left,
  }) : _hold = hold,
       _target = selected,
       _rows = rows,
       _pressedAt = pressedAt,
       _left = left;

  /// The slop the finger leaves before it moves the mark: 0.2 cm.
  static const double slop = 0.2 / 2.54 * 160;

  /// How long the mark takes to the next option.
  static const Duration slide = Duration(milliseconds: 125);

  /// Opens the picker for the options of the cell [cellBounds] (global), held
  /// 5 px inside the overlay it is shown in, with [initial] marked, as
  /// [EmojiToneSession] says.
  ///
  /// [rowOptions] makes it a two-person picker: the five tones of each person,
  /// null where a combination is missing, and [initialRows] their tones (-1
  /// for none).
  static EmojiToneSession show({
    required BuildContext context,
    required List<ContentKey$Unicode> options,
    required int initial,
    required Rect cellBounds,
    required Offset pressedAt,
    required PanelPageHold hold,
    required ValueChanged<ContentKey$Unicode> onChosen,
    List<List<ContentKey$Unicode?>>? rowOptions,
    List<int> initialRows = const [-1, -1],
    ValueChanged<List<int>>? onCompound,
  }) {
    final overlay = Overlay.of(context);
    final scopes = ChromeOverlayScopes.capture(context);
    final layout = EmojiTonePickerLayout(
      count: options.length,
      compound: rowOptions != null,
    );
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    // Held inside the overlay it is shown in: the screen, as far as it goes.
    final bounds = overlayBox.localToGlobal(Offset.zero) & overlayBox.size;
    final left = layout.leftFor(cellBounds, initial, bounds);
    final top = layout.topFor(cellBounds);
    final session = EmojiToneSession._(
      layout: layout,
      options: options,
      rowOptions: rowOptions,
      onChosen: onChosen,
      onCompound: onCompound,
      hold: hold,
      selected: initial.toDouble(),
      rows: List<int>.of(initialRows),
      pressedAt: pressedAt,
      left: left,
    );
    final origin = overlayBox.globalToLocal(Offset(left, top));
    final fade = scopes.motion.specOf(MotionRole.fade);
    session._entry = OverlayEntry(
      builder: (context) => scopes.wrap(
        TextFieldTapRegion(
          child: _ToneOverlay(
            session: session,
            origin: origin,
            arrowX: cellBounds.center.dx - left,
            fade: fade,
          ),
        ),
      ),
    );
    overlay.insert(session._entry!);
    unawaited(HapticFeedback.vibrate());
    return session;
  }

  /// The geometry.
  final EmojiTonePickerLayout layout;

  /// The options (of a two-person picker, the emoji as it is first).
  final List<ContentKey$Unicode> options;

  /// The tones of each person of a two-person picker.
  final List<List<ContentKey$Unicode?>>? rowOptions;

  /// Called once with the option a one-person picker chose.
  final ValueChanged<ContentKey$Unicode> onChosen;

  /// Called with both people's tones whenever a two-person picker changes.
  final ValueChanged<List<int>>? onCompound;

  final PanelPageHold _hold;
  final Offset _pressedAt;
  final double _left;
  final List<int> _rows;
  double _target;
  var _tracking = false;
  var _closing = false;
  OverlayEntry? _entry;
  final _open = listen.ValueNotifier<bool>(true);
  final _changed = ValueNotifier<int>(0);

  bool get _compound => rowOptions != null;

  @override
  listen.ValueListenable<bool> get isOpen => _open;

  @override
  void update(LongPressMoveUpdateDetails details) {
    if (_closing || _compound) return;
    final at = details.globalPosition;
    if (!_tracking) {
      final moved = at - _pressedAt;
      if (moved.dx.abs() < slop && moved.dy.abs() < slop) return;
      _tracking = true;
    }
    const step = EmojiTonePickerLayout.emojiSize + EmojiTonePickerLayout.gap;
    final index = ((at.dx - _left - 3) / step).floor().clamp(
      0,
      options.length - 1,
    );
    if (index == _target) return;
    _target = index.toDouble();
    _changed.value++;
    unawaited(HapticFeedback.selectionClick());
  }

  @override
  void end(LongPressEndDetails details) {
    if (_closing || _compound) return;
    final chosen = options[_target.round()];
    unawaited(HapticFeedback.mediumImpact());
    _close();
    onChosen(chosen);
  }

  @override
  void cancel() {
    if (_entry != null) _finish();
  }

  // A tap on a one-person picker (one opened with no finger down, by an
  // assistive long press): chooses the option under it.
  void _tapSingle(Offset local) {
    for (var i = 0; i < options.length; i++) {
      if (layout.optionRect(i).inflate(2).contains(local)) {
        _chooseIndex(i);
        return;
      }
    }
  }

  void _chooseIndex(int index) {
    if (_closing || _compound) return;
    _target = index.toDouble();
    unawaited(HapticFeedback.mediumImpact());
    _close();
    onChosen(options[index]);
  }

  // A tap or a drag on a two-person picker, at [local] in its window.
  void _touchRow(Offset local, {required int row}) {
    if (_closing || !_compound) return;
    final first = layout.toneRect(row, 0).left;
    const step = EmojiTonePickerLayout.emojiSize + EmojiTonePickerLayout.gap;
    final tone = local.dx < first - 2
        ? -1
        : ((local.dx - first + 2) / step).floor().clamp(
            0,
            EmojiTonePickerLayout.tones - 1,
          );
    if (tone == _rows[row]) return;
    _rows[row] = tone;
    // A tone for one person alone is given to both; none is none for both.
    final other = 1 - row;
    if (tone < 0 || _rows[other] < 0) _rows[other] = tone;
    _changed.value++;
    unawaited(HapticFeedback.selectionClick());
    onCompound?.call(List<int>.unmodifiable(_rows));
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    _hold.release();
    _open.value = false;
  }

  void _finish() {
    _closing = true;
    _hold.release();
    if (_open.value) _open.value = false;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }
}

class _ToneOverlay extends StatefulWidget {
  const _ToneOverlay({
    required this.session,
    required this.origin,
    required this.arrowX,
    required this.fade,
  });

  final EmojiToneSession session;
  final Offset origin;
  final double arrowX;
  final MotionSpec fade;

  @override
  State<_ToneOverlay> createState() => _ToneOverlayState();
}

class _ToneOverlayState extends State<_ToneOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _show = AnimationController(
    vsync: this,
    duration: widget.fade.duration,
  )..forward();
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: EmojiToneSession.slide,
    value: 1,
  );
  late double _from = widget.session._target;
  late double _to = widget.session._target;
  int? _row;

  // The reference client's ease-out quint.
  static const Curve _quint = Cubic(0.23, 1, 0.32, 1);

  EmojiToneSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _session._open.addListener(_onOpen);
    _session._changed.addListener(_onChanged);
  }

  @override
  void dispose() {
    _session._open.removeListener(_onOpen);
    _session._changed.removeListener(_onChanged);
    _show.dispose();
    _slide.dispose();
    super.dispose();
  }

  double get _selected =>
      _from + (_to - _from) * _quint.transform(_slide.value);

  void _onChanged() {
    setState(() {
      _from = _selected;
      _to = _session._target;
    });
    _slide.forward(from: 0);
  }

  void _onOpen() {
    if (_session._open.value) return;
    _show.reverse().whenComplete(() {
      if (mounted) _session._finish();
    });
  }

  void _down(Offset local) {
    if (!_session._compound) return;
    _row = local.dy < _session.layout.size.height / 2 ? 0 : 1;
    _session._touchRow(local, row: _row!);
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final layout = session.layout;
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
              opacity: CurvedAnimation(parent: _show, curve: widget.fade.curve),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => _down(details.localPosition),
                onTapUp: (details) => session._tapSingle(details.localPosition),
                onHorizontalDragStart: (details) =>
                    _down(details.localPosition),
                onHorizontalDragUpdate: (details) =>
                    session._touchRow(details.localPosition, row: _row ?? 0),
                child: AnimatedBuilder(
                  animation: Listenable.merge([_slide, session._changed]),
                  builder: (context, _) => EmojiTonePicker(
                    layout: layout,
                    options: session.options,
                    rowOptions: session.rowOptions,
                    selected: _selected,
                    marked: session._target.round(),
                    onChoose: session._chooseIndex,
                    rowSelections: [
                      for (final tone in session._rows) tone.toDouble(),
                    ],
                    arrowX: widget.arrowX,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

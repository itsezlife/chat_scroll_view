import 'dart:async';
import 'dart:math' as math;

import 'package:emoji_data/emoji_data.dart';
import 'package:chat_chrome/src/panel/emoji_glyph.dart';
import 'package:chat_chrome/src/theme/chat_chrome_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Skin-tone popup window metrics (phone).
abstract final class EmojiColorPickerMetrics {
  /// Drawn tone cell (`emojiSize`, phone).
  static const double emojiSize = 32;

  /// Gap between cells (`dp(4)`).
  static const double gap = 4;

  /// Horizontal inset before first cell (`dp(5)`).
  static const double padH = 5;

  /// Vertical padding around the row (`dp(15)` total chrome − size).
  static const double padV = 7.5;

  /// Arrow tip below body (`dp(6)`).
  static const double arrowH = 6;

  /// Corner radius on popup body.
  static const double radius = 12;

  /// Popup width for 6 tones.
  static double get popupWidth => emojiSize * 6 + padH * 2 + gap * 5;

  /// Popup body height (single row, no arrow).
  static double get popupHeight => padV * 2 + emojiSize;

  /// Total height including arrow.
  static double get totalHeight => popupHeight + arrowH;

  /// Selection from local X inside the picker content.
  static int selectionFromLocalX(double x) {
    final cell = emojiSize + gap;
    return (x / cell).floor().clamp(0, 5);
  }
}

/// Clip path: rounded body + downward arrow .
class _PickerShapeClipper extends CustomClipper<Path> {
  _PickerShapeClipper({required this.arrowX});

  final double arrowX;

  @override
  Path getClip(Size size) {
    final bodyH = size.height - EmojiColorPickerMetrics.arrowH;
    final w = size.width;
    final r = EmojiColorPickerMetrics.radius;
    final ax = arrowX.clamp(r + 8, w - r - 8);

    final path = Path()
      ..moveTo(r, 0)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
      ..lineTo(w, bodyH - r)
      ..arcToPoint(Offset(w - r, bodyH), radius: Radius.circular(r))
      ..lineTo(ax + 7, bodyH)
      ..lineTo(ax, size.height)
      ..lineTo(ax - 7, bodyH)
      ..lineTo(r, bodyH)
      ..arcToPoint(Offset(0, bodyH - r), radius: Radius.circular(r))
      ..lineTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant _PickerShapeClipper old) => old.arrowX != arrowX;
}

/// Skin-tone popup chrome (non-compound).
class EmojiColorPicker extends StatelessWidget {
  /// Creates a horizontal tone strip for [base].
  const EmojiColorPicker({
    required this.base,
    required this.selection,
    this.arrowX,
    super.key,
  });

  /// Base emoji without Fitzpatrick modifier.
  final String base;

  /// Selected tone index 0…5.
  final int selection;

  /// Arrow tip X in popup local coords (null → center under selection).
  final double? arrowX;

  @override
  Widget build(BuildContext context) {
    final colors = ChatChromeTheme.of(context);
    final bg = colors.messagePanelBackground;
    final highlight = colors.panelIcon.withValues(alpha: 0.18);
    final arrow =
        arrowX ??
        (EmojiColorPickerMetrics.padH +
            selection *
                (EmojiColorPickerMetrics.emojiSize +
                    EmojiColorPickerMetrics.gap) +
            EmojiColorPickerMetrics.emojiSize / 2);

    return PhysicalShape(
      clipper: _PickerShapeClipper(arrowX: arrow),
      color: bg,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      child: SizedBox(
        width: EmojiColorPickerMetrics.popupWidth,
        height: EmojiColorPickerMetrics.totalHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            EmojiColorPickerMetrics.padH,
            EmojiColorPickerMetrics.padV,
            EmojiColorPickerMetrics.padH,
            EmojiColorPickerMetrics.padV + EmojiColorPickerMetrics.arrowH,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var i = 0; i < EmojiSkinTone.modifiers.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: EmojiColorPickerMetrics.gap),
                _ToneCell(
                  glyph: EmojiSkinTone.apply(base, i),
                  selected: i == selection,
                  highlight: highlight,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One tone slot — clip emoji paint so glyphs cannot bleed under the popup.
class _ToneCell extends StatelessWidget {
  const _ToneCell({
    required this.glyph,
    required this.selected,
    required this.highlight,
  });

  final String glyph;
  final bool selected;
  final Color highlight;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: ColoredBox(
        color: selected ? highlight : Colors.transparent,
        child: SizedBox(
          width: EmojiColorPickerMetrics.emojiSize,
          height: EmojiColorPickerMetrics.emojiSize,
          child: EmojiGlyph(
            glyph: glyph,
            size: EmojiColorPickerMetrics.emojiSize,
            paintFraction: 0.92,
          ),
        ),
      ),
    );
  }
}

/// Live long-press skin picker (pointer move + up to send).
class EmojiColorPickerSession {
  EmojiColorPickerSession._({
    required this.base,
    required Completer<String?> completer,
    required OverlayEntry entry,
    required int selection,
  }) : _completer = completer,
       _entry = entry,
       _selection = selection;

  /// Opens the picker under [anchorGlobal] for [base].
  static EmojiColorPickerSession show({
    required BuildContext context,
    required String base,
    required Offset anchorGlobal,
    int initialSelection = 0,
  }) {
    final completer = Completer<String?>();
    final overlay = Overlay.of(context);
    final size = MediaQuery.sizeOf(context);
    final popupW = EmojiColorPickerMetrics.popupWidth;
    final popupH = EmojiColorPickerMetrics.totalHeight;

    var selection = initialSelection.clamp(0, 5);
    late OverlayEntry entry;
    late EmojiColorPickerSession session;

    // Align selected cell under the finger / emoji cell.
    var left =
        anchorGlobal.dx -
        (EmojiColorPickerMetrics.padH +
            selection *
                (EmojiColorPickerMetrics.emojiSize +
                    EmojiColorPickerMetrics.gap) +
            EmojiColorPickerMetrics.emojiSize / 2);
    left = left.clamp(8.0, size.width - popupW - 8);
    var top = anchorGlobal.dy - popupH - 4;
    top = top.clamp(8.0, size.height - popupH - 8);

    void rebuild() {
      entry.markNeedsBuild();
    }

    entry = OverlayEntry(
      builder: (context) {
        final arrowX = (anchorGlobal.dx - left).clamp(16.0, popupW - 16);
        return Positioned(
          left: left,
          top: top,
          child: EmojiColorPicker(
            base: base,
            selection: selection,
            arrowX: arrowX,
          ),
        );
      },
    );

    session = EmojiColorPickerSession._(
      base: base,
      completer: completer,
      entry: entry,
      selection: selection,
    );
    session._left = left;
    session._onSelectionChanged = (next) {
      if (next == selection) return;
      selection = next;
      session._selection = next;
      HapticFeedback.selectionClick();
      rebuild();
    };

    overlay.insert(entry);
    return session;
  }

  /// Base glyph without tone.
  final String base;

  final Completer<String?> _completer;
  final OverlayEntry _entry;
  int _selection;
  double _left = 0;
  void Function(int next)? _onSelectionChanged;

  /// Current tone index 0…5.
  int get selection => _selection;

  /// Completes when [complete] / [cancel] is called.
  Future<String?> get future => _completer.future;

  /// Updates selection from a global pointer X (pointer move).
  void updateFromGlobalX(double globalX) {
    final localX = globalX - _left - EmojiColorPickerMetrics.padH;
    final next = EmojiColorPickerMetrics.selectionFromLocalX(
      math.max(0.0, localX),
    );
    _onSelectionChanged?.call(next);
  }

  /// Sends the selected glyph and removes the overlay.
  void complete() {
    if (_completer.isCompleted) return;
    _entry.remove();
    _completer.complete(EmojiSkinTone.apply(base, _selection));
  }

  /// Dismisses without a glyph.
  void cancel() {
    if (_completer.isCompleted) return;
    _entry.remove();
    _completer.complete(null);
  }
}

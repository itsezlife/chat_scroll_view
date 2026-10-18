import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:composer_editable/composer_editable.dart';
import 'package:composer_editable/src/widget/selection_highlight.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The selection highlight is one shape, with no seam between its lines.
///
/// The highlight is translucent. Painted as a rect per line, two lines meet on
/// a shared edge that is rarely on a device pixel, and each rect covers only
/// part of the pixel on that edge: the two partial coverages composite to less
/// than the colour paints anywhere else, a visible seam. The tests read the
/// pixels the field paints, not the boxes it asks for, because the boxes
/// themselves leave a gap: the engine rounds each line's height, so every line
/// box ends 0.2 logical pixels short of the next one at 16 px text with a line
/// height of 1.3, whatever [BoxHeightStyle] asks for.
/// What a text holds for an inline atom.
const _atom = '\uFFFC';

void main() {
  const background = Color(0xFF000000);
  const highlight = Color(0x80FFFFFF);
  const fieldWidth = 120.0;
  const fieldPadding = 8.0;

  group('highlight seams', () {
    /// A field that paints [text] over an opaque background, selected whole.
    Future<_Painted> paint(
      WidgetTester tester, {
      required String text,
      required double devicePixelRatio,
      double fontSize = 16,
      double height = 1.3,
      TextDirection textDirection = TextDirection.ltr,
      TextEditingController? controller,
      FocusNode? focusNode,
      int? maxLines,
    }) async {
      tester.view.devicePixelRatio = devicePixelRatio;
      tester.view.physicalSize = const Size(240, 480) * devicePixelRatio;
      addTearDown(tester.view.reset);
      final field = controller ?? (TextEditingController(text: text));
      addTearDown(field.dispose);
      final focus = focusNode ?? FocusNode();
      addTearDown(focus.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            textSelectionTheme: const TextSelectionThemeData(
              selectionColor: highlight,
            ),
          ),
          home: Directionality(
            textDirection: textDirection,
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: boundary,
                child: ColoredBox(
                  color: background,
                  child: Material(
                    type: MaterialType.transparency,
                    child: Padding(
                      padding: const EdgeInsets.all(fieldPadding),
                      child: SizedBox(
                        width: fieldWidth,
                        child: ExtendedTextField(
                          controller: field,
                          focusNode: focus,
                          autofocus: true,
                          maxLines: maxLines,
                          showCursor: false,
                          style: TextStyle(
                            fontSize: fontSize,
                            height: height,
                            color: const Color(0x00000000),
                          ),
                          decoration: const InputDecoration.collapsed(
                            hintText: null,
                          ),
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
      await tester.pumpAndSettle();
      field.selection = TextSelection(
        baseOffset: 0,
        extentOffset: field.text.length,
      );
      await tester.pump();

      final render = tester
          .state<ExtendedEditableTextState>(find.byType(ExtendedEditableText))
          .renderEditable;
      final repaint =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = (await tester.runAsync(
        () => repaint.toImage(pixelRatio: devicePixelRatio),
      ))!;
      final bytes = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      return _Painted(
        render: render,
        image: image,
        rgba: bytes,
        devicePixelRatio: devicePixelRatio,
        origin: render.localToGlobal(Offset.zero, ancestor: repaint),
      );
    }

    /// Every pixel well inside the highlight is the highlight colour.
    ///
    /// A pixel is well inside when the four points one device pixel diagonally
    /// around its centre each lie in some selection box, so the outer edge of
    /// the highlight is not read but an edge two boxes share is. A seam is a
    /// pixel there that is not the colour the rest of the highlight paints.
    void expectNoSeam(_Painted painted, {required String reason}) {
      final boxes = painted.render.getBoxesForSelection(
        painted.render.selection!,
      );
      final lineTops = <int>{for (final box in boxes) box.top.round()};
      expect(lineTops.length, greaterThan(2), reason: 'a multi-line selection');

      final dpr = painted.devicePixelRatio;
      final fieldBox = Offset.zero & painted.render.size;
      final rects = <Rect>[
        for (final box in boxes)
          // The highlight stops at the field's own box.
          _scale(
            box.toRect().intersect(fieldBox).shift(painted.origin),
            dpr,
          ).inflate(0.5),
      ];
      bool covered(double x, double y) =>
          rects.any((rect) => rect.contains(Offset(x, y)));

      final first = rects.first;
      final expected = painted.level(
        first.center.dx.floor(),
        first.center.dy.floor(),
      );
      expect(
        expected,
        inInclusiveRange(0x38, 0xC8),
        reason: 'the first box is highlight over the background',
      );

      final seams = <int, List<int>>{};
      for (var y = 0; y < painted.image.height; y++) {
        for (var x = 0; x < painted.image.width; x++) {
          final cx = x + 0.5;
          final cy = y + 0.5;
          final deep =
              covered(cx - 1, cy - 1) &&
              covered(cx + 1, cy - 1) &&
              covered(cx - 1, cy + 1) &&
              covered(cx + 1, cy + 1);
          if (deep && (painted.level(x, y) - expected).abs() > 2) {
            (seams[y] ??= <int>[]).add(x);
          }
        }
      }
      expect(
        seams.entries.map((row) {
          final x = row.value;
          return 'row ${row.key}: ${x.length} px from ${x.first} to '
              '${x.last}, ${painted.level(x.first, row.key)}';
        }),
        isEmpty,
        reason: '$reason: rows that are not $expected',
      );
    }

    for (final dpr in <double>[1, 1.5, 2, 2.625, 3]) {
      final label = 'at ${dpr}x';

      testWidgets('a line height above one $label', (tester) async {
        final painted = await paint(
          tester,
          text: 'one two three four five six seven eight',
          devicePixelRatio: dpr,
        );
        expectNoSeam(painted, reason: 'line height 1.3');
      });

      testWidgets('a code span among larger text $label', (tester) async {
        final controller = _SpannedController(
          text: 'plain code plain code plain code plain code',
          mark: (text) => text == 'code'
              ? const TextStyle(fontFamily: 'monospace', fontSize: 12)
              : const TextStyle(fontSize: 19),
        );
        final painted = await paint(
          tester,
          text: '',
          controller: controller,
          devicePixelRatio: dpr,
        );
        expectNoSeam(painted, reason: 'mixed font sizes');
      });

      testWidgets('right-to-left text $label', (tester) async {
        final painted = await paint(
          tester,
          text: 'אחד שניים שלושה ארבעה חמישה שישה שבעה שמונה',
          devicePixelRatio: dpr,
          textDirection: TextDirection.rtl,
        );
        expectNoSeam(painted, reason: 'right-to-left text');
      });

      testWidgets('an inline atom taller than the text $label', (tester) async {
        final controller = _SpannedController(
          text: 'one $_atom two $_atom three $_atom four $_atom five',
          mark: (_) => const TextStyle(fontSize: 16),
          atom: const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: SizedBox(width: 22, height: 27),
          ),
        );
        final painted = await paint(
          tester,
          text: '',
          controller: controller,
          devicePixelRatio: dpr,
        );
        expectNoSeam(painted, reason: 'inline atom');
      });
    }

    testWidgets('a scrolled selection stops at the field box', (tester) async {
      final painted = await paint(
        tester,
        text: 'one two three four five six seven eight nine ten',
        devicePixelRatio: 2,
        maxLines: 2,
      );

      final dpr = painted.devicePixelRatio;
      final padding = (fieldPadding * dpr).round();
      final leaked = <String>[
        for (var x = padding; x < painted.image.width - padding; x++) ...[
          for (final y in <int>[
            padding - 2,
            painted.image.height - padding + 1,
          ])
            if (painted.level(x, y) != 0) '($x, $y)',
        ],
      ];
      expect(
        leaked,
        isEmpty,
        reason: 'padding around the field is not painted',
      );
    });

    testWidgets('a field without focus paints no highlight', (tester) async {
      final painted = await paint(
        tester,
        text: 'one two three four five six seven eight',
        devicePixelRatio: 1,
      );
      expect(painted.render.selectionColor, isNotNull);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      expect(painted.render.selectionColor, isNull);
    });
  });

  group('selectionHighlightPath', () {
    const clip = Rect.fromLTWH(0, 0, 100, 100);

    test('closes the gap rounding leaves between two lines', () {
      final path = selectionHighlightPath(
        const <Rect>[
          Rect.fromLTRB(0, 0, 80, 20.8),
          Rect.fromLTRB(0, 21, 80, 41.8),
        ],
        maxLineGap: 10,
        clip: clip,
      );

      expect(path.contains(const Offset(40, 20.9)), isTrue);
      expect(path.getBounds().bottom, closeTo(41.8, 0.01));
    });

    test('bridges only the width two lines share', () {
      final path = selectionHighlightPath(
        const <Rect>[
          Rect.fromLTRB(0, 0, 80, 20.8),
          Rect.fromLTRB(0, 21, 30, 41.8),
        ],
        maxLineGap: 10,
        clip: clip,
      );

      expect(path.contains(const Offset(20, 20.9)), isTrue);
      expect(
        path.contains(const Offset(50, 20.9)),
        isFalse,
        reason: 'the shorter line keeps its step',
      );
    });

    test('closes the gap between every run of two lines', () {
      // A line in runs of different heights, as a code span makes, and the
      // runs listed out of order (right-to-left).
      final path = selectionHighlightPath(
        const <Rect>[
          Rect.fromLTRB(40, 3, 80, 18),
          Rect.fromLTRB(0, 0, 40, 20.8),
          Rect.fromLTRB(40, 21, 80, 41.8),
          Rect.fromLTRB(0, 21.5, 40, 41.8),
        ],
        maxLineGap: 10,
        clip: clip,
      );

      expect(path.contains(const Offset(20, 21.2)), isTrue);
      expect(path.contains(const Offset(60, 19.5)), isTrue);
      expect(
        path.contains(const Offset(60, 1)),
        isFalse,
        reason: 'a shorter run keeps its own top',
      );
    });

    test('keeps a break wider than the gap the engine leaves', () {
      final path = selectionHighlightPath(
        const <Rect>[Rect.fromLTRB(0, 0, 80, 20), Rect.fromLTRB(0, 40, 80, 60)],
        maxLineGap: 10,
        clip: clip,
      );

      expect(path.contains(const Offset(40, 30)), isFalse);
    });

    test('stops at the clip', () {
      final path = selectionHighlightPath(
        const <Rect>[Rect.fromLTRB(-5, -5, 140, 120)],
        maxLineGap: 10,
        clip: clip,
      );

      expect(path.getBounds(), clip);
    });

    test('is empty for no boxes', () {
      expect(
        selectionHighlightPath(
          const <Rect>[],
          maxLineGap: 10,
          clip: clip,
        ).getBounds(),
        Rect.zero,
      );
    });
  });
}

/// Paints [text] in spans: a word at a time through [mark], and a
/// [_atom] as [atom].
class _SpannedController extends TextEditingController {
  _SpannedController({
    required String super.text,
    required this.mark,
    this.atom,
  });

  final TextStyle Function(String word) mark;
  final WidgetSpan? atom;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    required bool withComposing,
    TextStyle? style,
  }) {
    final base = style ?? const TextStyle();
    final children = <InlineSpan>[];
    for (final word in text.split(RegExp('(?<= )'))) {
      if (word.contains(_atom)) {
        children.add(atom!);
        final rest = word.replaceFirst(_atom, '');
        if (rest.isNotEmpty) {
          children.add(TextSpan(text: rest, style: base.merge(mark(rest))));
        }
      } else {
        children.add(
          TextSpan(text: word, style: base.merge(mark(word.trim()))),
        );
      }
    }
    return TextSpan(style: base, children: children);
  }
}

class _Painted {
  _Painted({
    required this.render,
    required this.image,
    required this.rgba,
    required this.devicePixelRatio,
    required this.origin,
  });

  final ExtendedRenderEditable render;
  final ui.Image image;
  final ByteData rgba;
  final double devicePixelRatio;

  /// Where the editable is inside the captured boundary, in logical pixels.
  final Offset origin;

  /// The red channel at a device pixel. The background is black and the
  /// highlight white, so one channel carries the blend.
  int level(int x, int y) => rgba.getUint8((y * image.width + x) * 4);
}

Rect _scale(Rect rect, double factor) => Rect.fromLTRB(
  rect.left * factor,
  rect.top * factor,
  rect.right * factor,
  rect.bottom * factor,
);
